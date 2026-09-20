-- ===========================================================================
-- PlantMaster Pro — 0001 foundation
--   extensions, enums, tenancy core (organizations / plants / members /
--   profiles), and the security helper functions every later policy calls.
--
-- Every statement is idempotent so this suite can be applied on top of the
-- existing production database without destroying data.
-- ===========================================================================

-- pgcrypto ships enabled on Supabase. gen_random_uuid() is core since PG13, so
-- a sandbox without the extension is still fine — never fail the migration.
do $$
begin
  create extension if not exists pgcrypto;
exception when others then
  raise notice 'pgcrypto unavailable (%), continuing with built-in gen_random_uuid()', sqlerrm;
end $$;

-- Portable random token. Uses pgcrypto's gen_random_bytes when present
-- (Supabase always has it) and falls back to stitched UUIDs otherwise, so the
-- same migration runs in CI sandboxes without the extension.
create or replace function public.pm_random_token()
returns text
language plpgsql
volatile
set search_path = public, pg_temp
as $$
begin
  return encode(gen_random_bytes(24), 'hex');
exception when undefined_function then
  return replace(gen_random_uuid()::text, '-', '')
      || replace(gen_random_uuid()::text, '-', '');
end $$;

-- ---------------------------------------------------------------------------
-- Enumerated domains
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname = 'member_role') then
    create type public.member_role as enum
      ('owner','manager','supervisor','engineer','technician','operator','viewer');
  end if;

  if not exists (select 1 from pg_type where typname = 'commercial_status') then
    create type public.commercial_status as enum
      ('trial','active','past_due','suspended','cancelled','deletion_pending');
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- profiles — one row per auth user (personal data, not tenant data)
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- organizations (tenants) + commercial state
-- ---------------------------------------------------------------------------
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
create index if not exists organizations_owner_idx  on public.organizations(owner_id);
create index if not exists organizations_status_idx on public.organizations(commercial_status);

-- ---------------------------------------------------------------------------
-- plants — a tenant may run several physical sites
-- ---------------------------------------------------------------------------
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
create index if not exists plants_org_idx on public.plants(organization_id);

-- ---------------------------------------------------------------------------
-- organization_members — the authorization spine
-- ---------------------------------------------------------------------------
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
create index if not exists org_members_user_idx   on public.organization_members(user_id) where active;
create index if not exists org_members_org_idx    on public.organization_members(organization_id);
create index if not exists org_members_lookup_idx on public.organization_members(user_id, organization_id) where active;

-- ---------------------------------------------------------------------------
-- platform_admins — PlantMaster staff (admin.hsbfix.org). Deliberately NOT a
-- role inside member_role: platform staff are not tenant members.
-- ---------------------------------------------------------------------------
create table if not exists public.platform_admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  email      text,
  note       text,
  created_at timestamptz not null default now()
);

-- ===========================================================================
-- SECURITY HELPERS
--
-- All are SECURITY DEFINER + STABLE and read only from organization_members /
-- platform_admins. They are the single source of truth for every RLS policy,
-- which keeps policies short and avoids the infinite-recursion trap of a
-- policy on organization_members that queries organization_members.
--
-- search_path is pinned on every function: without it a caller can put a
-- malicious schema first and hijack a SECURITY DEFINER body.
-- ===========================================================================

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

create or replace function public.is_org_member(p_org uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.organization_members m
    where m.organization_id = p_org
      and m.user_id = auth.uid()
      and m.active
  ) or public.is_platform_admin();
$$;

create or replace function public.org_role(p_org uuid)
returns public.member_role
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select m.role
  from public.organization_members m
  where m.organization_id = p_org
    and m.user_id = auth.uid()
    and m.active
  limit 1;
$$;

-- Rank roles so policies can express "supervisor and above" without listing.
create or replace function public.role_rank(p_role public.member_role)
returns int
language sql
immutable
as $$
  select case p_role
    when 'owner'      then 60
    when 'manager'    then 50
    when 'supervisor' then 40
    when 'engineer'   then 30
    when 'technician' then 20
    when 'operator'   then 10
    when 'viewer'     then 0
    else -1 end;
$$;

create or replace function public.has_org_role(p_org uuid, p_min public.member_role)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    public.role_rank(public.org_role(p_org)) >= public.role_rank(p_min),
    false
  ) or public.is_platform_admin();
$$;

