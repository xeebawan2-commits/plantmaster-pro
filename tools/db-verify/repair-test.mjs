// ---------------------------------------------------------------------------
// Proves the create_organization bug is real, then proves R1 fixes it.
//
// This does NOT use the reconstructed migrations. It builds a minimal replica
// of the LIVE schema, using the exact column definitions and the exact trigger
// body taken from reference/master-package/05-DATABASE/03-live-schema-snapshot/.
//
//   node tools/db-verify/repair-test.mjs
// ---------------------------------------------------------------------------
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const G = '\x1b[32m', R = '\x1b[31m', D = '\x1b[2m', X = '\x1b[0m';
let pass = 0, fail = 0;
const ok  = (m) => { console.log(`  ${G}✓${X} ${m}`); pass++; };
const bad = (m) => { console.log(`  ${R}✗${X} ${m}`); fail++; };

const db = new PGlite();

// -- minimal live-shaped schema --------------------------------------------
await db.exec(`
-- Supabase roles: PGlite is stock Postgres and has none of them.
do $roles$
begin
  if not exists (select 1 from pg_roles where rolname='anon') then
    create role anon nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then
    create role authenticated nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then
    create role service_role nologin noinherit bypassrls; end if;
end $roles$;
grant usage on schema public to anon, authenticated, service_role;

create schema if not exists auth;
grant usage on schema auth to anon, authenticated, service_role;
create table auth.users (id uuid primary key, email text);
create or replace function auth.uid() returns uuid language sql stable
  as $$ select nullif(current_setting('request.jwt.claim.sub', true),'')::uuid $$;

create table public.subscription_plans (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  active boolean not null default true,
  currency text not null default 'USD',
  price_monthly numeric not null default 0,
  price_yearly  numeric not null default 0,
  max_workers integer not null default 5,
  max_plants integer not null default 1,
  max_storage_bytes bigint not null default 524288000,
  max_files integer not null default 500,
  max_file_bytes bigint not null default 52428800,
  ai_requests_month integer not null default 50,
  ai_requests_day integer not null default 10,
  ai_requests_minute_user integer not null default 3,
  ai_input_tokens_month bigint not null default 250000,
  ai_output_tokens_month bigint not null default 100000,
  retention_days integer not null default 365,
  features jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text,
  logo_path text,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  commercial_status text not null default 'active',
  status_reason text,
  trial_ends_at timestamptz,
  suspended_at timestamptz,
  deletion_scheduled_at timestamptz,
  commercial_updated_at timestamptz not null default now()
);

create table public.organization_members (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null,
  role text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  permissions jsonb not null default '{}'::jsonb,
  deactivated_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (organization_id, user_id)
);

create table public.organization_subscriptions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plan_id uuid not null references public.subscription_plans(id),
  status text not null default 'trial',
  provider text, provider_customer_id text, provider_subscription_id text,
  current_period_start timestamptz not null default now(),
  current_period_end timestamptz,
  trial_ends_at timestamptz,
  cancel_at_period_end boolean not null default false,
  grace_ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.plants (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  location text,
  created_at timestamptz not null default now()
);

create table public.plant_members (
  plant_id uuid not null references public.plants(id) on delete cascade,
  user_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (plant_id, user_id)
);

-- verbatim from the live snapshot
create or replace function public.effective_company_limit(
  p_organization_id uuid, p_metric text, p_base bigint)
returns bigint language plpgsql stable security definer
as $fn$ begin return p_base; end $fn$;

create or replace function public.enforce_plant_plan_limit()
returns trigger language plpgsql security definer set search_path to 'public'
as $fn$
declare base_limit bigint; limit_value bigint; used bigint;
begin
  select p.max_plants into base_limit
    from organization_subscriptions s
    join subscription_plans p on p.id = s.plan_id
   where s.organization_id = new.organization_id
     and s.status in ('active','trial');
  if base_limit is null then raise exception 'Active subscription required'; end if;
  limit_value := effective_company_limit(new.organization_id,'plants',base_limit);
  select count(*) into used from plants
   where organization_id = new.organization_id and id <> new.id;
  if used + 1 > limit_value then raise exception 'Plant limit of % reached', limit_value; end if;
  return new;
end $fn$;

create trigger plants_plan_limit before insert on public.plants
  for each row execute function public.enforce_plant_plan_limit();
`);

const U = '11111111-1111-1111-1111-111111111111';
await db.exec(`insert into auth.users(id,email) values ('${U}','owner@example.com');`);
const asUser = async (sql) => {
  await db.exec(`set request.jwt.claim.sub = '${U}';`);
  return db.exec(sql);
};

console.log(`${D}── the live function, exactly as it exists today ──${X}`);

