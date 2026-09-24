// ---------------------------------------------------------------------------
// R6 — fix "duplicate key ... organization_subscriptions_organization_id_key"
// when a client creates their company workspace.
//
// Root cause reproduced here EXACTLY as it happens live:
//   * organizations has an AFTER INSERT trigger (organization_commercial_defaults
//     -> create_default_commercial_records) that inserts ONE trial subscription
//     row, keyed by organization_id, with ON CONFLICT DO NOTHING.
//   * create_organization() ALSO inserts a subscription row for the same org,
//     but WITHOUT on conflict -> it collides with the trigger's row ->
//     "duplicate key value violates unique constraint
//      organization_subscriptions_organization_id_key".
//
// This test: (1) proves the OLD function raises the duplicate-key error,
//            (2) proves the R6 function succeeds and leaves exactly ONE
//                subscription, one org, one plant, one membership.
//
//   node tools/db-verify/repair6-test.mjs
// ---------------------------------------------------------------------------
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';

const G='\x1b[32m', R='\x1b[31m', D='\x1b[2m', X='\x1b[0m';
let pass=0, fail=0;
const ok  = (m)=>{ console.log(`  ${G}✓${X} ${m}`); pass++; };
const bad = (m)=>{ console.log(`  ${R}✗${X} ${m}`); fail++; };
const sect= (m)=>console.log(`${D}── ${m} ──${X}`);
const db = new PGlite();
const q = async (sql)=> (await db.query(sql)).rows;

const CLIENT = '11111111-1111-1111-1111-111111111111';
const asClient = ()=>db.exec(`select set_config('request.jwt.claim.sub','${CLIENT}',false);`);

// ---- live-shaped schema (only the columns the real functions touch) --------
await db.exec(`
create schema if not exists auth;
create table auth.users(id uuid primary key, email text);
create or replace function auth.uid() returns uuid language sql stable
  as $$ select nullif(current_setting('request.jwt.claim.sub', true),'')::uuid $$;

create table subscription_plans(
  id uuid primary key default gen_random_uuid(), code text unique, name text,
  active boolean default true, max_workers int default 5, max_plants int default 1,
  features jsonb not null default '{}'::jsonb, created_at timestamptz default now());

create table organizations(
  id uuid primary key default gen_random_uuid(), name text not null, slug text,
  created_by uuid, commercial_status text default 'active',
  trial_ends_at timestamptz, status_reason text,
  commercial_updated_at timestamptz default now());

create table organization_subscriptions(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references organizations(id) on delete cascade,
  plan_id uuid references subscription_plans(id), status text default 'active',
  current_period_start timestamptz, current_period_end timestamptz,
  trial_ends_at timestamptz,
  created_at timestamptz default now(), updated_at timestamptz default now(),
  constraint organization_subscriptions_organization_id_key unique(organization_id));

create table organization_members(
  organization_id uuid, user_id uuid, role text, active boolean default true,
  created_at timestamptz default now());

create table plants(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid, name text, created_at timestamptz default now());

create table plant_members(plant_id uuid, user_id uuid, created_at timestamptz default now());

create table data_retention_policies(
  organization_id uuid primary key, created_at timestamptz default now());

create table quota_overrides(
  id uuid primary key default gen_random_uuid(), organization_id uuid, metric text,
  override_type text, value bigint, active boolean default true, ends_at timestamptz);

create table owner_invitations(
  id uuid primary key default gen_random_uuid(), email text, company_name text,
  plant_name text, plan_code text, trial_days int default 7,
  used_at timestamptz, used_by uuid, revoked_at timestamptz,
  expires_at timestamptz default now()+interval '30 days',
  created_org_id uuid, signup_request_id uuid, created_at timestamptz default now());

create table signup_requests(
  id uuid primary key default gen_random_uuid(), status text, reviewed_at timestamptz);

-- seed the trial plan + the client's account + their approved invitation
insert into subscription_plans(code,name,max_plants,max_workers) values('trial','Trial',1,5);
insert into auth.users(id,email) values('${CLIENT}','client@pakistansynthetic.com');
insert into owner_invitations(email,company_name,plant_name,plan_code,trial_days)
  values('client@pakistansynthetic.com','Pakistan Synthetic Limited','Hub','trial',7);
`);

