-- ============================================================
-- Schema for this section (auto-extracted from the repo / live snapshot)
-- ============================================================


-- ---------- TABLES ----------


-- [manuals]  source: 0004_knowledge_files.sql
create table if not exists public.manuals (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id        uuid references public.plants(id) on delete cascade,
  asset_id        uuid references public.assets(id) on delete set null,
  title           text not null,
  manufacturer    text,
  model           text,
  document_type   text default 'manual',
  storage_path    text,
  mime_type       text,
  size_bytes      bigint default 0,
  page_count      int,
  page_number     int,
  content         text,
  status          text not null default 'stored',   -- stored|indexing|indexed|failed
  index_error     text,
  uploaded_by     uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  removed_at      timestamptz
);


-- [document_chunks]  source: 0004_knowledge_files.sql
create table if not exists public.document_chunks (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  manual_id       uuid references public.manuals(id) on delete cascade,
  page_number     int,
  chunk_index     int default 0,
  content         text not null,
  token_count     int,
  created_at      timestamptz not null default now()
);


-- [file_metadata]  source: 0004_knowledge_files.sql
create table if not exists public.file_metadata (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id        uuid references public.plants(id) on delete cascade,
  bucket          text not null default 'plant-files',
  object_path     text not null,
  file_name       text,
  mime_type       text,
  size_bytes      bigint not null default 0,
  category        text default 'general',
  entity_type     text,
  entity_id       uuid,
  uploaded_by     uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  removed_at      timestamptz,
  removed_by      uuid references auth.users(id) on delete set null
);


-- [data_retention_policies]  source: 0005_platform_commercial.sql
create table if not exists public.data_retention_policies (
  organization_id       uuid primary key references public.organizations(id) on delete cascade,
  operational_days      int not null default 1095,
  audit_days            int not null default 2555,
  ai_prompt_days        int not null default 365,
  soft_delete_grace_days int not null default 30,
  active                boolean not null default true,
  effective_at          timestamptz not null default now(),
  status                text not null default 'active',
  last_seen_at          timestamptz default now(),
  updated_by            uuid references auth.users(id) on delete set null,
  updated_at            timestamptz not null default now()
);



-- ---------- FUNCTIONS / RPCs ----------


-- [reserve_storage_upload()]  source: 0006_rpc.sql
create or replace function public.reserve_storage_upload(
  p_organization_id uuid,
  p_bytes           bigint,
  p_file_name       text default null,
  p_mime_type       text default null
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  plan  public.subscription_plans;
  used  bigint;
  limit_bytes bigint;
  rid   uuid;
  org   public.organizations;
begin
  if not public.is_org_member(p_organization_id) then
    raise exception 'Not a member of this workspace' using errcode = '42501';
  end if;
  if not public.can_write(p_organization_id) then
    raise exception 'Read-only demo — uploads are disabled' using errcode = '42501';
  end if;
  if p_bytes is null or p_bytes <= 0 then
    raise exception 'Invalid file size' using errcode = '22023';
  end if;

  select * into org from public.organizations where id = p_organization_id;
  if org.commercial_status in ('suspended','cancelled') then
    raise exception 'This workspace is % — uploads are disabled', org.commercial_status
      using errcode = '42501';
  end if;

  -- Release anything abandoned before measuring.
  update public.storage_reservations
     set status = 'expired', settled_at = now()
   where organization_id = p_organization_id
     and status = 'pending' and expires_at <= now();

  select * into plan from public.organization_plan(p_organization_id);
  limit_bytes := (coalesce(plan.storage_gb, 1) * 1024 * 1024 * 1024)::bigint;
  used := public.organization_storage_bytes(p_organization_id);

  if used + p_bytes > limit_bytes then
    raise exception 'Storage limit reached (% GB). Free space or upgrade the plan.',
      coalesce(plan.storage_gb, 1) using errcode = '53100';
  end if;

  insert into public.storage_reservations
    (organization_id, bytes, file_name, mime_type, created_by)
  values (p_organization_id, p_bytes, p_file_name, p_mime_type, auth.uid())
  returning id into rid;

  return rid;
end $$;


-- [finalize_storage_upload()]  source: 0006_rpc.sql
create or replace function public.finalize_storage_upload(
  p_reservation_id   uuid,
  p_object_path      text,
  p_file_metadata_id uuid default null
) returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare r public.storage_reservations;
begin
  select * into r from public.storage_reservations
   where id = p_reservation_id for update;
  if not found then
    raise exception 'Unknown storage reservation' using errcode = 'P0002';
  end if;
  if not public.is_org_member(r.organization_id) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  if r.status <> 'pending' then
    return true;   -- already settled; make this idempotent
  end if;

  update public.storage_reservations
     set status = 'committed', settled_at = now(),
         object_path = p_object_path, file_metadata_id = p_file_metadata_id
   where id = p_reservation_id;

  insert into public.storage_usage_events
    (organization_id, event_type, bytes, object_path, user_id)
  values (r.organization_id, 'upload', r.bytes, p_object_path, auth.uid());

  return true;
end $$;


-- [cancel_storage_reservation()]  source: 0006_rpc.sql
create or replace function public.cancel_storage_reservation(p_reservation_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare r public.storage_reservations;
begin
  select * into r from public.storage_reservations
   where id = p_reservation_id for update;
  if not found then return true; end if;
  if not public.is_org_member(r.organization_id) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  update public.storage_reservations
     set status = 'cancelled', settled_at = now()
   where id = p_reservation_id and status = 'pending';
  return true;
end $$;


-- [record_storage_download()]  source: 0006_rpc.sql
create or replace function public.record_storage_download(
  p_organization_id uuid,
  p_object_path     text,
  p_bytes           bigint default 0
) returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_org_member(p_organization_id) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  insert into public.storage_usage_events
    (organization_id, event_type, bytes, object_path, user_id)
  values (p_organization_id, 'download', greatest(coalesce(p_bytes, 0), 0),
          p_object_path, auth.uid());
  return true;
end $$;
