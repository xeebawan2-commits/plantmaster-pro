-- ============================================================
-- Schema for this section (auto-extracted from the repo / live snapshot)
-- ============================================================


-- ---------- TABLES ----------


-- [scan_sessions]  source: 0004_knowledge_files.sql
create table if not exists public.scan_sessions (
  id                 uuid primary key default gen_random_uuid(),
  organization_id    uuid not null references public.organizations(id) on delete cascade,
  plant_id           uuid not null references public.plants(id) on delete cascade,
  source_type        text default 'camera',
  status             text not null default 'draft',
  title              text,
  mime_type          text,
  file_name          text,
  file_size          bigint,
  original_path      text,
  detected_codes     jsonb default '[]'::jsonb,
  extracted_text     text,
  structured_result  jsonb default '{}'::jsonb,
  linked_entity_type text,
  linked_entity_id   uuid,
  confidence         numeric,
  safety_notes       text,
  created_by         uuid references auth.users(id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  removed_at         timestamptz,
  removed_by         uuid references auth.users(id) on delete set null
);


-- [scan_pages]  source: 0004_knowledge_files.sql
create table if not exists public.scan_pages (
  id                uuid primary key default gen_random_uuid(),
  session_id        uuid not null references public.scan_sessions(id) on delete cascade,
  page_number       int not null default 1,
  storage_path      text,
  mime_type         text,
  size_bytes        bigint,
  rotation          int default 0,
  enhancement       text default 'original',
  extracted_text    text,
  structured_result jsonb default '{}'::jsonb,
  created_at        timestamptz not null default now()
);


-- [code_registry]  source: 0003_inventory_procurement.sql
create table if not exists public.code_registry (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id        uuid references public.plants(id) on delete cascade,
  code_value      text not null,
  entity_type     text not null,           -- asset | spare | tool | location
  entity_id       uuid,
  name            text,
  description     text,
  asset_code      text,
  part_number     text,
  tool_code       text,
  status          text,
  stock           numeric,
  active          boolean not null default true,
  created_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);


-- [assets]  source: 0002_operations.sql
create table if not exists public.assets (
  id                     uuid primary key default gen_random_uuid(),
  organization_id        uuid not null references public.organizations(id) on delete cascade,
  plant_id               uuid not null references public.plants(id) on delete cascade,
  asset_code             text,
  name                   text not null,
  asset_type             text,
  location               text,
  manufacturer           text,
  model                  text,
  serial_number          text,
  rating                 text,
  status                 text not null default 'operational',
  running_state          text not null default 'shutdown',
  criticality            text default 'medium',
  commissioned_on        date,
  parent_asset_id        uuid references public.assets(id) on delete set null,
  meter_unit             text,
  current_meter_value    numeric,
  pm_trigger_meter_value numeric,
  last_meter_at          timestamptz,
  qr_payload             text,
  notes                  text,
  created_by             uuid references auth.users(id) on delete set null,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  removed_at             timestamptz,
  removed_by             uuid references auth.users(id) on delete set null
);


-- [spares]  source: 0003_inventory_procurement.sql
create table if not exists public.spares (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id        uuid not null references public.plants(id) on delete cascade,
  part_number     text,
  description     text not null,
  specification   text,
  unit            text default 'pcs',
  stock           numeric not null default 0,
  minimum         numeric not null default 0,
  location        text,
  unit_cost       numeric default 0,
  asset_id        uuid references public.assets(id) on delete set null,
  created_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  removed_at      timestamptz,
  constraint spares_stock_non_negative check (stock >= 0)
);


-- [tools]  source: 0003_inventory_procurement.sql
create table if not exists public.tools (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references public.organizations(id) on delete cascade,
  plant_id         uuid not null references public.plants(id) on delete cascade,
  tool_code        text,
  name             text not null,
  description      text,
  part_number      text,
  status           text not null default 'available',
  stock            numeric not null default 1,
  holder_id        uuid references auth.users(id) on delete set null,
  location         text,
  calibration_due  date,
  created_by       uuid references auth.users(id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  removed_at       timestamptz
);


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