// ---- LIVE trigger: create_default_commercial_records (verbatim behaviour) --
await db.exec(`
create or replace function public.create_default_commercial_records()
returns trigger language plpgsql security definer set search_path to 'public' as $f$
declare p uuid;
begin
  select id into p from public.subscription_plans where code='trial';
  update public.organizations set commercial_status='trial',trial_ends_at=now()+interval '30 days' where id=new.id;
  insert into public.organization_subscriptions(organization_id,plan_id,status,current_period_start,current_period_end,trial_ends_at)
    values(new.id,p,'trial',now(),now()+interval '30 days',now()+interval '30 days') on conflict(organization_id) do nothing;
  insert into public.data_retention_policies(organization_id) values(new.id) on conflict do nothing;
  return new;
end $f$;
create trigger organization_commercial_defaults after insert on public.organizations
  for each row execute function create_default_commercial_records();

-- LIVE trigger: enforce_plant_plan_limit (needs an active/trial subscription) -
create or replace function public.enforce_plant_plan_limit()
returns trigger language plpgsql security definer set search_path to 'public' as $f$
declare base_limit bigint; used bigint;
begin
  select p.max_plants into base_limit from organization_subscriptions s
    join subscription_plans p on p.id=s.plan_id
   where s.organization_id=new.organization_id and s.status in('active','trial');
  if base_limit is null then raise exception 'Active subscription required'; end if;
  select count(*) into used from plants where organization_id=new.organization_id and id<>new.id;
  if used+1>base_limit then raise exception 'Plant limit of % reached',base_limit; end if;
  return new;
end $f$;
create trigger plants_enforce_plan_limit before insert on public.plants
  for each row execute function enforce_plant_plan_limit();
`);

// ===========================================================================
sect('1. reproduce the BUG (current live create_organization — R2 body, no ON CONFLICT)');
// ===========================================================================
await db.exec(`
create or replace function public.create_organization(org_name text, plant_name text)
returns table(organization_id uuid, plant_id uuid)
language plpgsql security definer set search_path to 'public' as $function$
declare o uuid; p uuid; caller_email text;
  inv public.owner_invitations%rowtype; plan public.subscription_plans%rowtype; trial_end timestamptz;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select lower(email) into caller_email from auth.users where id = auth.uid();
  select * into inv from public.owner_invitations
   where lower(email)=caller_email and used_at is null and revoked_at is null and expires_at>now()
   order by created_at desc limit 1;
  if inv.id is null then raise exception 'Accounts are approved by HSB Fix Services.' using errcode='check_violation'; end if;
  select * into plan from public.subscription_plans where code = inv.plan_code;
  if plan.id is null then raise exception 'Configured plan % does not exist', inv.plan_code; end if;
  insert into public.organizations(name,slug,created_by,commercial_status)
    values(coalesce(nullif(inv.company_name,''),org_name),
      lower(regexp_replace(coalesce(nullif(inv.company_name,''),org_name),'[^a-zA-Z0-9]+','-','g'))||'-'||substr(gen_random_uuid()::text,1,6),
      auth.uid(), case when inv.trial_days>0 then 'trial' else 'active' end)
    returning id into o;
  insert into public.organization_members(organization_id,user_id,role,active,created_at)
    values(o,auth.uid(),'owner',true,now());
  trial_end := case when inv.trial_days>0 then now()+make_interval(days=>inv.trial_days) end;
  insert into public.organization_subscriptions
    (organization_id,plan_id,status,current_period_start,current_period_end,trial_ends_at)
    values(o,plan.id,case when inv.trial_days>0 then 'trial' else 'active' end,
      now(),coalesce(trial_end,now()+interval '30 days'),trial_end);
  insert into public.plants(organization_id,name)
    values(o,coalesce(nullif(inv.plant_name,''),plant_name)) returning id into p;
  insert into public.plant_members(plant_id,user_id,created_at) values(p,auth.uid(),now());
  update public.owner_invitations set used_at=now(),used_by=auth.uid(),created_org_id=o where id=inv.id;
  return query select o,p;
end $function$;
`);

await asClient();
let reproduced=false, reproMsg='';
try {
  await q(`select * from create_organization('Pakistan Synthetic Limited','Hub')`);
} catch(e){ reproduced=true; reproMsg=e.message; }
if (reproduced && /organization_subscriptions_organization_id_key/.test(reproMsg))
  ok(`old function raises the client's exact error: ${D}${reproMsg}${X}`);
else if (reproduced) bad(`raised, but different error: ${reproMsg}`);
else bad(`old function did NOT error — cannot reproduce the client's bug`);

