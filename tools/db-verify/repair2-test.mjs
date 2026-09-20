// ---------------------------------------------------------------------------
// Exercises R2 against a live-shaped replica:
//   · the invitation gate actually gates
//   · an invited owner can create exactly one workspace
//   · the six control RPCs exist and refuse non-admins
//   · control_delete_company removes the tenant via cascade
//
//   node tools/db-verify/repair2-test.mjs
// ---------------------------------------------------------------------------
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const G='\x1b[32m', R='\x1b[31m', D='\x1b[2m', X='\x1b[0m';
let pass=0, fail=0;
const ok  = (m)=>{ console.log(`  ${G}✓${X} ${m}`); pass++; };
const bad = (m)=>{ console.log(`  ${R}✗${X} ${m}`); fail++; };

const db = new PGlite();
const strip = (f) => readFileSync(join(root,f),'utf8')
  .split('-- ============================================================\n--  VERIFY')[0];

await db.exec(`
do $roles$
begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin noinherit bypassrls; end if;
end $roles$;
grant usage on schema public to anon, authenticated, service_role;
create schema if not exists auth;
grant usage on schema auth to anon, authenticated, service_role;
create table auth.users (id uuid primary key, email text);
create or replace function auth.uid() returns uuid language sql stable
  as $$ select nullif(current_setting('request.jwt.claim.sub', true),'')::uuid $$;

create table public.subscription_plans (
  id uuid primary key default gen_random_uuid(), code text not null unique,
  name text not null, description text, active boolean not null default true,
  currency text not null default 'USD',
  price_monthly numeric not null default 0, price_yearly numeric not null default 0,
  max_workers integer not null default 5, max_plants integer not null default 1,
  max_storage_bytes bigint not null default 524288000,
  max_files integer not null default 500, max_file_bytes bigint not null default 52428800,
  ai_requests_month integer not null default 50, ai_requests_day integer not null default 10,
  ai_requests_minute_user integer not null default 3,
  ai_input_tokens_month bigint not null default 250000,
  ai_output_tokens_month bigint not null default 100000,
  retention_days integer not null default 365, features jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now());

create table public.organizations (
  id uuid primary key default gen_random_uuid(), name text not null, slug text,
  logo_path text, created_by uuid not null, created_at timestamptz not null default now(),
  commercial_status text not null default 'active', status_reason text,
  trial_ends_at timestamptz, suspended_at timestamptz, deletion_scheduled_at timestamptz,
  commercial_updated_at timestamptz not null default now());

create table public.organization_members (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null, role text not null, active boolean not null default true,
  created_at timestamptz not null default now(), permissions jsonb not null default '{}'::jsonb,
  deactivated_at timestamptz, updated_at timestamptz not null default now(),
  primary key (organization_id, user_id));

create table public.organization_subscriptions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plan_id uuid not null references public.subscription_plans(id),
  status text not null default 'trial', provider text,
  provider_customer_id text, provider_subscription_id text,
  current_period_start timestamptz not null default now(),
  current_period_end timestamptz, trial_ends_at timestamptz,
  cancel_at_period_end boolean not null default false, grace_ends_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now());

create table public.plants (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null, location text, created_at timestamptz not null default now());

create table public.plant_members (
  plant_id uuid not null references public.plants(id) on delete cascade,
  user_id uuid not null, created_at timestamptz not null default now(),
  primary key (plant_id, user_id));

-- live FK shapes: these four reference plants(id) with NO on-delete rule,
-- and ai_usage.organization_id has no rule either. This is what R2 handles.
create table public.ai_usage (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  plant_id uuid references public.plants(id),
  user_id uuid, created_at timestamptz not null default now());
create table public.manuals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id uuid references public.plants(id), title text);
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id uuid references public.plants(id), body text);
create table public.report_dispatches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id uuid references public.plants(id), sent_at timestamptz default now());
-- a representative cascading child
create table public.work_orders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id uuid references public.plants(id) on delete cascade, title text);

create or replace function public.effective_company_limit(
  p_organization_id uuid, p_metric text, p_base bigint)
returns bigint language plpgsql stable security definer
as $fn$ begin return p_base; end $fn$;

create or replace function public.enforce_plant_plan_limit()
returns trigger language plpgsql security definer set search_path to 'public'
as $fn$
declare base_limit bigint; limit_value bigint; used bigint;
begin
  select p.max_plants into base_limit from organization_subscriptions s
    join subscription_plans p on p.id=s.plan_id
   where s.organization_id=new.organization_id and s.status in('active','trial');
  if base_limit is null then raise exception 'Active subscription required'; end if;
  limit_value := effective_company_limit(new.organization_id,'plants',base_limit);
  select count(*) into used from plants where organization_id=new.organization_id and id<>new.id;
  if used+1 > limit_value then raise exception 'Plant limit of % reached', limit_value; end if;
  return new;
end $fn$;
create trigger plants_plan_limit before insert on public.plants
  for each row execute function public.enforce_plant_plan_limit();

-- platform admin switch we can flip during the test
create table public.platform_admins (user_id uuid primary key, active boolean not null default true);
create or replace function public.is_platform_admin() returns boolean
language sql stable security definer set search_path to 'public'
as $$ select exists(select 1 from public.platform_admins
                     where user_id = auth.uid() and active) $$;
`);

