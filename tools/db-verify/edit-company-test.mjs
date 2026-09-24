// ---------------------------------------------------------------------------
// End-to-end: "the Control Center edits a SINGLE company's package".
//
// Uses the real live functions (platform_set_company, effective_company_limit)
// and R4's organization_effective_features, to prove the admin flow behind
// editCompanyPlan() does the right thing AND touches only the one company.
//
//   node tools/db-verify/edit-company-test.mjs
// ---------------------------------------------------------------------------
import { PGlite } from '@electric-sql/pglite';

const G='\x1b[32m', R='\x1b[31m', D='\x1b[2m', X='\x1b[0m';
let pass=0, fail=0;
const ok  = (m)=>{ console.log(`  ${G}✓${X} ${m}`); pass++; };
const bad = (m)=>{ console.log(`  ${R}✗${X} ${m}`); fail++; };
const sect= (m)=>console.log(`${D}── ${m} ──${X}`);
const db = new PGlite();

// ---- who am I? a GUC the stubbed auth helpers read -------------------------
const asAdmin  = async ()=>db.exec(`select set_config('app.is_admin','true',false); select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000aa',false);`);
const asNobody = async ()=>db.exec(`select set_config('app.is_admin','false',false); select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000bb',false);`);
const q = async (sql)=> (await db.query(sql)).rows;

await db.exec(`
create schema if not exists auth;
create or replace function auth.uid() returns uuid language sql stable
  as $$ select nullif(current_setting('request.jwt.claim.sub', true),'')::uuid $$;

-- live-shaped tables (exactly the columns the real functions touch) ----------
create table subscription_plans(
  id uuid primary key default gen_random_uuid(), code text unique, name text,
  active boolean default true, max_workers int default 5, max_plants int default 1,
  features jsonb not null default '{}'::jsonb, created_at timestamptz default now());

create table organizations(
  id uuid primary key default gen_random_uuid(), name text not null,
  commercial_status text default 'active', status_reason text,
  suspended_at timestamptz, deletion_scheduled_at timestamptz,
  commercial_updated_at timestamptz default now());

create table organization_subscriptions(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references organizations(id) on delete cascade,
  plan_id uuid references subscription_plans(id), status text default 'active',
  created_at timestamptz default now(), updated_at timestamptz default now());

create table organization_members(
  organization_id uuid, user_id uuid, role text, active boolean default true);

create table quota_overrides(
  id uuid primary key default gen_random_uuid(), organization_id uuid,
  metric text, override_type text, value bigint, active boolean default true,
  ends_at timestamptz, reason text, created_by uuid, created_at timestamptz default now());

create table company_feature_grants(
  organization_id uuid, feature text, granted boolean default true, expires_at timestamptz);
create table company_feature_blocks(
  organization_id uuid, feature text, blocked boolean default true, expires_at timestamptz);

create table admin_action_logs(
  id uuid primary key default gen_random_uuid(), admin_user_id uuid, action text,
  target_type text, target_id text, organization_id uuid, reason text,
  details jsonb, created_at timestamptz default now());

-- stubbed auth helpers -------------------------------------------------------
create or replace function is_platform_admin() returns boolean language sql stable
  as $$ select coalesce(current_setting('app.is_admin', true),'false')='true' $$;
create or replace function platform_has_permission(p text) returns boolean language sql stable
  as $$ select coalesce(current_setting('app.is_admin', true),'false')='true' $$;
`);