// verbatim live body
await db.exec(`
create or replace function public.create_organization(org_name text, plant_name text)
returns table(organization_id uuid, plant_id uuid)
language plpgsql security definer set search_path to 'public'
as $fn$
declare o uuid; p uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  insert into organizations(name,slug,created_by) values(org_name,lower(regexp_replace(org_name,'[^a-zA-Z0-9]+','-','g'))||'-'||substr(gen_random_uuid()::text,1,6),auth.uid()) returning id into o;
  insert into organization_members values(o,auth.uid(),'owner',true,now());
  insert into plants(organization_id,name) values(o,plant_name) returning id into p;
  insert into plant_members values(p,auth.uid(),now());
  return query select o,p;
end $fn$;
`);

let liveErr = null;
try {
  await asUser(`select * from public.create_organization('Acme Mills','Unit 1');`);
} catch (e) { liveErr = e.message; }

if (liveErr && /Active subscription required/i.test(liveErr))
  ok(`live version fails exactly as reported: "${liveErr.trim()}"`);
else
  bad(`expected 'Active subscription required', got: ${liveErr ?? 'no error — bug not reproduced'}`);

const { rows: after } = await db.query(`select count(*)::int n from public.organizations`);
after[0].n === 0
  ? ok('nothing was created — the whole transaction rolled back')
  : bad(`expected 0 organizations, found ${after[0].n}`);

console.log(`\n${D}── after applying R1 ──${X}`);

// apply the real repair file, minus its psql-only verify tail
let r1 = readFileSync(join(root,'supabase/repairs/R1-fix-organization-creation.sql'),'utf8');
r1 = r1.split('-- ============================================================\n--  VERIFY')[0];
try { await db.exec(r1); ok('R1 applies without error'); }
catch (e) { bad(`R1 failed to apply: ${e.message}`); }

let res = null, err2 = null;
try { res = await asUser(`select * from public.create_organization('Acme Mills','Unit 1');`); }
catch (e) { err2 = e.message; }
err2 ? bad(`still failing: ${err2}`) : ok('create_organization now succeeds');

const q = async (sql) => (await db.query(sql)).rows[0];
const counts = await q(`
  select (select count(*)::int from public.organizations) orgs,
         (select count(*)::int from public.organization_members) members,
         (select count(*)::int from public.organization_subscriptions) subs,
         (select count(*)::int from public.plants) plants,
         (select count(*)::int from public.plant_members) pmembers`);

for (const [k, want] of [['orgs',1],['members',1],['subs',1],['plants',1],['pmembers',1]])
  counts[k] === want ? ok(`${k}: ${counts[k]}`) : bad(`${k}: expected ${want}, got ${counts[k]}`);

const org = await q(`select commercial_status from public.organizations limit 1`);
org.commercial_status === 'trial'
  ? ok(`organization starts on 'trial'`)
  : bad(`commercial_status = ${org.commercial_status}, expected trial`);

const sub = await q(`select s.status, p.code from public.organization_subscriptions s
                     join public.subscription_plans p on p.id = s.plan_id limit 1`);
sub.status === 'trial' && sub.code === 'trial'
  ? ok(`subscription attached: plan=${sub.code} status=${sub.status}`)
  : bad(`subscription wrong: ${JSON.stringify(sub)}`);

// re-runnable?
try { await db.exec(r1); ok('R1 is idempotent — re-running is clean'); }
catch (e) { bad(`second run failed: ${e.message}`); }

// plan limit still enforced (max_plants = 1 on trial)
let limitErr = null;
try {
  const o = await q(`select id from public.organizations limit 1`);
  await db.exec(`insert into public.plants(organization_id,name) values ('${o.id}','Unit 2');`);
} catch (e) { limitErr = e.message; }
limitErr && /Plant limit/i.test(limitErr)
  ? ok('plan limits still enforced — trial is capped at 1 plant')
  : bad(`expected a plant-limit error, got: ${limitErr ?? 'none — limit not enforced!'}`);

// auth still required
let anonErr = null;
try {
  await db.exec(`set request.jwt.claim.sub = '';`);
  await db.exec(`select * from public.create_organization('Sneaky','X');`);
} catch (e) { anonErr = e.message; }
anonErr && /Authentication required/i.test(anonErr)
  ? ok('still refuses anonymous callers')
  : bad(`expected 'Authentication required', got: ${anonErr ?? 'none'}`);

console.log(
  fail ? `\n${R}${fail} FAILED${X}, ${pass} passed\n`
       : `\n${G}ALL ${pass} REPAIR CHECKS PASSED${X}\n`);
await db.close();
process.exit(fail ? 1 : 0);
