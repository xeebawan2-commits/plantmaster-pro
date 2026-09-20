-- ============================================================
--  R4 — PER-COMPANY FEATURE CONTROL
--
--  PlantMaster Pro · project dpmmenwziplixrgylapy
--  Run AFTER R1 and R2. Safe to re-run.
--
--  WHY
--  ---
--  The Control Center's per-company module editor can currently only
--  take a module AWAY from what the plan includes. Ticking a box to
--  give one company something extra says "not in their package" and
--  does nothing, because public.company_feature_grants does not exist.
--
--  admin/app.js reads that table in four places. It is written
--  defensively — it detects the missing table and tells you to run
--  10-COMPANY-FEATURES.sql — so nothing crashes today, but the
--  feature genuinely does not work.
--
--  The app also calls organization_effective_features() and silently
--  falls back to organization_plan_summary() when it is absent, which
--  means per-company extras never reach the customer app either.
--
--  This is your 02-repairs-and-features/10-COMPANY-FEATURES.sql with
--  one correction, described in section 4.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1. The grants table — the mirror image of company_feature_blocks
-- ------------------------------------------------------------
create table if not exists public.company_feature_grants (
  organization_id uuid not null
    references public.organizations(id) on delete cascade,
  feature         text not null,
  granted         boolean not null default true,
  reason          text,
  granted_by      uuid references auth.users(id) on delete set null,
  expires_at      timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  primary key (organization_id, feature)
);

create index if not exists company_feature_grants_org_idx
  on public.company_feature_grants(organization_id);


-- ------------------------------------------------------------
-- 2. Let every module key be used, not just the original five
--
--    company_feature_blocks.feature was limited by a CHECK
--    constraint to a short list, so blocking anything else failed
--    silently. Remove the limit; widen it instead if it is an enum.
-- ------------------------------------------------------------
do $$
declare r record;
begin
  for r in
    select con.conname, pg_get_constraintdef(con.oid) as def
      from pg_constraint con
      join pg_class     c on c.oid = con.conrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relname = 'company_feature_blocks'
       and con.contype = 'c'
  loop
    if r.def ilike '%feature%' then
      execute format('alter table public.company_feature_blocks drop constraint %I', r.conname);
      raise notice 'Removed the old feature-name limit: %', r.conname;
    end if;
  end loop;
end $$;

do $$
declare
  v_type text; v_key text;
  v_keys text[] := array[
    'analytics','gemini','deep_search','vision_scanner','condition_analysis',
    'predictive_maintenance','safety_loto','work_orders','maintenance_plans',
    'checklists','inventory','procurement_requests','suppliers','finance_labor',
    'uploads','reports','people','permits','incidents','support','white_label'
  ];
begin
  select t.typname into v_type
    from pg_attribute a
    join pg_class     c on c.oid = a.attrelid
    join pg_namespace n on n.oid = c.relnamespace
    join pg_type      t on t.oid = a.atttypid
   where n.nspname='public' and c.relname='company_feature_blocks' and a.attname='feature';

  if v_type is not null and v_type not in ('text','varchar') then
    foreach v_key in array v_keys loop
      begin
        execute format('alter type public.%I add value if not exists %L', v_type, v_key);
      exception when others then null;
      end;
    end loop;
    raise notice 'Widened the % enum to cover all modules', v_type;
  end if;
end $$;


-- ------------------------------------------------------------
-- 3. Security
--    Platform admins manage. A company's own members may READ what
--    they are entitled to — the app needs that — but never write.
-- ------------------------------------------------------------
alter table public.company_feature_grants enable row level security;

drop policy if exists cfg_admin_all     on public.company_feature_grants;
drop policy if exists cfg_member_select on public.company_feature_grants;

create policy cfg_admin_all
  on public.company_feature_grants for all
  using (public.is_platform_admin()) with check (public.is_platform_admin());

create policy cfg_member_select
  on public.company_feature_grants for select
  using (exists (
    select 1 from public.organization_members m
     where m.organization_id = company_feature_grants.organization_id
       and m.user_id = auth.uid()
       and coalesce(m.active, true)));

