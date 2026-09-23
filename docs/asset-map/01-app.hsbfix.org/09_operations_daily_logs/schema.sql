-- ============================================================
-- Schema for this section (auto-extracted from the repo / live snapshot)
-- ============================================================


-- ---------- TABLES ----------


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


-- [shift_assignments]  source: 0002_operations.sql
create table if not exists public.shift_assignments (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id        uuid not null references public.plants(id) on delete cascade,
  user_id         uuid not null references auth.users(id) on delete cascade,
  work_date       date not null default current_date,
  shift_name      text not null default 'General Shift',
  role_note       text,
  created_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (plant_id, user_id, work_date)
);


-- [shift_handovers]  source: 0002_operations.sql
create table if not exists public.shift_handovers (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id        uuid not null references public.plants(id) on delete cascade,
  work_date       date not null default current_date,
  from_shift      text,
  to_shift        text,
  summary         text,
  pending_work    text,
  safety_notes    text,
  acknowledged_by uuid references auth.users(id) on delete set null,
  acknowledged_at timestamptz,
  created_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);


-- [checklist_templates]  source: 0002_operations.sql
create table if not exists public.checklist_templates (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id        uuid not null references public.plants(id) on delete cascade,
  asset_id        uuid references public.assets(id) on delete set null,
  name            text not null,
  schedule        text,
  shift_name      text,
  instructions    text,
  active          boolean not null default true,
  created_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  removed_at      timestamptz
);


-- [checklist_items]  source: 0002_operations.sql
create table if not exists public.checklist_items (
  id           uuid primary key default gen_random_uuid(),
  template_id  uuid not null references public.checklist_templates(id) on delete cascade,
  position     int not null default 0,
  label        text not null,
  input_type   text not null default 'yes_no',
  unit         text,
  min_value    numeric,
  max_value    numeric,
  required     boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
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


-- [checklist_values]  source: 0002_operations.sql
create table if not exists public.checklist_values (
  id         uuid primary key default gen_random_uuid(),
  run_id     uuid not null references public.checklist_runs(id) on delete cascade,
  item_id    uuid references public.checklist_items(id) on delete set null,
  label      text,
  value      text,
  numeric_value numeric,
  in_range   boolean,
  remark     text,
  created_at timestamptz not null default now()
);


-- [maintenance_plans]  source: 0002_operations.sql
create table if not exists public.maintenance_plans (
  id                uuid primary key default gen_random_uuid(),
  organization_id   uuid not null references public.organizations(id) on delete cascade,
  plant_id          uuid not null references public.plants(id) on delete cascade,
  asset_id          uuid references public.assets(id) on delete set null,
  title             text not null,
  description       text,
  frequency         text,
  interval_days     int,
  priority          text default 'medium',
  next_due          date,
  status            text not null default 'scheduled',
  last_completed_at timestamptz,
  last_completed_by uuid references auth.users(id) on delete set null,
  created_by        uuid references auth.users(id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  removed_at        timestamptz
);


-- [maintenance_completions]  source: 0002_operations.sql
create table if not exists public.maintenance_completions (
  id                uuid primary key default gen_random_uuid(),
  organization_id   uuid not null references public.organizations(id) on delete cascade,
  plant_id          uuid not null references public.plants(id) on delete cascade,
  plan_id           uuid references public.maintenance_plans(id) on delete cascade,
  work_done         text,
  worker_id         uuid references auth.users(id) on delete set null,
  shift_name        text,
  tools_used        text,
  parts_used        text,
  measurements      text,
  text              text,
  root_cause        text,
  corrective_action text,
  downtime_minutes  numeric default 0,
  completed_at      timestamptz not null default now(),
  created_at        timestamptz not null default now()
);
