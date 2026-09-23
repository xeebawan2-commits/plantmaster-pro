-- ============================================================
-- Schema for this section (auto-extracted from the repo / live snapshot)
-- ============================================================


-- ---------- TABLES ----------


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
