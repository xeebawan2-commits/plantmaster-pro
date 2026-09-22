-- ===========================================================================
-- PlantMaster Pro — 0005 platform & commercial
--   subscription plans and feature flags, invitations, in-company support,
--   platform complaint tickets, legal documents and consent, retention
--   policies, incidents, deletion requests and organization settings.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- PLANS
-- ---------------------------------------------------------------------------
create table if not exists public.subscription_plans (
  code              text primary key,
  name              text not null,
  price_monthly     numeric not null default 0,
  currency          text not null default 'PKR',
  max_users         int,
  max_plants        int,
  max_assets        int,
  storage_gb        numeric not null default 1,
  ai_requests_month int not null default 0,
  features          jsonb not null default '{}'::jsonb,
  active            boolean not null default true,
  sort_order        int not null default 0,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- SUPERSEDED PRICING — seeds only, never re-prices.
--
-- These were the original tiers (Starter 15,000 / Professional 45,000 /
-- Enterprise 120,000). Published pricing is now Basic 7,500 / Essential
-- 12,000 / Professional 24,000 / Enterprise 40,000, matching
-- site/pricing.html and the signed Subscription Agreement.
--
-- The `on conflict ... do update` below used to REPRICE every existing plan
-- back to the old figures, so re-running this migration would bill a live
-- customer against a tier they never agreed to. It is now `do nothing`:
-- the block still seeds a brand-new database, but can never overwrite a
-- price that is already set.
--
-- supabase/repairs/R5-final-pricing.sql is the current source of truth.
-- ---------------------------------------------------------------------------
insert into public.subscription_plans
  (code, name, price_monthly, max_users, max_plants, max_assets, storage_gb,
   ai_requests_month, sort_order, features)
values
  ('trial','Trial',            0,    5,  1,   100,   1,   50, 0,
   '{"branding":false,"ai":true,"condition_monitoring":true,"procurement":false,"api":false}'),
  ('starter','Starter',    15000,   15,  1,   500,   5,  300, 1,
   '{"branding":false,"ai":true,"condition_monitoring":true,"procurement":true,"api":false}'),
  ('professional','Professional', 45000, 60, 3, 3000, 25, 1500, 2,
   '{"branding":true,"ai":true,"condition_monitoring":true,"procurement":true,"api":false}'),
  ('enterprise','Enterprise',120000, null, null, null, 200, 10000, 3,
   '{"branding":true,"ai":true,"condition_monitoring":true,"procurement":true,"api":true}')
on conflict (code) do nothing;

-- Per-tenant overrides negotiated outside the standard plans.
create table if not exists public.organization_features (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  overrides       jsonb not null default '{}'::jsonb,
  note            text,
  updated_by      uuid references auth.users(id) on delete set null,
  updated_at      timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- ORGANIZATION SETTINGS (branding + daily report configuration)
-- ---------------------------------------------------------------------------
create table if not exists public.organization_settings (
  organization_id    uuid primary key references public.organizations(id) on delete cascade,
  plant_id           uuid references public.plants(id) on delete set null,
  app_name           text,
  plant_display_name text,
  primary_color      text default '#2563eb',
  secondary_color    text default '#0ea5e9',
  theme              text default 'dark',
  pattern            text default 'none',
  logo_path          text,
  address            text,
  contact            text,
  email              text,
  report_time        time default '11:00',
  report_recipients  text,
  footer_text        text,
  updated_by         uuid references auth.users(id) on delete set null,
  updated_at         timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- INVITATIONS
-- ---------------------------------------------------------------------------
create table if not exists public.invitations (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id        uuid references public.plants(id) on delete set null,
  email           text not null,
  role            public.member_role not null default 'technician',
  token           text not null unique default public.pm_random_token(),
  worker_details  jsonb not null default '{}'::jsonb,
  permissions     jsonb not null default '{}'::jsonb,
  expires_at      timestamptz not null default (now() + interval '14 days'),
  accepted_at     timestamptz,
  accepted_by     uuid references auth.users(id) on delete set null,
  created_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now()
);
create index if not exists invites_org_idx   on public.invitations(organization_id) where accepted_at is null;
create index if not exists invites_email_idx on public.invitations(lower(email));
create unique index if not exists invites_pending_unique
  on public.invitations(organization_id, lower(email)) where accepted_at is null;

-- ---------------------------------------------------------------------------
-- IN-COMPANY SUPPORT
-- ---------------------------------------------------------------------------
create table if not exists public.support_threads (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id        uuid references public.plants(id) on delete cascade,
  asset_id        uuid references public.assets(id) on delete set null,
  subject         text not null,
  priority        text not null default 'medium',
  status          text not null default 'open',
  created_by      uuid references auth.users(id) on delete set null,
  assigned_to     uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  closed_at       timestamptz
);
create index if not exists support_plant_idx on public.support_threads(plant_id, updated_at desc);

create table if not exists public.support_messages (
  id          uuid primary key default gen_random_uuid(),
  thread_id   uuid not null references public.support_threads(id) on delete cascade,
  user_id     uuid references auth.users(id) on delete set null,
  message     text not null,
  attachment_path text,
  created_at  timestamptz not null default now()
);
create index if not exists support_msg_thread_idx on public.support_messages(thread_id, created_at);

-- ---------------------------------------------------------------------------
-- PLATFORM COMPLAINTS (tenant owner <-> PlantMaster staff)
-- ---------------------------------------------------------------------------
create sequence if not exists public.app_complaint_number_seq;

create table if not exists public.app_complaints (
  id              uuid primary key default gen_random_uuid(),
  ticket_number   bigint not null default nextval('public.app_complaint_number_seq'),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  category        text not null default 'application',
  priority        text not null default 'medium',
  subject         text not null,
  description     text not null,
  status          text not null default 'open',
  app_version     text,
  device_info     jsonb default '{}'::jsonb,
  created_by      uuid references auth.users(id) on delete set null,
  assigned_to     uuid references auth.users(id) on delete set null,
  resolved_at     timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists complaints_org_idx    on public.app_complaints(organization_id, updated_at desc);
create index if not exists complaints_status_idx on public.app_complaints(status);

create table if not exists public.app_complaint_messages (
  id           uuid primary key default gen_random_uuid(),
  ticket_id    uuid not null references public.app_complaints(id) on delete cascade,
  user_id      uuid references auth.users(id) on delete set null,
  message      text not null,
  is_staff     boolean not null default false,
  created_at   timestamptz not null default now()
);
create index if not exists complaint_msg_idx on public.app_complaint_messages(ticket_id, created_at);

-- ---------------------------------------------------------------------------
-- LEGAL / COMPLIANCE
-- ---------------------------------------------------------------------------
create table if not exists public.legal_documents (
  id           uuid primary key default gen_random_uuid(),
  doc_type     text not null,              -- terms | privacy | dpa | safety
  version      text not null,
  title        text not null,
  body         text,
  url          text,
  locale       text not null default 'en',
  mandatory    boolean not null default true,
  active       boolean not null default true,
  effective_at timestamptz not null default now(),
  created_at   timestamptz not null default now(),
  unique (doc_type, version, locale)
);
create index if not exists legal_active_idx on public.legal_documents(active, effective_at desc);

create table if not exists public.legal_acceptances (
  id              uuid primary key default gen_random_uuid(),
  document_id     uuid not null references public.legal_documents(id) on delete cascade,
  organization_id uuid references public.organizations(id) on delete cascade,
  user_id         uuid not null references auth.users(id) on delete cascade,
  locale          text,
  user_agent_hash text,
  accepted_at     timestamptz not null default now(),
  unique (document_id, user_id, organization_id)
);
create index if not exists legal_accept_user_idx on public.legal_acceptances(user_id);

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

create table if not exists public.system_incidents (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  title           text not null,
  description     text,
  severity        text not null default 'minor',
  status          text not null default 'open',
  component       text,
  active          boolean not null default true,
  effective_at    timestamptz not null default now(),
  first_seen_at   timestamptz not null default now(),
  last_seen_at    timestamptz not null default now(),
  resolved_at     timestamptz,
  created_at      timestamptz not null default now()
);
create index if not exists incidents_org_idx on public.system_incidents(organization_id, last_seen_at desc);

create table if not exists public.deletion_requests (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  request_type    text not null,           -- account | organization | data_export
  status          text not null default 'requested',
  reason          text,
  requested_by    uuid references auth.users(id) on delete set null,
  processed_by    uuid references auth.users(id) on delete set null,
  processed_at    timestamptz,
  scheduled_for   timestamptz default (now() + interval '30 days'),
  created_at      timestamptz not null default now()
);
create index if not exists deletion_org_idx on public.deletion_requests(organization_id, status);

-- AI usage metering, needed by organization_plan_summary + the platform view.
create table if not exists public.ai_usage_events (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id         uuid references auth.users(id) on delete set null,
  function_name   text not null,
  mode            text,
  tokens_in       int default 0,
  tokens_out      int default 0,
  success         boolean not null default true,
  created_at      timestamptz not null default now()
);
create index if not exists ai_usage_org_idx on public.ai_usage_events(organization_id, created_at desc);

-- ===========================================================================
-- Triggers + policies
-- ===========================================================================
do $$
declare t text;
begin
  foreach t in array array[
    'organization_settings','invitations','support_threads','app_complaints',
    'system_incidents','deletion_requests','data_retention_policies']
  loop
    perform public.pm_attach_tenant_guards(t);
  end loop;
end $$;

-- Plans are public reference data (the marketing site prices from them).
alter table public.subscription_plans enable row level security;
drop policy if exists plans_read on public.subscription_plans;
create policy plans_read on public.subscription_plans
  for select to anon, authenticated using (true);
drop policy if exists plans_write on public.subscription_plans;
create policy plans_write on public.subscription_plans
  for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());

alter table public.organization_features enable row level security;
drop policy if exists org_features_select on public.organization_features;
create policy org_features_select on public.organization_features
  for select to authenticated using (public.is_org_member(organization_id));
drop policy if exists org_features_write on public.organization_features;
create policy org_features_write on public.organization_features
  for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());

-- Settings: every member reads branding; owners and managers edit.
alter table public.organization_settings enable row level security;
drop policy if exists org_settings_select on public.organization_settings;
create policy org_settings_select on public.organization_settings
  for select to authenticated using (public.is_org_member(organization_id));
drop policy if exists org_settings_write on public.organization_settings;
create policy org_settings_write on public.organization_settings
  for all to authenticated
  using (public.has_org_role(organization_id, 'manager')
         and public.can_write(organization_id))
  with check (public.has_org_role(organization_id, 'manager')
              and public.can_write(organization_id));

-- Invitations: managers manage them. The token is never exposed to members
-- who are not at least a manager, and acceptance happens via RPC.
alter table public.invitations enable row level security;
drop policy if exists invites_select on public.invitations;
create policy invites_select on public.invitations
  for select to authenticated
  using (public.has_org_role(organization_id, 'manager'));
drop policy if exists invites_write on public.invitations;
create policy invites_write on public.invitations
  for all to authenticated
  using (public.has_org_role(organization_id, 'manager')
         and public.can_write(organization_id))
  with check (public.has_org_role(organization_id, 'manager')
              and public.can_write(organization_id));

-- Support threads: visible to the whole plant, so a supervisor can help.
select public.pm_standard_policies('support_threads', 'operator');

alter table public.support_messages enable row level security;
drop policy if exists support_msg_select on public.support_messages;
create policy support_msg_select on public.support_messages
  for select to authenticated
  using (exists (select 1 from public.support_threads t
                 where t.id = thread_id and public.is_org_member(t.organization_id)));
drop policy if exists support_msg_insert on public.support_messages;
create policy support_msg_insert on public.support_messages
  for insert to authenticated
  with check (user_id = auth.uid()
              and exists (select 1 from public.support_threads t
                          where t.id = thread_id
                            and public.is_org_member(t.organization_id)
                            and public.can_write(t.organization_id)));

-- Platform complaints: the tenant owner and platform staff only.
alter table public.app_complaints enable row level security;
drop policy if exists complaints_select on public.app_complaints;
create policy complaints_select on public.app_complaints
  for select to authenticated
  using (public.is_org_owner(organization_id) or public.is_platform_admin());
drop policy if exists complaints_write on public.app_complaints;
create policy complaints_write on public.app_complaints
  for all to authenticated
  using (public.is_org_owner(organization_id) or public.is_platform_admin())
  with check (public.is_org_owner(organization_id) or public.is_platform_admin());

alter table public.app_complaint_messages enable row level security;
drop policy if exists complaint_msg_select on public.app_complaint_messages;
create policy complaint_msg_select on public.app_complaint_messages
  for select to authenticated
  using (exists (select 1 from public.app_complaints c
                 where c.id = ticket_id
                   and (public.is_org_owner(c.organization_id) or public.is_platform_admin())));
drop policy if exists complaint_msg_insert on public.app_complaint_messages;
create policy complaint_msg_insert on public.app_complaint_messages
  for insert to authenticated
  with check (exists (select 1 from public.app_complaints c
                 where c.id = ticket_id
                   and (public.is_org_owner(c.organization_id) or public.is_platform_admin())));

-- Legal documents are world-readable when active (the sites render them).
alter table public.legal_documents enable row level security;
drop policy if exists legal_read on public.legal_documents;
create policy legal_read on public.legal_documents
  for select to anon, authenticated using (active or public.is_platform_admin());
drop policy if exists legal_write on public.legal_documents;
create policy legal_write on public.legal_documents
  for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());

alter table public.legal_acceptances enable row level security;
drop policy if exists legal_accept_select on public.legal_acceptances;
create policy legal_accept_select on public.legal_acceptances
  for select to authenticated
  using (user_id = auth.uid()
         or (organization_id is not null and public.is_org_owner(organization_id)));
drop policy if exists legal_accept_insert on public.legal_acceptances;
create policy legal_accept_insert on public.legal_acceptances
  for insert to authenticated with check (user_id = auth.uid());

alter table public.data_retention_policies enable row level security;
drop policy if exists retention_select on public.data_retention_policies;
create policy retention_select on public.data_retention_policies
  for select to authenticated using (public.is_org_member(organization_id));
drop policy if exists retention_write on public.data_retention_policies;
create policy retention_write on public.data_retention_policies
  for all to authenticated
  using (public.is_org_owner(organization_id)) with check (public.is_org_owner(organization_id));

alter table public.system_incidents enable row level security;
drop policy if exists incidents_select on public.system_incidents;
create policy incidents_select on public.system_incidents
  for select to authenticated
  using (organization_id is null or public.is_org_member(organization_id));
drop policy if exists incidents_write on public.system_incidents;
create policy incidents_write on public.system_incidents
  for all to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());