do $$
begin
  if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
              where n.nspname='public' and c.relname='company_feature_blocks') then
    execute 'alter table public.company_feature_blocks enable row level security';
    execute 'drop policy if exists cfb_member_select on public.company_feature_blocks';
    execute $p$
      create policy cfb_member_select on public.company_feature_blocks for select
        using (exists (select 1 from public.organization_members m
                        where m.organization_id = company_feature_blocks.organization_id
                          and m.user_id = auth.uid()
                          and coalesce(m.active, true))) $p$;
    execute 'drop policy if exists cfb_admin_all on public.company_feature_blocks';
    execute $p$
      create policy cfb_admin_all on public.company_feature_blocks for all
        using (public.is_platform_admin()) with check (public.is_platform_admin()) $p$;
  end if;
end $$;

grant select on public.company_feature_grants to authenticated;
grant select on public.company_feature_blocks to authenticated;


-- ------------------------------------------------------------
-- 4. What can this company actually use?
--
--      plan features  +  per-company grants  -  per-company blocks
--
--    CORRECTION vs 10-COMPANY-FEATURES.sql
--    -------------------------------------
--    That version looked for the plan on the organizations row:
--
--        v_plan_code := coalesce(v_org->>'plan_code',
--                                v_org->>'subscription_plan_code',
--                                v_org->>'plan');
--
--    public.organizations has no such column. Its 12 columns are
--    id, name, slug, logo_path, created_by, created_at,
--    commercial_status, status_reason, trial_ends_at, suspended_at,
--    deletion_scheduled_at, commercial_updated_at.
--
--    So v_plan_code was always null, v_features stayed '{}', and
--    every company would have shown zero package features — worse
--    than the fallback it replaces.
--
--    The plan is reached through organization_subscriptions.plan_id,
--    which is how enforce_plant_plan_limit and check_ai_quota already
--    do it. This version joins the same way.
-- ------------------------------------------------------------
create or replace function public.organization_effective_features(
  p_organization_id uuid
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_features jsonb := '{}'::jsonb;
  r record;
begin
  if p_organization_id is null then
    return '{}'::jsonb;
  end if;

  if not (
    public.is_platform_admin()
    or exists (select 1 from public.organization_members m
                where m.organization_id = p_organization_id
                  and m.user_id = auth.uid()
                  and coalesce(m.active, true))
  ) then
    raise exception 'Not authorised for this organization';
  end if;

  if not exists (select 1 from public.organizations where id = p_organization_id) then
    return '{}'::jsonb;
  end if;

  -- plan features, via the subscription (the live schema's actual shape)
  select coalesce(sp.features, '{}'::jsonb) into v_features
    from public.organization_subscriptions s
    join public.subscription_plans sp on sp.id = s.plan_id
   where s.organization_id = p_organization_id
     and s.status in ('active','trial')
   order by s.created_at desc
   limit 1;

  v_features := coalesce(v_features, '{}'::jsonb);

  for r in
    select feature from public.company_feature_grants
     where organization_id = p_organization_id
       and coalesce(granted, true)
       and (expires_at is null or expires_at > now())
  loop
    v_features := v_features || jsonb_build_object(r.feature, true);
  end loop;

  for r in
    select feature from public.company_feature_blocks
     where organization_id = p_organization_id
       and coalesce(blocked, true)
       and (expires_at is null or expires_at > now())
  loop
    v_features := v_features || jsonb_build_object(r.feature, false);
  end loop;

  return v_features;
end $$;

revoke all on function public.organization_effective_features(uuid) from public;
grant execute on function public.organization_effective_features(uuid) to authenticated;

commit;


-- ============================================================
--  VERIFY — expect 'created', 'created', 'removed'
-- ============================================================
select 'company_feature_grants table' as item,
       case when to_regclass('public.company_feature_grants') is not null
            then 'created' else 'MISSING' end as result
union all
select 'organization_effective_features()',
       case when exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                          where n.nspname='public' and p.proname='organization_effective_features')
            then 'created' else 'MISSING' end
union all
select 'feature-name limit on blocks',
       case when exists (select 1 from pg_constraint con
                           join pg_class c on c.oid=con.conrelid
                           join pg_namespace n on n.oid=c.relnamespace
                          where n.nspname='public' and c.relname='company_feature_blocks'
                            and con.contype='c'
                            and pg_get_constraintdef(con.oid) ilike '%feature%')
            then 'STILL THERE' else 'removed' end;
