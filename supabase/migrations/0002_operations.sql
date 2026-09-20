-- ===========================================================================
-- PlantMaster Pro — 0002 operations
--   assets, work orders, safety (permits + LOTO), attendance, shifts,
--   daily logs, checklists and preventive maintenance.
--
-- Tenancy rule used throughout: every operational row carries BOTH
-- organization_id and plant_id. plant_id drives the UI's scoping and
-- organization_id keeps authorization cheap (no join needed in the policy).
-- A trigger keeps the two consistent so a client cannot post a plant from
-- another tenant.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Guard: organization_id must match the plant's real owner.
-- ---------------------------------------------------------------------------
create or replace function public.enforce_plant_org()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  real_org uuid;
begin
  if new.plant_id is null then
    return new;
  end if;
  select organization_id into real_org from public.plants where id = new.plant_id;
  if real_org is null then
    raise exception 'plant % does not exist', new.plant_id using errcode = '23503';
  end if;
  if new.organization_id is null then
    new.organization_id := real_org;
  elsif new.organization_id <> real_org then
    raise exception 'plant % belongs to organization %, not %',
      new.plant_id, real_org, new.organization_id using errcode = '42501';
  end if;
  return new;
end $$;

-- Applies the guard + updated_at to a table in one call.
create or replace function public.pm_attach_tenant_guards(p_table text)
returns void
language plpgsql
as $$
begin
  -- The guard dereferences NEW.plant_id, so it may only be attached to tables
  -- that actually have that column (e.g. data_retention_policies does not).
  execute format('drop trigger if exists guard_%1$s on public.%1$s', p_table);
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name=p_table and column_name='plant_id')
  then
    execute format(
      'create trigger guard_%1$s before insert or update on public.%1$s
       for each row execute function public.enforce_plant_org()', p_table);
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name=p_table and column_name='updated_at')
  then
    execute format('drop trigger if exists touch_%1$s on public.%1$s', p_table);
    execute format(
      'create trigger touch_%1$s before update on public.%1$s
       for each row execute function public.touch_updated_at()', p_table);
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Standard policy generator.
--   read  : any active member of the org
--   write : role >= p_min_write AND not a viewer
-- Soft-deleted rows stay visible (the Recovery Bin restores them).
-- ---------------------------------------------------------------------------
create or replace function public.pm_standard_policies(
  p_table text,
  p_min_write public.member_role default 'technician'
) returns void
language plpgsql
as $$
begin
  execute format('alter table public.%I enable row level security', p_table);

  execute format('drop policy if exists %1$s_select on public.%1$s', p_table);
  execute format(
    'create policy %1$s_select on public.%1$s for select to authenticated
       using (public.is_org_member(organization_id))', p_table);

  execute format('drop policy if exists %1$s_insert on public.%1$s', p_table);
  execute format(
    'create policy %1$s_insert on public.%1$s for insert to authenticated
       with check (public.has_org_role(organization_id, %L)
                   and public.can_write(organization_id))', p_table, p_min_write);

  execute format('drop policy if exists %1$s_update on public.%1$s', p_table);
  execute format(
    'create policy %1$s_update on public.%1$s for update to authenticated
       using (public.has_org_role(organization_id, %L)
              and public.can_write(organization_id))
       with check (public.has_org_role(organization_id, %L)
                   and public.can_write(organization_id))',
    p_table, p_min_write, p_min_write);

  -- Hard DELETE is reserved for managers; normal flows soft-delete.
  execute format('drop policy if exists %1$s_delete on public.%1$s', p_table);
  execute format(
    'create policy %1$s_delete on public.%1$s for delete to authenticated
       using (public.has_org_role(organization_id, ''manager'')
              and public.can_write(organization_id))', p_table);
end $$;

-- ===========================================================================
-- ASSETS
-- ===========================================================================
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
create index if not exists assets_plant_idx  on public.assets(plant_id) where removed_at is null;
create index if not exists assets_org_idx    on public.assets(organization_id);
create index if not exists assets_code_idx   on public.assets(organization_id, asset_code);
create index if not exists assets_updated_idx on public.assets(plant_id, updated_at desc);
-- Asset codes are scanned by QR: they must be unique per tenant.
create unique index if not exists assets_code_unique
  on public.assets(organization_id, asset_code)
  where asset_code is not null and removed_at is null;

-- ===========================================================================
-- WORK ORDERS
-- ===========================================================================
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
create index if not exists wo_plant_idx    on public.work_orders(plant_id) where removed_at is null;
create index if not exists wo_org_idx      on public.work_orders(organization_id);
create index if not exists wo_asset_idx    on public.work_orders(asset_id);
create index if not exists wo_status_idx   on public.work_orders(plant_id, status);
create index if not exists wo_assigned_idx on public.work_orders(assigned_to) where completed_at is null;
create index if not exists wo_updated_idx  on public.work_orders(plant_id, updated_at desc);

-- ===========================================================================
-- SAFETY — permits to work and lock-out / tag-out
-- ===========================================================================
create table if not exists public.permits (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  plant_id        uuid not null references public.plants(id) on delete cascade,
  work_order_id   uuid references public.work_orders(id) on delete cascade,
  permit_type     text not null,
  status          text not null default 'requested',
  requested_by    uuid references auth.users(id) on delete set null,
  approved_by     uuid references auth.users(id) on delete set null,
  approved_at     timestamptz,
  closed_at       timestamptz,
  valid_from      timestamptz,
  valid_to        timestamptz,
  precautions     text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists permits_wo_idx    on public.permits(work_order_id);
create index if not exists permits_plant_idx on public.permits(plant_id, status);

create table if not exists public.loto_procedures (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  plant_id        uuid not null references public.plants(id) on delete cascade,
  work_order_id   uuid references public.work_orders(id) on delete cascade,
  asset_id        uuid references public.assets(id) on delete set null,
  isolation_points text,
  applied_by      uuid references auth.users(id) on delete set null,
  applied_at      timestamptz not null default now(),
  verified_by     uuid references auth.users(id) on delete set null,
  removed_at      timestamptz,
  removed_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists loto_wo_idx    on public.loto_procedures(work_order_id);
create index if not exists loto_plant_idx on public.loto_procedures(plant_id) where removed_at is null;

-- ===========================================================================
-- PEOPLE — attendance, shift assignments, handovers, daily logs
-- ===========================================================================
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
create index if not exists attendance_lookup_idx on public.attendance(organization_id, work_date);
create index if not exists attendance_plant_idx  on public.attendance(plant_id, work_date desc);

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
create index if not exists shift_assign_idx on public.shift_assignments(plant_id, work_date desc);

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
create index if not exists handover_plant_idx on public.shift_handovers(plant_id, created_at desc);

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
create index if not exists daily_logs_plant_idx on public.daily_logs(plant_id, created_at desc);
create index if not exists daily_logs_date_idx  on public.daily_logs(organization_id, log_date);

-- ===========================================================================
-- CHECKLISTS
-- ===========================================================================
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
create index if not exists cl_templates_plant_idx on public.checklist_templates(plant_id) where removed_at is null;

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
create index if not exists cl_items_template_idx on public.checklist_items(template_id, position);

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
create index if not exists cl_runs_plant_idx    on public.checklist_runs(plant_id, performed_at desc);
create index if not exists cl_runs_template_idx on public.checklist_runs(template_id);

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
create index if not exists cl_values_run_idx on public.checklist_values(run_id);

-- ===========================================================================
-- PREVENTIVE MAINTENANCE
-- ===========================================================================
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
create index if not exists mp_plant_idx on public.maintenance_plans(plant_id) where removed_at is null;
create index if not exists mp_due_idx   on public.maintenance_plans(plant_id, next_due);

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
create index if not exists mc_plant_idx on public.maintenance_completions(plant_id, completed_at desc);
create index if not exists mc_plan_idx  on public.maintenance_completions(plan_id);

-- ===========================================================================
-- Triggers + policies
-- ===========================================================================
do $$
declare t text;
begin
  foreach t in array array[
    'assets','work_orders','permits','loto_procedures','attendance',
    'shift_assignments','shift_handovers','daily_logs','checklist_templates',
    'checklist_runs','maintenance_plans','maintenance_completions']
  loop
    perform public.pm_attach_tenant_guards(t);
  end loop;
end $$;

-- Operational records: any technician-and-above may create/edit.
select public.pm_standard_policies('assets',                  'technician');
select public.pm_standard_policies('work_orders',             'operator');
select public.pm_standard_policies('daily_logs',              'operator');
select public.pm_standard_policies('shift_handovers',         'operator');
select public.pm_standard_policies('checklist_runs',          'operator');
select public.pm_standard_policies('maintenance_completions', 'technician');
-- Definitions and rosters: supervisor and above.
select public.pm_standard_policies('checklist_templates',     'supervisor');
select public.pm_standard_policies('maintenance_plans',       'supervisor');
select public.pm_standard_policies('attendance',              'supervisor');
select public.pm_standard_policies('shift_assignments',       'supervisor');
-- Safety documents: supervisor and above (approval is further gated below).
select public.pm_standard_policies('permits',                 'supervisor');
select public.pm_standard_policies('loto_procedures',         'technician');

-- ---------------------------------------------------------------------------
-- Child tables authorize through their parent.
-- ---------------------------------------------------------------------------
alter table public.checklist_items  enable row level security;
alter table public.checklist_values enable row level security;

drop policy if exists checklist_items_select on public.checklist_items;
create policy checklist_items_select on public.checklist_items
  for select to authenticated
  using (exists (select 1 from public.checklist_templates t
                 where t.id = template_id and public.is_org_member(t.organization_id)));

drop policy if exists checklist_items_write on public.checklist_items;
create policy checklist_items_write on public.checklist_items
  for all to authenticated
  using (exists (select 1 from public.checklist_templates t
                 where t.id = template_id
                   and public.has_org_role(t.organization_id, 'supervisor')
                   and public.can_write(t.organization_id)))
  with check (exists (select 1 from public.checklist_templates t
                 where t.id = template_id
                   and public.has_org_role(t.organization_id, 'supervisor')
                   and public.can_write(t.organization_id)));

drop policy if exists checklist_values_select on public.checklist_values;
create policy checklist_values_select on public.checklist_values
  for select to authenticated
  using (exists (select 1 from public.checklist_runs r
                 where r.id = run_id and public.is_org_member(r.organization_id)));

drop policy if exists checklist_values_write on public.checklist_values;
create policy checklist_values_write on public.checklist_values
  for all to authenticated
  using (exists (select 1 from public.checklist_runs r
                 where r.id = run_id
                   and public.has_org_role(r.organization_id, 'operator')
                   and public.can_write(r.organization_id)))
  with check (exists (select 1 from public.checklist_runs r
                 where r.id = run_id
                   and public.has_org_role(r.organization_id, 'operator')
                   and public.can_write(r.organization_id)));

-- ---------------------------------------------------------------------------
-- Safety interlock: only supervisor+ may move a permit into 'approved', and
-- never the same person who requested it. Enforced in the database because a
-- client-side check is not a safety control.
-- ---------------------------------------------------------------------------
create or replace function public.enforce_permit_approval()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.status = 'approved' and coalesce(old.status, '') <> 'approved' then
    if not public.has_org_role(
         coalesce(new.organization_id, public.plant_org(new.plant_id)), 'supervisor') then
      raise exception 'Only a supervisor or above can approve a permit to work'
        using errcode = '42501';
    end if;
    if new.requested_by is not null and new.approved_by = new.requested_by then
      raise exception 'A permit cannot be approved by the person who requested it'
        using errcode = '42501';
    end if;
    new.approved_by := coalesce(new.approved_by, auth.uid());
    new.approved_at := coalesce(new.approved_at, now());
  end if;
  return new;
end $$;

drop trigger if exists permit_approval_guard on public.permits;
create trigger permit_approval_guard
  before update on public.permits
  for each row execute function public.enforce_permit_approval();

-- Work order completion stamps itself.
create or replace function public.stamp_work_order_completion()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.status in ('completed','closed','done')
     and coalesce(old.status,'') not in ('completed','closed','done') then
    new.completed_at := coalesce(new.completed_at, now());
    new.completed_by := coalesce(new.completed_by, auth.uid());
  end if;
  return new;
end $$;

drop trigger if exists wo_completion_stamp on public.work_orders;
create trigger wo_completion_stamp
  before update on public.work_orders
  for each row execute function public.stamp_work_order_completion();
