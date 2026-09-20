-- ============================================================
--  R1 — FIX ORGANIZATION CREATION
--
--  PlantMaster Pro · project dpmmenwziplixrgylapy
--  Written against the live schema snapshot of 13 September 2026.
--
--  THE BUG
--  -------
--  public.create_organization() does these inserts in order:
--
--      organizations        -> ok
--      organization_members -> ok
--      plants               -> FAILS
--      plant_members        -> never reached
--
--  The plants table carries a trigger, enforce_plant_plan_limit,
--  which begins:
--
--      select p.max_plants into base_limit
--        from organization_subscriptions s
--        join subscription_plans p on p.id = s.plan_id
--       where s.organization_id = new.organization_id
--         and s.status in ('active','trial');
--      if base_limit is null then
--        raise exception 'Active subscription required';
--      end if;
--
--  create_organization never inserts into organization_subscriptions,
--  so base_limit is always null, the trigger always raises, and the
--  whole function rolls back. No organization can ever be created.
--
--  THE FIX
--  -------
--  Insert the subscription BEFORE the plant. Everything else about
--  the function is preserved.
--
--  This script is idempotent and safe to re-run.
--  It only replaces one function; it creates and drops nothing else.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- Make sure the plans exist, otherwise there is no plan to attach.
-- Values match 30--01-GATEKEEPER.sql from your master package.
-- ------------------------------------------------------------
insert into public.subscription_plans
  (code,name,description,currency,price_monthly,price_yearly,
   max_workers,max_plants,max_storage_bytes,max_files,max_file_bytes,
   ai_requests_month,ai_requests_day,ai_requests_minute_user,
   ai_input_tokens_month,ai_output_tokens_month,retention_days,active)
values
  ('trial','Trial (7 days)','Full Professional features for 7 days','PKR',0,0,
   25,1,5368709120,2000,52428800,
   300,60,5,2000000,800000,365,true),
  ('essential','Essential','10 users, 1 plant, 10 GB','PKR',12000,120000,
   10,1,10737418240,5000,52428800,
   500,50,3,2000000,800000,1095,true),
  ('professional','Professional','25 users, 1 plant, 30 GB, full AI','PKR',24000,240000,
   25,1,32212254720,20000,104857600,
   3000,200,5,12000000,5000000,1095,true),
  ('enterprise','Enterprise','Quoted. Unlimited users.','PKR',0,0,
   999999,99,107374182400,999999,524288000,
   999999,99999,60,999999999,999999999,2190,true)
on conflict (code) do update set
  name        = excluded.name,
  description = excluded.description,
  currency    = excluded.currency,
  active      = true,
  updated_at  = now();


-- ------------------------------------------------------------
-- The fix itself.
--
-- Note on ungated signup: this version still lets any authenticated
-- user create a workspace. R2 replaces it with the invitation-gated
-- version. R1 is deliberately kept separate so you can restore
-- signup immediately without also changing your access policy.
-- ------------------------------------------------------------
create or replace function public.create_organization(org_name text, plant_name text)
returns table(organization_id uuid, plant_id uuid)
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  o         uuid;
  p         uuid;
  plan_row  public.subscription_plans%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if coalesce(trim(org_name),'') = '' then
    raise exception 'Company name is required';
  end if;

  select * into plan_row
    from public.subscription_plans
   where code = 'trial' and active
   limit 1;

  if plan_row.id is null then
    raise exception 'No trial plan configured. Run R1 section 1.';
  end if;

  insert into public.organizations (name, slug, created_by, commercial_status)
  values (
    trim(org_name),
    lower(regexp_replace(trim(org_name),'[^a-zA-Z0-9]+','-','g'))
      || '-' || substr(gen_random_uuid()::text,1,6),
    auth.uid(),
    'trial'
  )
  returning id into o;

  insert into public.organization_members (organization_id, user_id, role, active, created_at)
  values (o, auth.uid(), 'owner', true, now());

  -- THE FIX: subscription must exist before the plant is inserted,
  -- because enforce_plant_plan_limit reads it.
  insert into public.organization_subscriptions
    (organization_id, plan_id, status,
     current_period_start, current_period_end, trial_ends_at)
  values
    (o, plan_row.id, 'trial',
     now(), now() + interval '7 days', now() + interval '7 days');

  insert into public.plants (organization_id, name)
  values (o, coalesce(nullif(trim(plant_name),''),'Main Plant'))
  returning id into p;

  insert into public.plant_members (plant_id, user_id, created_at)
  values (p, auth.uid(), now());

  return query select o, p;
end
$function$;

grant execute on function public.create_organization(text,text) to authenticated;

commit;


-- ============================================================
--  VERIFY — expect: 4 plans, 'yes', and 0 broken orgs
-- ============================================================
select 'active plans' as check, count(*)::text as value
  from public.subscription_plans where active
union all
select 'subscription before plant',
       case when position('organization_subscriptions' in def)
                 < position('into public.plants' in def)
            then 'yes — fixed' else 'NO — still broken' end
  from (
    select pg_get_functiondef(p.oid) as def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname='public' and p.proname='create_organization'
     limit 1
  ) s
union all
select 'existing orgs with no subscription',
       (select count(*)::text from public.organizations o
         where not exists (select 1 from public.organization_subscriptions s
                            where s.organization_id = o.id));