// ---- the REAL functions, verbatim from live / R4 --------------------------
await db.exec(`
CREATE OR REPLACE FUNCTION public.platform_set_company(p_organization_id uuid, p_status text, p_plan_code text DEFAULT NULL::text, p_reason text DEFAULT NULL::text)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$declare plan_uuid uuid;subscription_state text;begin if not public.platform_has_permission('companies.manage') then raise exception 'Permission required';end if;if p_status not in('trial','active','past_due','suspended','cancelled','deletion_pending') then raise exception 'Invalid company status';end if;if p_plan_code is not null then select id into plan_uuid from subscription_plans where code=p_plan_code and active;if plan_uuid is null then raise exception 'Plan not found';end if;end if;update organizations set commercial_status=p_status,status_reason=p_reason,suspended_at=case when p_status='suspended' then now() else null end,deletion_scheduled_at=case when p_status='deletion_pending' then coalesce(deletion_scheduled_at,now()+interval '30 days') else null end,commercial_updated_at=now() where id=p_organization_id;subscription_state:=case when p_status in('active','trial','past_due','suspended','cancelled') then p_status else 'cancelled' end;update organization_subscriptions set plan_id=coalesce(plan_uuid,plan_id),status=subscription_state,updated_at=now() where organization_id=p_organization_id;insert into admin_action_logs(admin_user_id,action,target_type,target_id,organization_id,reason,details) values(auth.uid(),'company_commercial_updated','organization',p_organization_id::text,p_organization_id,p_reason,jsonb_build_object('status',p_status,'plan_code',p_plan_code));end$function$;

CREATE OR REPLACE FUNCTION public.effective_company_limit(p_organization_id uuid, p_metric text, p_base bigint)
 RETURNS bigint LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$declare absolute_value bigint;bonus_value bigint;blocked boolean;begin
 select exists(select 1 from quota_overrides where organization_id=p_organization_id and metric=p_metric and override_type='block' and active and (ends_at is null or ends_at>now())) into blocked;if blocked then return 0;end if;
 select value into absolute_value from quota_overrides where organization_id=p_organization_id and metric=p_metric and override_type='absolute' and active and (ends_at is null or ends_at>now()) order by created_at desc limit 1;
 select coalesce(sum(value),0) into bonus_value from quota_overrides where organization_id=p_organization_id and metric=p_metric and override_type='bonus' and active and (ends_at is null or ends_at>now());
 return greatest(0,coalesce(absolute_value,p_base)+coalesce(bonus_value,0));end$function$;

create or replace function organization_effective_features(p_organization_id uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_features jsonb := '{}'::jsonb; r record;
begin
  if p_organization_id is null then return '{}'::jsonb; end if;
  if not (public.is_platform_admin() or exists(select 1 from organization_members m where m.organization_id=p_organization_id and m.user_id=auth.uid() and coalesce(m.active,true))) then
     raise exception 'Not authorised for this organization'; end if;
  select coalesce(sp.features,'{}'::jsonb) into v_features
    from organization_subscriptions s join subscription_plans sp on sp.id=s.plan_id
   where s.organization_id=p_organization_id and s.status in('active','trial')
   order by s.created_at desc limit 1;
  v_features := coalesce(v_features,'{}'::jsonb);
  for r in select feature from company_feature_grants where organization_id=p_organization_id and coalesce(granted,true) and (expires_at is null or expires_at>now()) loop
     v_features := v_features || jsonb_build_object(r.feature,true); end loop;
  for r in select feature from company_feature_blocks where organization_id=p_organization_id and coalesce(blocked,true) and (expires_at is null or expires_at>now()) loop
     v_features := v_features || jsonb_build_object(r.feature,false); end loop;
  return v_features;
end $$;
`);

// ---- seed: two plans, two companies BOTH on basic -------------------------
await db.exec(`
insert into subscription_plans(code,name,max_workers,features) values
 ('basic','Basic',5, '{"work_orders":true,"analytics":false,"predictive_maintenance":false,"white_label":false}'::jsonb),
 ('professional','Professional',25,'{"work_orders":true,"analytics":true,"predictive_maintenance":true,"white_label":false}'::jsonb);

insert into organizations(id,name) values
 ('00000000-0000-0000-0000-00000000000A','Company A (edited)'),
 ('00000000-0000-0000-0000-00000000000B','Company B (control)');

insert into organization_subscriptions(organization_id,plan_id,status)
 select o.id, p.id, 'active' from organizations o cross join subscription_plans p where p.code='basic';
`);

