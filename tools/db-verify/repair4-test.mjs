// ---------------------------------------------------------------------------
// R4: per-company feature control.
// Proves the plan-code correction matters, and that grants/blocks compose.
//
//   node tools/db-verify/repair4-test.mjs
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
do $r$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin noinherit; end if;
end $r$;
grant usage on schema public to anon, authenticated;
create schema if not exists auth;
grant usage on schema auth to anon, authenticated;
create table auth.users(id uuid primary key, email text);
create or replace function auth.uid() returns uuid language sql stable
  as $$ select nullif(current_setting('request.jwt.claim.sub', true),'')::uuid $$;

create table public.subscription_plans(
  id uuid primary key default gen_random_uuid(), code text unique, name text,
  description text, active boolean default true, currency text default 'PKR',
  price_monthly numeric default 0, price_yearly numeric default 0,
  max_workers int default 5, max_plants int default 1,
  max_storage_bytes bigint default 0, max_files int default 0,
  max_file_bytes bigint default 0, ai_requests_month int default 0,
  ai_requests_day int default 0, ai_requests_minute_user int default 0,
  ai_input_tokens_month bigint default 0, ai_output_tokens_month bigint default 0,
  retention_days int default 365, features jsonb not null default '{}'::jsonb,
  created_at timestamptz default now(), updated_at timestamptz default now());

-- NOTE: exactly the live shape — there is NO plan column here.
create table public.organizations(
  id uuid primary key default gen_random_uuid(), name text not null, slug text,
  logo_path text, created_by uuid not null, created_at timestamptz default now(),
  commercial_status text not null default 'active', status_reason text,
  trial_ends_at timestamptz, suspended_at timestamptz,
  deletion_scheduled_at timestamptz, commercial_updated_at timestamptz default now());

create table public.organization_members(
  organization_id uuid references public.organizations(id) on delete cascade,
  user_id uuid, role text, active boolean default true,
  created_at timestamptz default now(), primary key(organization_id,user_id));

create table public.organization_subscriptions(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  plan_id uuid references public.subscription_plans(id),
  status text not null default 'trial',
  current_period_start timestamptz default now(), current_period_end timestamptz,
  trial_ends_at timestamptz, created_at timestamptz default now(),
  updated_at timestamptz default now());

-- live shape, incl. the narrow CHECK that R4 must remove
create table public.company_feature_blocks(
  organization_id uuid not null references public.organizations(id) on delete cascade,
  feature text not null check (feature in
    ('gemini','deep_search','vision_scanner','condition_analysis','uploads')),
  blocked boolean not null default true, reason text,
  expires_at timestamptz, created_at timestamptz default now(),
  primary key(organization_id,feature));

create table public.platform_admins(user_id uuid primary key, active boolean default true);
create or replace function public.is_platform_admin() returns boolean
language sql stable security definer set search_path to 'public'
as $$ select exists(select 1 from public.platform_admins where user_id=auth.uid() and active) $$;
`);

const ADMIN='99999999-9999-9999-9999-999999999999';
const MEMBER='11111111-1111-1111-1111-111111111111';
const OUTSIDER='22222222-2222-2222-2222-222222222222';
await db.exec(`
insert into auth.users(id,email) values
 ('${ADMIN}','admin@hsbfix.org'),('${MEMBER}','m@acme.test'),('${OUTSIDER}','x@other.test');
insert into public.platform_admins(user_id) values ('${ADMIN}');
insert into public.subscription_plans(code,name,features)
 values ('professional','Professional','{"work_orders":true,"gemini":true,"analytics":false}'::jsonb);
insert into public.organizations(id,name,created_by)
 values ('33333333-3333-3333-3333-333333333333','Acme Mills','${ADMIN}');
insert into public.organization_members(organization_id,user_id,role)
 values ('33333333-3333-3333-3333-333333333333','${MEMBER}','owner');
insert into public.organization_subscriptions(organization_id,plan_id,status)
 select '33333333-3333-3333-3333-333333333333', id, 'active'
   from public.subscription_plans where code='professional';
`);
const ORG='33333333-3333-3333-3333-333333333333';
const q = async (uid,sql)=>{ await db.exec(`set request.jwt.claim.sub='${uid}';`);
                             return (await db.query(sql)).rows; };

console.log(`${D}── apply R4 ──${X}`);
try { await db.exec(strip('supabase/repairs/R4-company-features.sql')); ok('R4 applies'); }
catch(e){ bad(`R4 failed: ${e.message}`); }

console.log(`\n${D}── the plan-code correction ──${X}`);
let f = (await q(MEMBER, `select public.organization_effective_features('${ORG}') f`))[0].f;
f.work_orders === true && f.gemini === true
  ? ok(`plan features resolved through organization_subscriptions: ${JSON.stringify(f)}`)
  : bad(`plan features not found — got ${JSON.stringify(f)}. The packaged version read organizations.plan_code, which does not exist, and would return {} here.`);

console.log(`\n${D}── grants add, blocks remove ──${X}`);
await db.exec(`insert into public.company_feature_grants(organization_id,feature,granted)
               values ('${ORG}','vision_scanner',true);`);
f = (await q(MEMBER, `select public.organization_effective_features('${ORG}') f`))[0].f;
f.vision_scanner === true ? ok('a grant adds a module the plan does not include')
                          : bad(`grant ignored: ${JSON.stringify(f)}`);

await db.exec(`insert into public.company_feature_blocks(organization_id,feature,blocked)
               values ('${ORG}','gemini',true);`);
f = (await q(MEMBER, `select public.organization_effective_features('${ORG}') f`))[0].f;
f.gemini === false ? ok('a block removes a module the plan does include')
                   : bad(`block ignored: ${JSON.stringify(f)}`);

console.log(`\n${D}── the widened feature list ──${X}`);
let e=null;
try { await db.exec(`insert into public.company_feature_blocks(organization_id,feature)
                     values ('${ORG}','procurement_requests');`); }
catch(err){ e=err.message; }
e ? bad(`still constrained: ${e}`)
  : ok('modules beyond the original five can now be blocked');

console.log(`\n${D}── security ──${X}`);
e=null;
try { await q(OUTSIDER, `select public.organization_effective_features('${ORG}')`); }
catch(err){ e=err.message; }
e && /Not authorised/i.test(e) ? ok('an outsider is refused')
                               : bad(`expected refusal, got: ${e ?? 'none'}`);

try {
  const r = await q(ADMIN, `select public.organization_effective_features('${ORG}') f`);
  r.length ? ok('a platform admin may read any company') : bad('admin got nothing');
} catch(err){ bad(`admin refused: ${err.message}`); }

// members read-only on grants
await db.exec(`set role authenticated;`);
e=null;
try {
  await db.exec(`set request.jwt.claim.sub='${MEMBER}';`);
  await db.exec(`insert into public.company_feature_grants(organization_id,feature)
                 values ('${ORG}','white_label');`);
} catch(err){ e=err.message; }
await db.exec(`reset role;`);
e ? ok('a member cannot grant themselves a module')
  : bad('a member was able to write to company_feature_grants!');

console.log(`\n${D}── idempotency ──${X}`);
try { await db.exec(strip('supabase/repairs/R4-company-features.sql')); ok('R4 re-runs cleanly'); }
catch(err){ bad(`second run failed: ${err.message}`); }

console.log(fail ? `\n${R}${fail} FAILED${X}, ${pass} passed\n`
                 : `\n${G}ALL ${pass} FEATURE-CONTROL CHECKS PASSED${X}\n`);
await db.close();
process.exit(fail?1:0);
