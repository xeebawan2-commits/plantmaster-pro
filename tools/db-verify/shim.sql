-- ---------------------------------------------------------------------------
-- Supabase emulation shim — TEST HARNESS ONLY. Never applied to production.
--
-- PGlite is stock PostgreSQL, so it has none of the objects Supabase injects
-- into a hosted project (the `auth` / `storage` schemas, the `anon`,
-- `authenticated` and `service_role` roles, `auth.uid()`, ...).
-- This file creates just enough of that surface for the real migrations in
-- supabase/migrations/ to run and for the RLS policies to be exercised
-- exactly as they will behave in production.
-- ---------------------------------------------------------------------------

create schema if not exists auth;
create schema if not exists storage;
create schema if not exists extensions;

-- Supabase roles -------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticator') then
    create role authenticator noinherit login;
  end if;
end $$;

grant usage on schema public to anon, authenticated, service_role;
-- Supabase grants the auth helper schema to the API roles; mirror that so
-- auth.uid() is callable once we `set role authenticated`.
grant usage on schema auth, storage, extensions to anon, authenticated, service_role;
grant anon, authenticated, service_role to authenticator;

-- auth.users -----------------------------------------------------------------
create table if not exists auth.users (
  id            uuid primary key default gen_random_uuid(),
  email         text unique,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now()
);

-- Request context. In production these come from the JWT via PostgREST.
create or replace function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

create or replace function auth.role() returns text
language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), 'anon');
$$;

create or replace function auth.email() returns text
language sql stable as $$
  select nullif(current_setting('request.jwt.claim.email', true), '');
$$;

create or replace function auth.jwt() returns jsonb
language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb);
$$;

-- storage.buckets / storage.objects -----------------------------------------
create table if not exists storage.buckets (
  id                 text primary key,
  name               text not null,
  public             boolean not null default false,
  file_size_limit    bigint,
  allowed_mime_types text[],
  created_at         timestamptz not null default now()
);

create table if not exists storage.objects (
  id             uuid primary key default gen_random_uuid(),
  bucket_id      text references storage.buckets(id),
  name           text not null,
  owner          uuid,
  metadata       jsonb not null default '{}'::jsonb,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
alter table storage.objects enable row level security;

create or replace function storage.foldername(name text) returns text[]
language sql immutable as $$
  select string_to_array(name, '/');
$$;

-- Test helper: impersonate a signed-in user for RLS checks.
create or replace function auth.login(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), false);
  perform set_config('request.jwt.claim.role', 'authenticated', false);
  perform set_config('role', 'authenticated', false);
end $$;

create or replace function auth.logout() returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', '', false);
  perform set_config('request.jwt.claim.role', 'anon', false);
  perform set_config('role', 'anon', false);
end $$;
