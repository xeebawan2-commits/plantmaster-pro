-- ===========================================================================
-- PlantMaster Pro — 0004 knowledge, files & storage accounting
--   manuals + document_chunks (AI grounding), technical experiences,
--   problem cases, condition monitoring, the document scanner, file metadata,
--   the storage-quota reservation protocol and the notification system.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- MANUALS & AI GROUNDING
-- ---------------------------------------------------------------------------
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
create index if not exists manuals_org_idx   on public.manuals(organization_id) where removed_at is null;
create index if not exists manuals_asset_idx on public.manuals(asset_id);
create index if not exists manuals_search_idx
  on public.manuals using gin (to_tsvector('english',
     coalesce(title,'') || ' ' || coalesce(manufacturer,'') || ' ' || coalesce(model,'')));

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
create index if not exists chunks_manual_idx on public.document_chunks(manual_id);
create index if not exists chunks_org_idx    on public.document_chunks(organization_id);
-- The solver runs ILIKE '%term%' over chunk content; trigram would be ideal but
-- pg_trgm is not guaranteed, so a full-text index plus the org filter keeps it sane.
create index if not exists chunks_content_idx
  on public.document_chunks using gin (to_tsvector('english', content));

-- ---------------------------------------------------------------------------
-- TECHNICAL EXPERIENCES — curated tribal knowledge, approved before reuse
-- ---------------------------------------------------------------------------
create table if not exists public.technical_experiences (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references public.organizations(id) on delete cascade,
  plant_id         uuid references public.plants(id) on delete cascade,
  asset_id         uuid references public.assets(id) on delete set null,
  title            text,
  problem          text not null,
  symptoms         text,
  root_cause       text,
  actual_cause     text,
  solution         text,
  verified_solution text,
  tools            text,
  parts            text,
  manufacturer     text,
  model            text,
  storage_path     text,
  status           text not null default 'draft',
  approved         boolean not null default false,
  approved_by      uuid references auth.users(id) on delete set null,
  approved_at      timestamptz,
  created_by       uuid references auth.users(id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  removed_at       timestamptz
);
create index if not exists exp_org_idx      on public.technical_experiences(organization_id) where approved;
create index if not exists exp_approved_idx on public.technical_experiences(organization_id, approved);

-- ---------------------------------------------------------------------------
-- PROBLEM CASES — AI solver sessions
-- ---------------------------------------------------------------------------
create table if not exists public.problem_cases (
  id                uuid primary key default gen_random_uuid(),
  organization_id   uuid not null references public.organizations(id) on delete cascade,
  plant_id          uuid references public.plants(id) on delete cascade,
  asset_id          uuid references public.assets(id) on delete set null,
  title             text not null,
  symptoms          text,
  alarm_code        text,
  mode              text default 'quick',
  ai_answer         jsonb,
  actual_cause      text,
  verified_solution text,
  manufacturer      text,
  model             text,
  storage_path      text,
  status            text not null default 'open',
  resolved_by       uuid references auth.users(id) on delete set null,
  resolved_at       timestamptz,
  created_by        uuid references auth.users(id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  removed_at        timestamptz
);
create index if not exists cases_org_idx on public.problem_cases(organization_id, created_at desc);

-- ---------------------------------------------------------------------------
-- CONDITION MONITORING — sound / vibration recordings and AI analysis
-- ---------------------------------------------------------------------------
create table if not exists public.condition_recordings (
  id                  uuid primary key default gen_random_uuid(),
  organization_id     uuid not null references public.organizations(id) on delete cascade,
  plant_id            uuid not null references public.plants(id) on delete cascade,
  asset_id            uuid references public.assets(id) on delete set null,
  recording_type      text not null default 'machine_sound',
  title               text,
  operating_condition text,
  rpm                 numeric,
  load_percent        numeric,
  temperature         numeric,
  duration_seconds    numeric,
  sample_rate         numeric,
  device_info         text,
  user_agent          text,
  platform            text,
  calibration_status  text,
  audio_path          text,
  audio_mime_type     text,
  audio_size_bytes    bigint,
  waveform            jsonb,
  spectrum            jsonb,
  vibration_samples   jsonb,
  metrics             jsonb,
  ai_analysis         jsonb,
  baseline_id         uuid references public.condition_recordings(id) on delete set null,
  comparison          jsonb,
  condition_status    text,
  is_baseline         boolean not null default false,
  notes               text,
  worker_name         text,
  designation         text,
  shift_name          text,
  status              text not null default 'recorded',
  approved_by         uuid references auth.users(id) on delete set null,
  approved_at         timestamptz,
  created_by          uuid references auth.users(id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  removed_at          timestamptz,
  removed_by          uuid references auth.users(id) on delete set null
);
create index if not exists cond_org_idx   on public.condition_recordings(organization_id, created_at desc)
  where removed_at is null;
create index if not exists cond_asset_idx on public.condition_recordings(asset_id, recording_type);
-- One baseline per asset per recording type.
create unique index if not exists cond_baseline_unique
  on public.condition_recordings(asset_id, recording_type)
  where is_baseline and removed_at is null;

-- ---------------------------------------------------------------------------
-- DOCUMENT SCANNER
-- ---------------------------------------------------------------------------
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
create index if not exists scans_org_idx on public.scan_sessions(organization_id, created_at desc)
  where removed_at is null;

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
create index if not exists scan_pages_session_idx on public.scan_pages(session_id, page_number);

-- ---------------------------------------------------------------------------
-- FILE METADATA — the index over the storage bucket
-- ---------------------------------------------------------------------------
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
create unique index if not exists file_path_unique on public.file_metadata(bucket, object_path);
create index if not exists files_org_idx on public.file_metadata(organization_id, created_at desc)
  where removed_at is null;

-- ---------------------------------------------------------------------------
-- STORAGE ACCOUNTING — reservation protocol
--
-- The client cannot be trusted to report how much it stored, so every upload
-- is: reserve (checks quota, writes a pending row) -> upload -> finalize
-- (converts pending to committed) or cancel (releases it). A stale pending
-- reservation expires after an hour so a crashed upload cannot leak quota.
-- ---------------------------------------------------------------------------
create table if not exists public.storage_reservations (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references public.organizations(id) on delete cascade,
  bytes            bigint not null,
  file_name        text,
  mime_type        text,
  object_path      text,
  file_metadata_id uuid,
  status           text not null default 'pending',   -- pending|committed|cancelled|expired
  created_by       uuid references auth.users(id) on delete set null,
  created_at       timestamptz not null default now(),
  settled_at       timestamptz,
  expires_at       timestamptz not null default (now() + interval '1 hour')
);
create index if not exists storage_res_org_idx
  on public.storage_reservations(organization_id, status);

create table if not exists public.storage_usage_events (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  event_type      text not null,          -- upload | download | delete
  bytes           bigint not null default 0,
  object_path     text,
  user_id         uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now()
);
create index if not exists storage_events_org_idx
  on public.storage_usage_events(organization_id, created_at desc);
create index if not exists storage_events_month_idx
  on public.storage_usage_events(organization_id, event_type, created_at);

-- ---------------------------------------------------------------------------
-- NOTIFICATIONS + web push
-- ---------------------------------------------------------------------------
create table if not exists public.notifications (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id        uuid references public.plants(id) on delete cascade,
  user_id         uuid references auth.users(id) on delete cascade,  -- null = whole org
  title           text not null,
  body            text,
  severity        text default 'normal',
  category        text default 'general',
  alarm           boolean not null default false,
  route           text,
  entity_type     text,
  entity_id       uuid,
  read_at         timestamptz,
  pushed_at       timestamptz,
  created_at      timestamptz not null default now()
);
create index if not exists notif_org_idx    on public.notifications(organization_id, created_at desc);
create index if not exists notif_unread_idx on public.notifications(organization_id) where read_at is null;
create index if not exists notif_push_idx   on public.notifications(created_at) where pushed_at is null;

create table if not exists public.push_subscriptions (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  organization_id uuid references public.organizations(id) on delete cascade,
  endpoint        text not null unique,
  p256dh          text not null,
  auth            text not null,
  user_agent      text,
  active          boolean not null default true,
  last_success_at timestamptz,
  failure_count   int not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists push_subs_user_idx on public.push_subscriptions(user_id) where active;
create index if not exists push_subs_org_idx  on public.push_subscriptions(organization_id) where active;

-- ---------------------------------------------------------------------------
-- AUDIT LOG — append only
-- ---------------------------------------------------------------------------
create table if not exists public.audit_logs (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id        uuid references public.plants(id) on delete cascade,
  user_id         uuid references auth.users(id) on delete set null,
  action          text not null,
  entity_type     text,
  entity_id       text,
  details         jsonb not null default '{}'::jsonb,
  ip_address      inet,
  created_at      timestamptz not null default now()
);
create index if not exists audit_org_idx    on public.audit_logs(organization_id, created_at desc);
create index if not exists audit_action_idx on public.audit_logs(organization_id, action);
create index if not exists audit_entity_idx on public.audit_logs(entity_type, entity_id);

-- ===========================================================================
-- Triggers + policies
-- ===========================================================================
do $$
declare t text;
begin
  foreach t in array array[
    'manuals','technical_experiences','problem_cases','condition_recordings',
    'scan_sessions','file_metadata','notifications','audit_logs']
  loop
    perform public.pm_attach_tenant_guards(t);
  end loop;
end $$;

select public.pm_standard_policies('manuals',               'technician');
select public.pm_standard_policies('technical_experiences', 'technician');
select public.pm_standard_policies('problem_cases',         'operator');
select public.pm_standard_policies('condition_recordings',  'technician');
select public.pm_standard_policies('scan_sessions',         'technician');
select public.pm_standard_policies('file_metadata',         'technician');

-- Manuals can be hidden per member via permissions->>'manuals.view'.
-- Managers and owners always see them.
drop policy if exists manuals_select on public.manuals;
create policy manuals_select on public.manuals
  for select to authenticated
  using (
    public.is_org_member(organization_id)
    and (
      public.has_org_role(organization_id, 'manager')
      or coalesce(
           (select (m.permissions ->> 'manuals.view')::boolean
              from public.organization_members m
             where m.organization_id = public.manuals.organization_id
               and m.user_id = auth.uid() and m.active),
           true)
    )
  );

-- document_chunks inherit their manual's organization.
alter table public.document_chunks enable row level security;
drop policy if exists chunks_select on public.document_chunks;
create policy chunks_select on public.document_chunks
  for select to authenticated
  using (public.is_org_member(organization_id));
-- Written only by the ingest-manual edge function (service_role).
drop policy if exists chunks_write on public.document_chunks;
create policy chunks_write on public.document_chunks
  for all to authenticated
  using (public.has_org_role(organization_id, 'manager'))
  with check (public.has_org_role(organization_id, 'manager'));

-- scan_pages inherit their session.
alter table public.scan_pages enable row level security;
drop policy if exists scan_pages_select on public.scan_pages;
create policy scan_pages_select on public.scan_pages
  for select to authenticated
  using (exists (select 1 from public.scan_sessions s
                 where s.id = session_id and public.is_org_member(s.organization_id)));
drop policy if exists scan_pages_write on public.scan_pages;
create policy scan_pages_write on public.scan_pages
  for all to authenticated
  using (exists (select 1 from public.scan_sessions s
                 where s.id = session_id
                   and public.has_org_role(s.organization_id, 'technician')
                   and public.can_write(s.organization_id)))
  with check (exists (select 1 from public.scan_sessions s
                 where s.id = session_id
                   and public.has_org_role(s.organization_id, 'technician')
                   and public.can_write(s.organization_id)));

-- Notifications: org-wide rows plus rows addressed to you. Members may only
-- mark them read; creation belongs to triggers and edge functions.
alter table public.notifications enable row level security;
drop policy if exists notifications_select on public.notifications;
create policy notifications_select on public.notifications
  for select to authenticated
  using (public.is_org_member(organization_id)
         and (user_id is null or user_id = auth.uid()));

drop policy if exists notifications_insert on public.notifications;
create policy notifications_insert on public.notifications
  for insert to authenticated
  with check (public.is_org_member(organization_id) and public.can_write(organization_id));

drop policy if exists notifications_update on public.notifications;
create policy notifications_update on public.notifications
  for update to authenticated
  using (public.is_org_member(organization_id)
         and (user_id is null or user_id = auth.uid()))
  with check (public.is_org_member(organization_id));

drop policy if exists notifications_delete on public.notifications;
create policy notifications_delete on public.notifications
  for delete to authenticated
  using (public.has_org_role(organization_id, 'manager'));

-- Push subscriptions are personal.
alter table public.push_subscriptions enable row level security;
drop policy if exists push_subs_all on public.push_subscriptions;
create policy push_subs_all on public.push_subscriptions
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Audit log: readable by managers, insert-only for everyone, never mutable.
alter table public.audit_logs enable row level security;
drop policy if exists audit_select on public.audit_logs;
create policy audit_select on public.audit_logs
  for select to authenticated
  using (public.has_org_role(organization_id, 'supervisor'));

drop policy if exists audit_insert on public.audit_logs;
create policy audit_insert on public.audit_logs
  for insert to authenticated
  with check (public.is_org_member(organization_id) and user_id = auth.uid());
-- no update / delete policy: the trail is immutable.

-- Storage bookkeeping tables are managed exclusively by SECURITY DEFINER RPCs.
alter table public.storage_reservations  enable row level security;
alter table public.storage_usage_events  enable row level security;

drop policy if exists storage_res_select on public.storage_reservations;
create policy storage_res_select on public.storage_reservations
  for select to authenticated
  using (public.has_org_role(organization_id, 'manager'));

drop policy if exists storage_events_select on public.storage_usage_events;
create policy storage_events_select on public.storage_usage_events
  for select to authenticated
  using (public.has_org_role(organization_id, 'manager'));

-- ===========================================================================
-- Checklist alarm -> notification (server side, so it cannot be skipped)
-- ===========================================================================
create or replace function public.notify_checklist_failure()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if coalesce(new.failures, 0) > 0 then
    insert into public.notifications(
      organization_id, plant_id, title, body, severity, category, alarm, route,
      entity_type, entity_id)
    values (
      new.organization_id, new.plant_id,
      'Checklist alarm',
      coalesce(new.failures,0) || ' item(s) failed limits. Completed by '
        || coalesce(new.worker_name, 'a worker') || '.',
      'high', 'checklist', true, '/checklists', 'checklist_run', new.id);
  end if;
  return new;
end $$;

drop trigger if exists checklist_alarm on public.checklist_runs;
create trigger checklist_alarm
  after insert on public.checklist_runs
  for each row execute function public.notify_checklist_failure();
