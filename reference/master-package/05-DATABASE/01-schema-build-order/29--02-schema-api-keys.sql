-- =====================================================================
-- PlantMaster Pro — API keys for the public REST API
-- Run in Supabase SQL Editor AFTER 01-schema-procurement.sql
--
-- Design notes:
--  * Only the SHA-256 hash of a key is stored. The plaintext is shown to
--    the owner once, at creation, and is unrecoverable afterwards.
--  * Soft delete uses removed_at, matching every other table in this app.
--  * Helper functions are prefixed pm_ to avoid colliding with the
--    is_org_member / is_org_leader functions this project already has.
-- =====================================================================

create table if not exists public.api_keys (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references public.organizations(id) on delete cascade,
  plant_id         uuid references public.plants(id) on delete cascade,
  name             text not null,
  key_hash         text not null unique,
  key_prefix       text not null,              -- first 8 chars, for display only
  scopes           text[] not null default '{read}',
  created_by       uuid,
  created_at       timestamptz not null default now(),
  last_used_at     timestamptz,
  expires_at       timestamptz,
  revoked_at       timestamptz,
  removed_at       timestamptz
);

create index if not exists api_keys_hash_idx on public.api_keys(key_hash);
create index if not exists api_keys_org_idx  on public.api_keys(organization_id);

alter table public.api_keys enable row level security;

-- Owners only. API keys grant tenant-wide read access, so managers are
-- deliberately excluded.
create or replace function public.pm_is_org_owner(p_org uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.organization_members m
     where m.organization_id = p_org
       and m.user_id = auth.uid()
       and m.role = 'owner'
  );
$$;

drop policy if exists api_keys_read  on public.api_keys;
drop policy if exists api_keys_write on public.api_keys;

create policy api_keys_read on public.api_keys
  for select using (public.pm_is_org_owner(organization_id));

create policy api_keys_write on public.api_keys
  for all    using (public.pm_is_org_owner(organization_id))
             with check (public.pm_is_org_owner(organization_id));

-- ---------------------------------------------------------------------
-- Key generation. Returns the plaintext key EXACTLY ONCE; only the hash
-- is persisted. pgcrypto ships enabled on Supabase.
-- ---------------------------------------------------------------------
create or replace function public.pm_create_api_key(
  p_org     uuid,
  p_name    text,
  p_plant   uuid default null,
  p_expires timestamptz default null
)
returns table(id uuid, api_key text, key_prefix text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key    text;
  v_hash   text;
  v_prefix text;
  v_id     uuid;
begin
  if not public.pm_is_org_owner(p_org) then
    raise exception 'Only the organization owner can create API keys';
  end if;

  -- pm_live_<40 hex chars>
  v_key    := 'pm_live_' || encode(gen_random_bytes(20), 'hex');
  v_hash   := encode(digest(v_key, 'sha256'), 'hex');
  v_prefix := left(v_key, 16);
  v_id     := gen_random_uuid();

  insert into public.api_keys
    (id, organization_id, plant_id, name, key_hash, key_prefix, created_by, expires_at)
  values
    (v_id, p_org, p_plant, p_name, v_hash, v_prefix, auth.uid(), p_expires);

  return query select v_id, v_key, v_prefix;
end;
$$;

create or replace function public.pm_revoke_api_key(p_key uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_org uuid;
begin
  select organization_id into v_org from public.api_keys where id = p_key;
  if v_org is null then
    raise exception 'API key not found';
  end if;
  if not public.pm_is_org_owner(v_org) then
    raise exception 'Only the organization owner can revoke API keys';
  end if;

  update public.api_keys
     set revoked_at = now()
   where id = p_key;
end;
$$;

grant select, insert, update, delete on public.api_keys to authenticated;

grant execute on function public.pm_is_org_owner(uuid) to authenticated;
grant execute on function public.pm_create_api_key(uuid,text,uuid,timestamptz) to authenticated;
grant execute on function public.pm_revoke_api_key(uuid) to authenticated;

-- =====================================================================
-- DONE.
-- Verify:
--   select * from public.pm_create_api_key('<your-org-uuid>', 'Test key');
-- Copy the api_key value — it cannot be retrieved again.
-- =====================================================================