const planOf = async (org)=> (await q(`select sp.code from organization_subscriptions s join subscription_plans sp on sp.id=s.plan_id where s.organization_id='${org}'`))[0]?.code;
const featOf = async (org)=> (await q(`select organization_effective_features('${org}') f`))[0].f;
const limOf  = async (org,base)=> Number((await q(`select effective_company_limit('${org}','workers',${base}) v`))[0].v);
const A='00000000-0000-0000-0000-00000000000A', B='00000000-0000-0000-0000-00000000000B';

console.log('\nPlantMaster — edit a SINGLE company package (end-to-end)\n');

sect('starting state: both companies on Basic');
(await planOf(A))==='basic' ? ok('Company A starts on basic') : bad('A not basic');
(await planOf(B))==='basic' ? ok('Company B starts on basic') : bad('B not basic');

sect('security: a non-admin cannot edit a company');
await asNobody();
try { await db.exec(`select platform_set_company('${A}','active','professional','hack')`); bad('non-admin was allowed to edit'); }
catch(e){ ok('non-admin is refused ("'+String(e.message).slice(0,40)+'…")'); }

sect('admin edits Company A: change package Basic -> Professional');
await asAdmin();
await db.exec(`select platform_set_company('${A}','active','professional','Upgrade agreed with customer')`);
(await planOf(A))==='professional' ? ok('Company A is now on professional') : bad('A did not move to professional');
(await planOf(B))==='basic'        ? ok('Company B is UNTOUCHED (still basic)') : bad('B changed — isolation broken!');

sect('the change flips the right features for A only');
let fa=await featOf(A), fb=await featOf(B);
fa.analytics===true  ? ok('A now has analytics (from professional)') : bad('A missing analytics');
fa.predictive_maintenance===true ? ok('A now has predictive maintenance') : bad('A missing predictive');
fb.analytics===false ? ok('B still has NO analytics (unchanged)') : bad('B analytics changed!');

sect('admin adds an extra allowance to A: +5 workers (bonus override)');
await db.exec(`insert into quota_overrides(organization_id,metric,override_type,value,reason,created_by) values('${A}','workers','bonus',5,'Agreed extra seats',auth.uid())`);
(await limOf(A,25))===30 ? ok('A effective worker limit = 25 base + 5 bonus = 30') : bad('A bonus not applied: '+await limOf(A,25));
(await limOf(B,5))===5   ? ok('B effective worker limit still 5 (no bonus)') : bad('B limit changed!');

sect('admin removes one module from A that its plan includes (block)');
await db.exec(`insert into company_feature_blocks(organization_id,feature,blocked) values('${A}','predictive_maintenance',true)`);
fa=await featOf(A);
fa.predictive_maintenance===false ? ok('A predictive maintenance now blocked, despite being on professional') : bad('block not applied');

sect('admin gives A one module its plan does NOT include (grant)');
await db.exec(`insert into company_feature_grants(organization_id,feature,granted) values('${A}','white_label',true)`);
fa=await featOf(A);
fa.white_label===true ? ok('A now has white_label via a per-company grant') : bad('grant not applied');

sect('Company B is still exactly a Basic company (full isolation)');
fb=await featOf(B);
(fb.analytics===false && fb.predictive_maintenance===false && fb.white_label===false && (await limOf(B,5))===5 && (await planOf(B))==='basic')
  ? ok('B: basic plan, base features, base limits — nothing leaked from A') : bad('B was affected by edits to A!');

sect('the edit was written to the audit log');
const logs = await q(`select action,details from admin_action_logs where organization_id='${A}' and action='company_commercial_updated'`);
logs.length>=1 ? ok(`audit log recorded the package change (${logs.length} entry)`) : bad('no audit log written');

console.log(`\n${fail? R:G}${pass} passed, ${fail} failed${X}`);
console.log(fail? `${R}SOME CHECKS FAILED${X}` : `${G}ALL EDIT-COMPANY CHECKS PASSED${X}\n`);
process.exit(fail?1:0);