// nothing should have been committed (whole function is one transaction)
const afterFail = (await q(`select
  (select count(*) from organizations) o,
  (select count(*) from organization_subscriptions) s`))[0];
if (Number(afterFail.o)===0 && Number(afterFail.s)===0)
  ok('failed attempt left NO orphan org/subscription (clean rollback)');
else bad(`rollback incomplete: orgs=${afterFail.o} subs=${afterFail.s}`);

// ===========================================================================
sect('2. apply R6 fix and prove workspace creation now succeeds');
// ===========================================================================
// Load the real R6 function body from the committed repair file so the test
// exercises exactly what we ship (not a hand-copy).
const r6 = readFileSync(new URL('../../supabase/repairs/R6-fix-workspace-subscription.sql', import.meta.url), 'utf8');
// strip transaction wrappers / grants that PGlite-in-one-tx dislikes
const r6fn = r6
  .replace(/^\s*begin\s*;/im,'')
  .replace(/^\s*commit\s*;/im,'')
  .replace(/^\s*grant[^\n;]*;/gim,'')
  .replace(/--\s*VERIFY[\s\S]*$/i,'');
await db.exec(r6fn);
ok('R6 create_organization installed from supabase/repairs/R6-fix-workspace-subscription.sql');

await asClient();
let created=null, createErr='';
try { created = (await q(`select * from create_organization('Pakistan Synthetic Limited','Hub')`))[0]; }
catch(e){ createErr=e.message; }
if (created && created.organization_id) ok('client creates "Pakistan Synthetic Limited" workspace — no error');
else bad(`workspace creation still fails: ${createErr}`);

if (created){
  const row = (await q(`select
    (select count(*) from organizations)             orgs,
    (select count(*) from organization_subscriptions where organization_id='${created.organization_id}') subs,
    (select count(*) from plants where organization_id='${created.organization_id}')       plants,
    (select count(*) from organization_members where organization_id='${created.organization_id}' and role='owner') owners,
    (select status from organization_subscriptions where organization_id='${created.organization_id}') status,
    (select name from organizations where id='${created.organization_id}') name`))[0];
  Number(row.orgs)===1        ? ok('exactly one organization exists')            : bad(`orgs=${row.orgs}`);
  Number(row.subs)===1        ? ok('exactly ONE subscription row (no duplicate)') : bad(`subs=${row.subs}`);
  Number(row.plants)===1      ? ok('the "Hub" plant was created')                 : bad(`plants=${row.plants}`);
  Number(row.owners)===1      ? ok('client is the owner')                         : bad(`owners=${row.owners}`);
  row.status==='trial'        ? ok('subscription is on the trial plan (status=trial)') : bad(`status=${row.status}`);
  row.name==='Pakistan Synthetic Limited' ? ok('company name is correct')         : bad(`name=${row.name}`);
}

// ===========================================================================
sect('3. idempotency & second-company sanity');
// ===========================================================================
// the invitation is now used -> a second attempt is correctly gated
let secondBlocked=false;
try { await q(`select * from create_organization('Another Co','P1')`); }
catch(e){ secondBlocked = /approved by HSB/.test(e.message); }
secondBlocked ? ok('re-run after invite consumed is blocked (invite is single-use)')
              : bad('used invitation was accepted again');

// a fresh client with their own invite also succeeds (no cross-company collision)
const CLIENT2='22222222-2222-2222-2222-222222222222';
await db.exec(`
insert into auth.users(id,email) values('${CLIENT2}','ops@zainab-textiles.com');
insert into owner_invitations(email,company_name,plant_name,plan_code,trial_days)
  values('ops@zainab-textiles.com','Zainab Textiles','Unit 1','trial',7);
select set_config('request.jwt.claim.sub','${CLIENT2}',false);`);
let second=null;
try { second=(await q(`select * from create_organization('Zainab Textiles','Unit 1')`))[0]; } catch(e){ second=null; var e2=e.message; }
second ? ok('a different client with their own invite also creates a workspace')
       : bad(`second client failed: ${typeof e2!=='undefined'?e2:''}`);
if (second){
  const n=(await q(`select count(*) c from organization_subscriptions`))[0].c;
  Number(n)===2 ? ok('two companies -> exactly two subscriptions total') : bad(`total subs=${n}`);
}

// ---------------------------------------------------------------------------
console.log(`\n${fail? R : G}R6 workspace-creation fix: ${pass} passed, ${fail} failed${X}`);
process.exit(fail?1:0);
