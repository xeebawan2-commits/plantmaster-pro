-- ============================================================
--  PlantMaster — per-company feature GRANTS
--  HSB Fix Services
--
--  WHY THIS EXISTS
--  Until now the per-company editor could only take a module
--  AWAY from what the package gives. There was no way to give
--  one company something extra. That is why ticking a box said
--  "not in their package" and did nothing.
--
--  This adds the missing half: a grants table, so a single
--  company can be given any module without touching the
--  package everyone else is on.
--
--  Safe to run more than once.
--  Paste the whole file into the Supabase SQL editor, press Run.
-- ============================================================


-- ------------------------------------------------------------
-- 1. The grants table (the mirror image of the blocks table)
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
--    company_feature_blocks.feature was limited to a short list
--    (gemini, deep_search, vision_scanner, condition_analysis,
--    uploads). Blocking anything else silently failed. This
--    removes that limit so all 21 modules work.
-- ------------------------------------------------------------
do $$
declare r record;
begin
  for r in
    select con.conname, pg_get_constraintdef(con.oid) as def
    from   pg_constraint con
    join   pg_class     c on c.oid = con.conrelid
    join   pg_namespace n on n.oid = c.relnamespace
    where  n.nspname = 'public'
      and  c.relname = 'company_feature_blocks'
      and  con.contype = 'c'
  loop
    if r.def ilike '%feature%' then
      execute format('alter table public.company_feature_blocks drop constraint %I', r.conname);
      raise notice 'Removed the old feature-name limit: %', r.conname;
    end if;
  end loop;
end $$;

-- If feature is an enum rather than plain text, widen it instead.
do $$
declare
  v_type text;
  v_key  text;
  v_keys text[] := array[
    'analytics','gemini','deep_search','vision_scanner','condition_analysis',
    'predictive_maintenance','safety_loto','work_orders','maintenance_plans',
    'checklists','inventory','procurement_requests','suppliers','finance_labor',
    'uploads','reports','people','permits','incidents','support','white_label'
  ];
begin
  select t.typname into v_type
  from   pg_attribute a
  join   pg_class     c on c.oid = a.attrelid
  join   pg_namespace n on n.oid = c.relnamespace
  join   pg_type      t on t.oid = a.atttypid
  where  n.nspname = 'public'
    and  c.relname = 'company_feature_blocks'
    and  a.attname = 'feature';

  if v_type is not null and v_type <> 'text' and v_type <> 'varchar' then
    foreach v_key in array v_keys loop
      begin
        execute format('alter type public.%I add value if not exists %L', v_type, v_key);
      exception when others then
        null;
      end;
    end loop;
    raise notice 'Widened the % enum to cover all modules', v_type;
  end if;
end $$;


-- ------------------------------------------------------------
-- 3. Security
--    Platform admins manage everything.
--    A company's own members may READ what they are entitled to
--    (the app needs this) but may never write it.
-- ------------------------------------------------------------
alter table public.company_feature_grants enable row level security;

drop policy if exists cfg_admin_all     on public.company_feature_grants;
drop policy if exists cfg_member_select on public.company_feature_grants;

create policy cfg_admin_all
  on public.company_feature_grants
  for all
  using      (public.is_platform_admin())
  with check (public.is_platform_admin());

create policy cfg_member_select
  on public.company_feature_grants
  for select
  using (
    exists (
      select 1 from public.organization_members m
      where  m.organization_id = company_feature_grants.organization_id
        and  m.user_id = auth.uid()
        and  coalesce(m.active, true)
    )
  );

-- Members must be able to read their blocks too, or the app
-- cannot tell what has been switched off for them.
do $$
begin
  if exists (
    select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname='public' and c.relname='company_feature_blocks'
  ) then
    execute 'alter table public.company_feature_blocks enable row level security';
    execute 'drop policy if exists cfb_member_select on public.company_feature_blocks';
    execute $p$
      create policy cfb_member_select
        on public.company_feature_blocks
        for select
        using (
          exists (
            select 1 from public.organization_members m
            where  m.organization_id = company_feature_blocks.organization_id
              and  m.user_id = auth.uid()
              and  coalesce(m.active, true)
          )
        )
    $p$;
    execute 'drop policy if exists cfb_admin_all on public.company_feature_blocks';
    execute $p$
      create policy cfb_admin_all
        on public.company_feature_blocks
        for all
        using (public.is_platform_admin())
        with check (public.is_platform_admin())
    $p$;
  end if;
end $$;

grant select on public.company_feature_grants to authenticated;
grant select on public.company_feature_blocks to authenticated;


-- ------------------------------------------------------------
-- 4. One function that answers: what can this company use?
--
--    package features  +  per-company grants  -  per-company blocks
--
--    The app calls this instead of reading the plan directly, so
--    a per-company extra takes effect immediately.
-- ------------------------------------------------------------
create or replace function public.organization_effective_features(
  p_organization_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org       jsonb;
  v_plan_code text;
  v_features  jsonb := '{}'::jsonb;
  r           record;
begin
  if p_organization_id is null then
    return '{}'::jsonb;
  end if;

  -- Caller must belong to the company, or be a platform admin.
  if not (
    public.is_platform_admin()
    or exists (
      select 1 from public.organization_members m
      where  m.organization_id = p_organization_id
        and  m.user_id = auth.uid()
        and  coalesce(m.active, true)
    )
  ) then
    raise exception 'Not authorised for this organization';
  end if;

  -- Find the plan code without assuming a column name.
  select to_jsonb(o) into v_org
  from   public.organizations o
  where  o.id = p_organization_id;

  if v_org is null then
    return '{}'::jsonb;
  end if;

  v_plan_code := coalesce(
    v_org->>'plan_code',
    v_org->>'subscription_plan_code',
    v_org->>'plan'
  );

  if v_plan_code is not null then
    select coalesce(sp.features, '{}'::jsonb) into v_features
    from   public.subscription_plans sp
    where  sp.code = v_plan_code;
  end if;

  v_features := coalesce(v_features, '{}'::jsonb);

  -- Add anything granted to this company specifically.
  for r in
    select feature
    from   public.company_feature_grants
    where  organization_id = p_organization_id
      and  coalesce(granted, true)
      and  (expires_at is null or expires_at > now())
  loop
    v_features := v_features || jsonb_build_object(r.feature, true);
  end loop;

  -- Remove anything blocked for this company specifically.
  for r in
    select feature
    from   public.company_feature_blocks
    where  organization_id = p_organization_id
      and  coalesce(blocked, true)
      and  (expires_at is null or expires_at > now())
  loop
    v_features := v_features || jsonb_build_object(r.feature, false);
  end loop;

  return v_features;
end;
$$;

revoke all on function public.organization_effective_features(uuid) from public;
grant execute on function public.organization_effective_features(uuid) to authenticated;


-- ------------------------------------------------------------
-- 5. Check it worked
-- ------------------------------------------------------------
select 'company_feature_grants table' as item,
       case when exists (
         select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='company_feature_grants'
       ) then 'created' else 'MISSING' end as result
union all
select 'organization_effective_features()',
       case when exists (
         select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public' and p.proname='organization_effective_features'
       ) then 'created' else 'MISSING' end
union all
select 'feature-name limit on blocks',
       case when exists (
         select 1 from pg_constraint con
         join pg_class c on c.oid=con.conrelid
         join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='public' and c.relname='company_feature_blocks'
           and con.contype='c' and pg_get_constraintdef(con.oid) ilike '%feature%'
       ) then 'STILL THERE' else 'removed' end;