const ADMIN = '99999999-9999-9999-9999-999999999999';
const OWNER = '11111111-1111-1111-1111-111111111111';
const RANDO = '22222222-2222-2222-2222-222222222222';
await db.exec(`
insert into auth.users(id,email) values
  ('${ADMIN}','xeebawan2@gmail.com'),
  ('${OWNER}','owner@acme.test'),
  ('${RANDO}','nobody@example.com');
insert into public.platform_admins(user_id) values ('${ADMIN}');
`);
const as = async (uid, sql) => { await db.exec(`set request.jwt.claim.sub = '${uid}';`); return db.exec(sql); };
const q  = async (uid, sql) => { await db.exec(`set request.jwt.claim.sub = '${uid}';`); return (await db.query(sql)).rows; };

console.log(`${D}── apply R1 then R2 ──${X}`);
try { await db.exec(strip('supabase/repairs/R1-fix-organization-creation.sql')); ok('R1 applies'); }
catch(e){ bad(`R1 failed: ${e.message}`); }
try { await db.exec(strip('supabase/repairs/R2-control-center.sql')); ok('R2 applies'); }
catch(e){ bad(`R2 failed: ${e.message}`); }

console.log(`\n${D}── the gate ──${X}`);
let e1=null;
try { await as(RANDO, `select * from public.create_organization('Pirate Co','P1');`); }
catch(e){ e1=e.message; }
e1 && /approved by HSB Fix Services/i.test(e1)
  ? ok('uninvited user is refused')
  : bad(`expected the invitation refusal, got: ${e1 ?? 'none — the gate is open!'}`);

console.log(`\n${D}── control_invite_owner ──${X}`);
let e2=null;
try { await as(RANDO, `select public.control_invite_owner('x@y.com','X Co');`); }
catch(e){ e2=e.message; }
e2 && /Platform administrator required/i.test(e2)
  ? ok('non-admin cannot issue invitations')
  : bad(`expected admin-required, got: ${e2 ?? 'none'}`);

try {
  await as(ADMIN, `select public.control_invite_owner('owner@acme.test','Acme Mills','Unit 1','trial',7);`);
  ok('admin issues an invitation');
} catch(e){ bad(`invite failed: ${e.message}`); }

const inv = await q(ADMIN, `select email, company_name, plan_code, trial_days from public.owner_invitations`);
inv.length===1 && inv[0].email==='owner@acme.test' && inv[0].plan_code==='trial'
  ? ok(`invitation stored: ${inv[0].company_name} / ${inv[0].plan_code} / ${inv[0].trial_days}d`)
  : bad(`unexpected invitation rows: ${JSON.stringify(inv)}`);