create or replace function public.is_org_owner(p_org uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.org_role(p_org) = 'owner' or public.is_platform_admin();
$$;

-- viewer == read-only demo account. Used to block every write path.
create or replace function public.can_write(p_org uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(public.org_role(p_org) <> 'viewer', false)
      or public.is_platform_admin();
$$;

-- Plant -> organization resolution, so plant-scoped tables can authorize
-- without every policy repeating a join.
create or replace function public.plant_org(p_plant uuid)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.organization_id from public.plants p where p.id = p_plant;
$$;

create or replace function public.is_plant_member(p_plant uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.is_org_member(public.plant_org(p_plant));
$$;

create or replace function public.can_write_plant(p_plant uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.can_write(public.plant_org(p_plant));
$$;

create or replace function public.has_plant_role(p_plant uuid, p_min public.member_role)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.has_org_role(public.plant_org(p_plant), p_min);
$$;

-- ---------------------------------------------------------------------------
-- Generic updated_at trigger
-- ---------------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- New auth user -> profile row. The app also upserts, but a DB-side trigger
-- means a profile always exists even for users created in the dashboard.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', new.email, ''))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- RLS — tenancy core
-- ---------------------------------------------------------------------------
alter table public.profiles             enable row level security;
alter table public.organizations        enable row level security;
alter table public.plants               enable row level security;
alter table public.organization_members enable row level security;
alter table public.platform_admins      enable row level security;

-- profiles: you read yourself, plus colleagues in your organizations
-- (the app renders worker names on rosters, audit trails and handovers).
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (
    id = auth.uid()
    or public.is_platform_admin()
    or exists (
      select 1
      from public.organization_members me
      join public.organization_members them
        on them.organization_id = me.organization_id
      where me.user_id = auth.uid() and me.active
        and them.user_id = public.profiles.id and them.active
    )
  );

drop policy if exists profiles_insert on public.profiles;
create policy profiles_insert on public.profiles
  for insert to authenticated
  with check (id = auth.uid());

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update to authenticated
  using (id = auth.uid() or public.is_platform_admin())
  with check (id = auth.uid() or public.is_platform_admin());

-- organizations
drop policy if exists organizations_select on public.organizations;
create policy organizations_select on public.organizations
  for select to authenticated
  using (public.is_org_member(id));

-- Creation goes exclusively through create_organization() so that the owner
-- membership row and first plant are created atomically.
drop policy if exists organizations_update on public.organizations;
create policy organizations_update on public.organizations
  for update to authenticated
  using (public.is_org_owner(id))
  with check (public.is_org_owner(id));

-- plants
drop policy if exists plants_select on public.plants;
create policy plants_select on public.plants
  for select to authenticated
  using (public.is_org_member(organization_id));

drop policy if exists plants_write on public.plants;
create policy plants_write on public.plants
  for all to authenticated
  using (public.has_org_role(organization_id, 'manager'))
  with check (public.has_org_role(organization_id, 'manager')
              and public.can_write(organization_id));

-- organization_members: every member sees the roster; only owners mutate it.
-- Uses is_org_member() (SECURITY DEFINER) rather than a self-join, which is
-- what prevents recursive policy evaluation on this table.
drop policy if exists org_members_select on public.organization_members;
create policy org_members_select on public.organization_members
  for select to authenticated
  using (user_id = auth.uid() or public.is_org_member(organization_id));

drop policy if exists org_members_write on public.organization_members;
create policy org_members_write on public.organization_members
  for all to authenticated
  using (public.is_org_owner(organization_id))
  with check (public.is_org_owner(organization_id));

-- platform_admins: readable only by platform admins; never writable from the
-- client (service_role / SQL editor only).
drop policy if exists platform_admins_select on public.platform_admins;
create policy platform_admins_select on public.platform_admins
  for select to authenticated
  using (public.is_platform_admin());

-- ---------------------------------------------------------------------------
-- updated_at triggers
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['profiles','organizations','plants','organization_members']
  loop
    execute format('drop trigger if exists touch_%1$s on public.%1$s', t);
    execute format(
      'create trigger touch_%1$s before update on public.%1$s
       for each row execute function public.touch_updated_at()', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Grants. RLS still governs every row; these just open the tables to the
-- PostgREST roles.
-- ---------------------------------------------------------------------------
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
-- Table-level grants for objects created by later migrations are re-applied
-- in 0009_grants.sql, which runs last.