alter table public.deletion_requests enable row level security;
drop policy if exists deletion_select on public.deletion_requests;
create policy deletion_select on public.deletion_requests
  for select to authenticated
  using (public.is_org_owner(organization_id) or public.is_platform_admin());
drop policy if exists deletion_insert on public.deletion_requests;
create policy deletion_insert on public.deletion_requests
  for insert to authenticated
  with check (public.is_org_owner(organization_id) and requested_by = auth.uid());
drop policy if exists deletion_update on public.deletion_requests;
create policy deletion_update on public.deletion_requests
  for update to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());

alter table public.ai_usage_events enable row level security;
drop policy if exists ai_usage_select on public.ai_usage_events;
create policy ai_usage_select on public.ai_usage_events
  for select to authenticated
  using (public.has_org_role(organization_id, 'manager'));
drop policy if exists ai_usage_insert on public.ai_usage_events;
create policy ai_usage_insert on public.ai_usage_events
  for insert to authenticated
  with check (public.is_org_member(organization_id));

-- Seed the baseline legal documents so the consent gate has something to show.
insert into public.legal_documents (doc_type, version, title, locale, url, mandatory, active)
values
  ('terms',  '1.0', 'Terms of Service', 'en', 'https://hsbfix.org/terms.html',   true, true),
  ('privacy','1.0', 'Privacy Policy',   'en', 'https://hsbfix.org/privacy.html', true, true)
on conflict (doc_type, version, locale) do nothing;