console.log(`\n${D}── redeeming it ──${X}`);
try { await as(OWNER, `select * from public.create_organization('ignored','ignored');`); ok('invited owner creates the workspace'); }
catch(e){ bad(`redeem failed: ${e.message}`); }

const org = (await q(ADMIN,`select name, commercial_status from public.organizations`))[0];
org && org.name==='Acme Mills'
  ? ok(`company name came from the invitation, not the form: "${org.name}"`)
  : bad(`expected 'Acme Mills', got ${JSON.stringify(org)}`);

const sub = (await q(ADMIN,`select s.status, p.code from public.organization_subscriptions s
                            join public.subscription_plans p on p.id=s.plan_id`))[0];
sub && sub.status==='trial' ? ok(`subscription attached (${sub.code}/${sub.status})`) : bad(`no subscription: ${JSON.stringify(sub)}`);

const used = (await q(ADMIN,`select used_at, created_org_id from public.owner_invitations`))[0];
used.used_at && used.created_org_id ? ok('invitation marked used and linked to the company') : bad('invitation not consumed');

let e3=null;
try { await as(OWNER, `select * from public.create_organization('Second','S');`); }
catch(e){ e3=e.message; }
e3 ? ok('the same invitation cannot be reused') : bad('invitation was reusable — gate leaks!');

console.log(`\n${D}── control_delete_company ──${X}`);
const oid = (await q(ADMIN,`select id from public.organizations limit 1`))[0].id;
const pid = (await q(ADMIN,`select id from public.plants limit 1`))[0].id;
await db.exec(`
  insert into public.ai_usage(organization_id,plant_id,user_id) values ('${oid}','${pid}','${OWNER}');
  insert into public.manuals(organization_id,plant_id,title) values ('${oid}','${pid}','Pump manual');
  insert into public.notifications(organization_id,plant_id,body) values ('${oid}','${pid}','hi');
  insert into public.report_dispatches(organization_id,plant_id) values ('${oid}','${pid}');
  insert into public.work_orders(organization_id,plant_id,title) values ('${oid}','${pid}','WO-1');
`);
ok('seeded tenant rows incl. the four no-cascade FKs');

let e4=null;
try { await as(RANDO, `select public.control_delete_company('${oid}','Acme Mills');`); }
catch(e){ e4=e.message; }
e4 && /Platform administrator required/i.test(e4) ? ok('non-admin cannot delete a company') : bad(`expected refusal, got ${e4}`);

let e5=null;
try { await as(ADMIN, `select public.control_delete_company('${oid}','Wrong Name');`); }
catch(e){ e5=e.message; }
e5 && /Type the company name exactly/i.test(e5) ? ok('wrong confirmation is refused') : bad(`expected name-confirmation error, got ${e5}`);

try { await as(ADMIN, `select public.control_delete_company('${oid}','Acme Mills');`); ok('admin deletes the company'); }
catch(e){ bad(`delete failed: ${e.message}`); }

const left = (await q(ADMIN,`
  select (select count(*)::int from public.organizations) o,
         (select count(*)::int from public.plants) p,
         (select count(*)::int from public.ai_usage) a,
         (select count(*)::int from public.manuals) m,
         (select count(*)::int from public.work_orders) w,
         (select count(*)::int from public.organization_members) mem,
         (select count(*)::int from public.organization_subscriptions) s`))[0];
Object.values(left).every(v=>v===0)
  ? ok('every tenant row is gone — cascades did the rest')
  : bad(`rows survived: ${JSON.stringify(left)}`);

console.log(`\n${D}── idempotency ──${X}`);
try { await db.exec(strip('supabase/repairs/R2-control-center.sql')); ok('R2 re-runs cleanly'); }
catch(e){ bad(`second run failed: ${e.message}`); }

console.log(fail ? `\n${R}${fail} FAILED${X}, ${pass} passed\n`
                 : `\n${G}ALL ${pass} CONTROL-CENTER CHECKS PASSED${X}\n`);
await db.close();
process.exit(fail?1:0);
