-- ============================================================
-- Schema for this section (auto-extracted from the repo / live snapshot)
-- ============================================================


-- ---------- TABLES ----------


-- [work_orders]  source: 0002_operations.sql
create table if not exists public.work_orders (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references public.organizations(id) on delete cascade,
  plant_id         uuid not null references public.plants(id) on delete cascade,
  asset_id         uuid references public.assets(id) on delete set null,
  wo_number        text,
  title            text not null,
  description      text,
  work_type        text default 'corrective',
  priority         text not null default 'medium',
  status           text not null default 'open',
  assigned_to      uuid references auth.users(id) on delete set null,
  due_at           timestamptz,
  started_at       timestamptz,
  completed_at     timestamptz,
  completed_by     uuid references auth.users(id) on delete set null,
  downtime_minutes numeric default 0,
  labor_minutes    numeric default 0,
  total_cost       numeric default 0,
  root_cause       text,
  corrective_action text,
  source           text default 'manual',
  created_by       uuid references auth.users(id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  removed_at       timestamptz,
  removed_by       uuid references auth.users(id) on delete set null
);


-- [checklist_runs]  source: 0002_operations.sql
create table if not exists public.checklist_runs (
  id                     uuid primary key default gen_random_uuid(),
  organization_id        uuid not null references public.organizations(id) on delete cascade,
  plant_id               uuid not null references public.plants(id) on delete cascade,
  template_id            uuid references public.checklist_templates(id) on delete set null,
  asset_id               uuid references public.assets(id) on delete set null,
  performed_by           uuid references auth.users(id) on delete set null,
  worker_name            text,
  designation            text,
  shift_name             text,
  status                 text not null default 'completed',
  notes                  text,
  failures               int not null default 0,
  work_date              date not null default current_date,
  next_due               timestamptz,
  performed_at           timestamptz not null default now(),
  completed_at           timestamptz,
  supervisor_approved_by uuid references auth.users(id) on delete set null,
  supervisor_approved_at timestamptz,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  removed_at             timestamptz
);


-- [attendance]  source: 0002_operations.sql
create table if not exists public.attendance (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id        uuid not null references public.plants(id) on delete cascade,
  user_id         uuid not null references auth.users(id) on delete cascade,
  work_date       date not null default current_date,
  shift_name      text,
  status          text not null default 'present',
  check_in        timestamptz,
  check_out       timestamptz,
  notes           text,
  created_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  removed_at      timestamptz,
  unique (plant_id, user_id, work_date)   -- matches upsert onConflict in operations.js
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


-- [daily_logs]  source: 0002_operations.sql
create table if not exists public.daily_logs (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id        uuid not null references public.plants(id) on delete cascade,
  log_date        date not null default current_date,
  work_date       date generated always as (log_date) stored,
  shift_name      text,
  category        text,
  entry           text not null,
  worker_name     text,
  designation     text,
  asset_id        uuid references public.assets(id) on delete set null,
  created_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  removed_at      timestamptz
);
