-- PlantMaster Pro v4.9 Condition Monitoring: Sound & Vibration
-- Additive/idempotent. Does not alter existing operational workflows.

create table if not exists public.measurement_points(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id uuid not null references public.plants(id) on delete cascade,
  asset_id uuid references public.assets(id) on delete cascade,
  name text not null,
  direction text,
  description text,
  reference_photo_path text,
  active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique(asset_id,name,direction)
);

create table if not exists public.condition_recordings(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id uuid not null references public.plants(id) on delete cascade,
  asset_id uuid references public.assets(id) on delete set null,
  measurement_point_id uuid references public.measurement_points(id) on delete set null,
  recording_type text not null check(recording_type in ('voice_note','machine_sound','phone_vibration','external_vibration')),
  title text not null,
  operating_condition text,
  rpm numeric,
  load_percent numeric,
  temperature numeric,
  duration_seconds numeric,
  sample_rate numeric,
  device_info jsonb not null default '{}'::jsonb,
  calibration_status text not null default 'uncalibrated' check(calibration_status in ('uncalibrated','relative','calibrated')),
  audio_path text,
  audio_mime_type text,
  audio_size_bytes bigint,
  waveform jsonb not null default '[]'::jsonb,
  spectrum jsonb not null default '[]'::jsonb,
  vibration_samples jsonb not null default '[]'::jsonb,
  metrics jsonb not null default '{}'::jsonb,
  ai_analysis jsonb not null default '{}'::jsonb,
  manual_sources jsonb not null default '[]'::jsonb,
  baseline_id uuid references public.condition_recordings(id) on delete set null,
  comparison jsonb not null default '{}'::jsonb,
  is_baseline boolean not null default false,
  status text not null default 'completed' check(status in ('draft','recording','processing','completed','submitted','approved','failed')),
  condition_status text not null default 'unverified' check(condition_status in ('normal','changed','warning','alarm','unverified')),
  notes text,
  created_by uuid not null references auth.users(id),
  worker_name text not null,
  designation text,
  shift_name text,
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  removed_at timestamptz,
  removed_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists condition_recordings_org_time_idx on public.condition_recordings(organization_id,created_at desc);
create index if not exists condition_recordings_asset_time_idx on public.condition_recordings(asset_id,created_at desc);
create index if not exists condition_recordings_baseline_idx on public.condition_recordings(asset_id,measurement_point_id,is_baseline) where removed_at is null;

create table if not exists public.condition_alarms(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id uuid not null references public.plants(id) on delete cascade,
  asset_id uuid references public.assets(id) on delete cascade,
  recording_id uuid not null references public.condition_recordings(id) on delete cascade,
  alarm_type text not null,
  severity text not null check(severity in ('info','warning','alarm','critical')),
  message text not null,
  metric text,
  measured_value numeric,
  limit_value numeric,
  acknowledged_by uuid references auth.users(id),
  acknowledged_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists condition_alarms_org_time_idx on public.condition_alarms(organization_id,created_at desc);

create table if not exists public.sensor_devices(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id uuid references public.plants(id) on delete cascade,
  name text not null,
  sensor_type text not null check(sensor_type in ('phone','bluetooth_accelerometer','usb_sensor','industrial_monitor')),
  manufacturer text,
  model text,
  serial_number text,
  calibration_date date,
  calibration_due date,
  protocol_details jsonb not null default '{}'::jsonb,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.condition_entity_links(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  recording_id uuid not null references public.condition_recordings(id) on delete cascade,
  entity_type text not null,
  entity_id text not null,
  relation text not null default 'evidence',
  linked_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique(recording_id,entity_type,entity_id,relation)
);

alter table public.measurement_points enable row level security;
alter table public.condition_recordings enable row level security;
alter table public.condition_alarms enable row level security;
alter table public.sensor_devices enable row level security;
alter table public.condition_entity_links enable row level security;

do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='measurement_points' and policyname='condition points member access') then create policy "condition points member access" on public.measurement_points for all to authenticated using(public.is_org_member(organization_id)) with check(public.is_org_member(organization_id));end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='condition_recordings' and policyname='condition recordings member access') then create policy "condition recordings member access" on public.condition_recordings for all to authenticated using(public.is_org_member(organization_id)) with check(public.is_org_member(organization_id));end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='condition_alarms' and policyname='condition alarms member access') then create policy "condition alarms member access" on public.condition_alarms for all to authenticated using(public.is_org_member(organization_id)) with check(public.is_org_member(organization_id));end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='sensor_devices' and policyname='condition sensors member access') then create policy "condition sensors member access" on public.sensor_devices for all to authenticated using(public.is_org_member(organization_id)) with check(public.is_org_member(organization_id));end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='condition_entity_links' and policyname='condition links member access') then create policy "condition links member access" on public.condition_entity_links for all to authenticated using(public.is_org_member(organization_id)) with check(public.is_org_member(organization_id));end if;
end $$;

grant select,insert,update,delete on public.measurement_points,public.condition_recordings,public.condition_alarms,public.sensor_devices,public.condition_entity_links to authenticated;
grant usage,select on all sequences in schema public to authenticated;

-- Respect company commercial lifecycle.
do $$ declare t text;n text;begin
  foreach t in array array['measurement_points','condition_recordings','condition_alarms','sensor_devices','condition_entity_links'] loop
    n:='commercial_write_guard_'||t;
    if not exists(select 1 from pg_trigger where tgname=n and not tgisinternal) then execute format('create trigger %I before insert or update or delete on public.%I for each row execute function public.require_commercial_write_access()',n,t);end if;
  end loop;
end $$;

-- Baselines require an engineering/leadership role and record approval identity.
create or replace function public.protect_condition_baseline()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.is_baseline and (tg_op='INSERT' or not coalesce(old.is_baseline,false)) then
    if public.org_role(new.organization_id) not in ('owner','manager','engineer') then raise exception 'Owner, manager or engineer approval is required for a baseline';end if;
    new.approved_by:=auth.uid();new.approved_at:=coalesce(new.approved_at,now());new.status:='approved';
  end if;
  return new;
end $$;
do $$ begin
  if not exists(select 1 from pg_trigger where tgname='protect_condition_baseline' and not tgisinternal) then create trigger protect_condition_baseline before insert or update of is_baseline on public.condition_recordings for each row execute function public.protect_condition_baseline();end if;
end $$;

-- Owner-only hard erase; normal UI uses Recovery.
do $$ begin
  if not exists(select 1 from pg_trigger where tgname='owner_hard_delete_condition_recordings' and not tgisinternal) then create trigger owner_hard_delete_condition_recordings before delete on public.condition_recordings for each row execute function public.require_owner_for_hard_delete();end if;
end $$;

-- Realtime condition log.
do $$ begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='condition_recordings') then alter publication supabase_realtime add table public.condition_recordings;end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='condition_alarms') then alter publication supabase_realtime add table public.condition_alarms;end if;
end $$;
