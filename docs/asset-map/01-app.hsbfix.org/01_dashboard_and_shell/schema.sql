-- ============================================================
-- Schema for this section (auto-extracted from the repo / live snapshot)
-- ============================================================


-- ---------- TABLES ----------


-- [organizations]  source: 0001_foundation.sql
create table if not exists public.organizations (
  id                uuid primary key default gen_random_uuid(),
  name              text not null,
  slug              text unique,
  logo_path         text,
  owner_id          uuid references auth.users(id) on delete set null,
  commercial_status public.commercial_status not null default 'trial',
  plan_code         text not null default 'trial',
  status_reason     text,
  trial_ends_at     timestamptz default (now() + interval '30 days'),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  removed_at        timestamptz
);


-- [organization_members]  source: 0001_foundation.sql
create table if not exists public.organization_members (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id         uuid not null references auth.users(id) on delete cascade,
  plant_id        uuid references public.plants(id) on delete set null,
  role            public.member_role not null default 'technician',
  permissions     jsonb not null default '{}'::jsonb,
  active          boolean not null default true,
  accepted_at     timestamptz default now(),
  deactivated_at  timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (organization_id, user_id)
);


-- [plants]  source: 0001_foundation.sql
create table if not exists public.plants (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name            text not null,
  code            text,
  location        text,
  timezone        text not null default 'Asia/Karachi',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  removed_at      timestamptz
);


-- [profiles]  source: 0001_foundation.sql
create table if not exists public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  full_name     text not null default '',
  employee_id   text,
  designation   text,
  default_shift text default 'General Shift',
  contact       text,
  skills        text,
  avatar_path   text,
  locale        text default 'en',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);


-- [organization_settings]  source: 0005_platform_commercial.sql
create table if not exists public.organization_settings (
  organization_id    uuid primary key references public.organizations(id) on delete cascade,
  plant_id           uuid references public.plants(id) on delete set null,
  app_name           text,
  plant_display_name text,
  primary_color      text default '#2563eb',
  secondary_color    text default '#0ea5e9',
  theme              text default 'dark',
  pattern            text default 'none',
  logo_path          text,
  address            text,
  contact            text,
  email              text,
  report_time        time default '11:00',
  report_recipients  text,
  footer_text        text,
  updated_by         uuid references auth.users(id) on delete set null,
  updated_at         timestamptz not null default now()
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


-- [notifications]  source: 0004_knowledge_files.sql
create table if not exists public.notifications (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id        uuid references public.plants(id) on delete cascade,
  user_id         uuid references auth.users(id) on delete cascade,  -- null = whole org
  title           text not null,
  body            text,
  severity        text default 'normal',
  category        text default 'general',
  alarm           boolean not null default false,
  route           text,
  entity_type     text,
  entity_id       uuid,
  read_at         timestamptz,
  pushed_at       timestamptz,
  created_at      timestamptz not null default now()
);



-- ---------- FUNCTIONS / RPCs ----------


-- [create_organization()]  source: R1-fix-organization-creation.sql
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


-- [accept_invitation()]  source: 0006_rpc.sql
create or replace function public.accept_invitation(invite_token text)
returns public.organization_members
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := auth.uid();
  inv public.invitations;
  mem public.organization_members;
  mail text;
begin
  if uid is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;

  select * into inv from public.invitations
   where token = invite_token for update;

  if not found then
    raise exception 'This invitation link is not valid' using errcode = 'P0002';
  end if;
  if inv.accepted_at is not null then
    raise exception 'This invitation has already been used' using errcode = '23505';
  end if;
  if inv.expires_at < now() then
    raise exception 'This invitation has expired' using errcode = '22023';
  end if;

  -- The invitation is addressed to an email; only that person may use it.
  select email into mail from auth.users where id = uid;
  if mail is not null and lower(mail) <> lower(inv.email) then
    raise exception 'This invitation was sent to %', inv.email using errcode = '42501';
  end if;

  insert into public.organization_members
    (organization_id, user_id, plant_id, role, permissions, active, accepted_at)
  values (inv.organization_id, uid, inv.plant_id, inv.role,
          coalesce(inv.permissions, '{}'::jsonb), true, now())
  on conflict (organization_id, user_id) do update
    set active = true, role = excluded.role, deactivated_at = null, updated_at = now()
  returning * into mem;

  update public.invitations
     set accepted_at = now(), accepted_by = uid
   where id = inv.id;

  -- Carry the worker details captured at invite time onto the profile.
  if inv.worker_details <> '{}'::jsonb then
    update public.profiles
       set full_name   = coalesce(nullif(inv.worker_details->>'full_name',''), full_name),
           employee_id = coalesce(inv.worker_details->>'employee_id', employee_id),
           designation = coalesce(inv.worker_details->>'designation', designation),
           contact     = coalesce(inv.worker_details->>'contact', contact),
           default_shift = coalesce(inv.worker_details->>'default_shift', default_shift),
           updated_at  = now()
     where id = uid;
  end if;

  insert into public.audit_logs
    (organization_id, plant_id, user_id, action, entity_type, entity_id, details)
  values (inv.organization_id, inv.plant_id, uid, 'invitation_accepted', 'member',
          uid::text, jsonb_build_object('role', inv.role));

  return mem;
end $$;


-- [is_platform_admin()]  source: 0001_foundation.sql
create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.platform_admins pa
    where pa.user_id = auth.uid()
  );
$$;


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


-- [pending_legal_documents()]  source: 0006_rpc.sql
create or replace function public.pending_legal_documents(p_organization_id uuid default null)
returns setof public.legal_documents
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select d.* from public.legal_documents d
   where d.active and d.mandatory
     and not exists (
       select 1 from public.legal_acceptances a
        where a.document_id = d.id
          and a.user_id = auth.uid()
          and (a.organization_id is not distinct from p_organization_id))
   order by d.effective_at desc;
$$;


-- [accept_legal_document()]  source: 0006_rpc.sql
create or replace function public.accept_legal_document(
  p_document_id     uuid,
  p_organization_id uuid default null,
  p_locale          text default null,
  p_user_agent_hash text default null
) returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;
  insert into public.legal_acceptances
    (document_id, organization_id, user_id, locale, user_agent_hash)
  values (p_document_id, p_organization_id, auth.uid(), p_locale, p_user_agent_hash)
  on conflict (document_id, user_id, organization_id) do nothing;
  return true;
end $$;
