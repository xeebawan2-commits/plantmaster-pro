-- ============================================================
-- Schema for this section (auto-extracted from the repo / live snapshot)
-- ============================================================


-- ---------- TABLES ----------


-- [organization_subscriptions]  source: 05-tables-constraints-indexes.sql (LIVE snapshot)
create table if not exists public.organization_subscriptions (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  plan_id uuid not null,
  status text default 'trial'::text not null,
  provider text,
  provider_customer_id text,
  provider_subscription_id text,
  current_period_start timestamptz default now() not null,
  current_period_end timestamptz,
  trial_ends_at timestamptz,
  cancel_at_period_end boolean default false not null,
  grace_ends_at timestamptz,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null
);


-- [subscription_plans]  source: 0005_platform_commercial.sql
create table if not exists public.subscription_plans (
  code              text primary key,
  name              text not null,
  price_monthly     numeric not null default 0,
  currency          text not null default 'PKR',
  max_users         int,
  max_plants        int,
  max_assets        int,
  storage_gb        numeric not null default 1,
  ai_requests_month int not null default 0,
  features          jsonb not null default '{}'::jsonb,
  active            boolean not null default true,
  sort_order        int not null default 0,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);


-- [company_feature_grants]  source: R4-company-features.sql
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


-- [company_feature_blocks]  source: 05-tables-constraints-indexes.sql (LIVE snapshot)
create table if not exists public.company_feature_blocks (
  organization_id uuid not null,
  feature text not null,
  blocked boolean default true not null,
  reason text not null,
  blocked_by uuid not null,
  expires_at timestamptz,
  updated_at timestamptz default now() not null
);


-- [quota_overrides]  source: 05-tables-constraints-indexes.sql (LIVE snapshot)
create table if not exists public.quota_overrides (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  metric text not null,
  override_type text not null,
  value bigint,
  starts_at timestamptz default now() not null,
  ends_at timestamptz,
  reason text not null,
  active boolean default true not null,
  created_by uuid not null,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null
);



-- ---------- FUNCTIONS / RPCs ----------


-- [organization_effective_features()]  source: R4-company-features.sql
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


-- [organization_plan_summary()]  source: 0006_rpc.sql
create or replace function public.organization_plan_summary(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  plan public.subscription_plans;
  org  public.organizations;
  used_bytes bigint;
  users_n int;
  plants_n int;
  assets_n int;
  ai_n int;
begin
  if not public.is_org_member(p_organization_id) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  select * into org  from public.organizations where id = p_organization_id;
  select * into plan from public.organization_plan(p_organization_id);
  used_bytes := public.organization_storage_bytes(p_organization_id);

  select count(*) into users_n from public.organization_members
   where organization_id = p_organization_id and active;
  select count(*) into plants_n from public.plants
   where organization_id = p_organization_id and removed_at is null;
  select count(*) into assets_n from public.assets
   where organization_id = p_organization_id and removed_at is null;
  select count(*) into ai_n from public.ai_usage_events
   where organization_id = p_organization_id
     and created_at >= date_trunc('month', now());

  return jsonb_build_object(
    'organization_id',   p_organization_id,
    'organization_name', org.name,
    'plan_code',         org.plan_code,
    'plan_name',         coalesce(plan.name, org.plan_code),
    'price_monthly',     coalesce(plan.price_monthly, 0),
    'currency',          coalesce(plan.currency, 'PKR'),
    'commercial_status', org.commercial_status,
    'status_reason',     org.status_reason,
    'trial_ends_at',     org.trial_ends_at,
    'storage_used_bytes',  used_bytes,
    'storage_limit_bytes', (coalesce(plan.storage_gb, 1) * 1024 * 1024 * 1024)::bigint,
    'storage_gb',        coalesce(plan.storage_gb, 1),
    'users',             users_n,
    'max_users',         plan.max_users,
    'plants',            plants_n,
    'max_plants',        plan.max_plants,
    'assets',            assets_n,
    'max_assets',        plan.max_assets,
    'ai_requests_month', ai_n,
    'ai_limit_month',    coalesce(plan.ai_requests_month, 0),
    'features',          public.organization_effective_features(p_organization_id)
  );
end $$;
