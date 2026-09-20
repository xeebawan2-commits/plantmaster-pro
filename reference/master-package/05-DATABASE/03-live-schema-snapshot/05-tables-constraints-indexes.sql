-- =====================================================================
-- PlantMaster Pro — FULL DATABASE SCHEMA (reconstructed)
-- Project dpmmenwziplixrgylapy · captured 13 September 2026
--
-- 83 tables · 381 constraints · 140 indexes · 61 triggers · 135 RLS policies
--
-- Rebuilt from the live catalog exports. Run order:
--   1. this file (tables, constraints, indexes)
--   2. 02-function-source.sql   (73 functions)
--   3. 06-rls-policies.sql      (135 policies)
--   4. re-run the trigger section at the bottom of this file
--      (triggers need their functions to exist first)
--
-- NOTE: ARRAY and USER-DEFINED columns were exported without their exact
-- element type. They are emitted as text[] / text and marked -- CHECK TYPE.
-- =====================================================================

create extension if not exists pgcrypto;
create extension if not exists "uuid-ossp";
create extension if not exists vector;



-- ============ action_attachments ============
create table if not exists public.action_attachments (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  plant_id uuid,
  entity_type text not null,
  entity_id uuid not null,
  file_metadata_id uuid not null,
  uploaded_by uuid not null,
  created_at timestamptz default now() not null
);
alter table public.action_attachments enable row level security;

-- ============ admin_action_logs ============
create table if not exists public.admin_action_logs (
  id bigint not null,
  admin_user_id uuid,
  action text not null,
  target_type text not null,
  target_id text,
  organization_id uuid,
  reason text,
  details jsonb default '{}'::jsonb not null,
  correlation_id uuid default gen_random_uuid() not null,
  created_at timestamptz default now() not null
);
alter table public.admin_action_logs enable row level security;

-- ============ ai_usage ============
create table if not exists public.ai_usage (
  id bigint not null,
  organization_id uuid not null,
  plant_id uuid,
  user_id uuid,
  provider text,
  mode text,
  input_tokens integer,
  output_tokens integer,
  estimated_cost numeric,
  created_at timestamptz default now(),
  request_id uuid,
  model text,
  status text default 'completed'::text,
  latency_ms integer,
  error_code text,
  source_count integer default 0
);
alter table public.ai_usage enable row level security;

-- ============ api_keys ============
create table if not exists public.api_keys (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  plant_id uuid,
  name text not null,
  key_hash text not null,
  key_prefix text not null,
  scopes text[] default '{read}'::text[] not null,   -- CHECK TYPE
  created_by uuid,
  created_at timestamptz default now() not null,
  last_used_at timestamptz,
  expires_at timestamptz,
  revoked_at timestamptz,
  removed_at timestamptz
);
alter table public.api_keys enable row level security;

-- ============ asset_status_history ============
create table if not exists public.asset_status_history (
  id bigint not null,
  organization_id uuid not null,
  plant_id uuid not null,
  asset_id uuid not null,
  old_state text,
  new_state text not null,
  changed_by uuid,
  changed_at timestamptz default now()
);
alter table public.asset_status_history enable row level security;

-- ============ assets ============
create table if not exists public.assets (
  id uuid not null,
  organization_id uuid not null,
  plant_id uuid not null,
  asset_code text not null,
  name text not null,
  asset_type text not null,
  location text,
  manufacturer text,
  model text,
  serial_number text,
  rating text,
  status text default 'operational'::text not null,
  running_state text default 'shutdown'::text not null,
  details jsonb default '{}'::jsonb not null,
  created_by uuid not null,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null,
  removed_at timestamptz,
  removed_by uuid,
  row_version bigint default 1 not null,
  parent_id uuid,
  meter_unit text,
  current_meter_value numeric default 0,
  pm_trigger_meter_value numeric
);
alter table public.assets enable row level security;

-- ============ attendance ============
create table if not exists public.attendance (
  id uuid not null,
  organization_id uuid not null,
  plant_id uuid not null,
  user_id uuid not null,
  work_date date not null,
  shift_name text,
  status text not null,
  check_in timestamptz,
  check_out timestamptz,
  notes text,
  created_by uuid,
  updated_at timestamptz default now()
);
alter table public.attendance enable row level security;

-- ============ audit_logs ============
create table if not exists public.audit_logs (
  id bigint not null,
  organization_id uuid not null,
  plant_id uuid,
  user_id uuid,
  action text not null,
  entity_type text not null,
  entity_id text,
  details jsonb default '{}'::jsonb not null,
  created_at timestamptz default now() not null
);
alter table public.audit_logs enable row level security;

-- ============ backup_jobs ============
create table if not exists public.backup_jobs (
  id uuid default gen_random_uuid() not null,
  job_type text not null,
  status text default 'requested'::text not null,
  provider text default 'supabase_managed'::text not null,
  requested_by uuid not null,
  started_at timestamptz,
  completed_at timestamptz,
  backup_reference text,
  size_bytes bigint,
  checksum text,
  error text,
  metadata jsonb default '{}'::jsonb not null,
  created_at timestamptz default now() not null
);
alter table public.backup_jobs enable row level security;

-- ============ billing_events ============
create table if not exists public.billing_events (
  id uuid default gen_random_uuid() not null,
  provider text not null,
  provider_event_id text not null,
  organization_id uuid,
  event_type text not null,
  status text default 'received'::text not null,
  payload_hash text,
  error text,
  received_at timestamptz default now() not null,
  processed_at timestamptz
);
alter table public.billing_events enable row level security;

-- ============ checklist_items ============
create table if not exists public.checklist_items (
  id uuid not null,
  template_id uuid not null,
  sort_order integer not null,
  label text not null,
  input_type text not null,
  unit text,
  required boolean default true,
  limits jsonb default '{}'::jsonb
);
alter table public.checklist_items enable row level security;

-- ============ checklist_runs ============
create table if not exists public.checklist_runs (
  id uuid not null,
  organization_id uuid not null,
  plant_id uuid not null,
  template_id uuid not null,
  asset_id uuid,
  performed_by uuid not null,
  shift_name text,
  status text not null,
  notes text,
  performed_at timestamptz default now(),
  designation text,
  completed_at timestamptz,
  supervisor_approved_by uuid,
  supervisor_approved_at timestamptz,
  signature_data text
);
alter table public.checklist_runs enable row level security;

-- ============ checklist_templates ============
create table if not exists public.checklist_templates (
  id uuid not null,
  organization_id uuid not null,
  plant_id uuid not null,
  asset_id uuid,
  name text not null,
  schedule text,
  shift_name text,
  instructions text,
  active boolean default true,
  created_by uuid,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  removed_at timestamptz,
  removed_by uuid,
  row_version bigint default 1 not null
);
alter table public.checklist_templates enable row level security;

-- ============ checklist_values ============
create table if not exists public.checklist_values (
  id uuid not null,
  run_id uuid not null,
  item_id uuid not null,
  value jsonb not null,
  failed boolean default false not null,
  note text
);
alter table public.checklist_values enable row level security;

-- ============ code_registry ============
create table if not exists public.code_registry (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  plant_id uuid,
  code_value text not null,
  code_format text default 'QR_CODE'::text not null,
  entity_type text not null,
  entity_id text not null,
  label text,
  active boolean default true not null,
  created_by uuid,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null
);
alter table public.code_registry enable row level security;

-- ============ company_feature_blocks ============
create table if not exists public.company_feature_blocks (
  organization_id uuid not null,
  feature text not null,
  blocked boolean default true not null,
  reason text not null,
  blocked_by uuid not null,
  expires_at timestamptz,
  updated_at timestamptz default now() not null
);
alter table public.company_feature_blocks enable row level security;

-- ============ complimentary_access ============
create table if not exists public.complimentary_access (
  organization_id uuid not null,
  access_type text default 'complimentary'::text not null,
  starts_at timestamptz default now() not null,
  ends_at timestamptz,
  reason text not null,
  never_auto_suspend boolean default true not null,
  granted_by uuid not null,
  revoked_at timestamptz,
  revoked_by uuid,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null
);
alter table public.complimentary_access enable row level security;

-- ============ condition_alarms ============
create table if not exists public.condition_alarms (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  plant_id uuid not null,
  asset_id uuid,
  recording_id uuid not null,
  alarm_type text not null,
  severity text not null,
  message text not null,
  metric text,
  measured_value numeric,
  limit_value numeric,
  acknowledged_by uuid,
  acknowledged_at timestamptz,
  created_at timestamptz default now() not null
);
alter table public.condition_alarms enable row level security;

-- ============ condition_entity_links ============
create table if not exists public.condition_entity_links (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  recording_id uuid not null,
  entity_type text not null,
  entity_id text not null,
  relation text default 'evidence'::text not null,
  linked_by uuid not null,
  created_at timestamptz default now() not null
);
alter table public.condition_entity_links enable row level security;

-- ============ condition_recordings ============
create table if not exists public.condition_recordings (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  plant_id uuid not null,
  asset_id uuid,
  measurement_point_id uuid,
  recording_type text not null,
  title text not null,
  operating_condition text,
  rpm numeric,
  load_percent numeric,
  temperature numeric,
  duration_seconds numeric,
  sample_rate numeric,
  device_info jsonb default '{}'::jsonb not null,
  calibration_status text default 'uncalibrated'::text not null,
  audio_path text,
  audio_mime_type text,
  audio_size_bytes bigint,
  waveform jsonb default '[]'::jsonb not null,
  spectrum jsonb default '[]'::jsonb not null,
  vibration_samples jsonb default '[]'::jsonb not null,
  metrics jsonb default '{}'::jsonb not null,
  ai_analysis jsonb default '{}'::jsonb not null,
  manual_sources jsonb default '[]'::jsonb not null,
  baseline_id uuid,
  comparison jsonb default '{}'::jsonb not null,
  is_baseline boolean default false not null,
  status text default 'completed'::text not null,
  condition_status text default 'unverified'::text not null,
  notes text,
  created_by uuid not null,
  worker_name text not null,
  designation text,
  shift_name text,
  approved_by uuid,
  approved_at timestamptz,
  removed_at timestamptz,
  removed_by uuid,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null
);
alter table public.condition_recordings enable row level security;

-- ============ daily_logs ============
create table if not exists public.daily_logs (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  plant_id uuid not null,
  log_date date default CURRENT_DATE not null,
  shift_name text not null,
  category text default 'operations'::text not null,
  entry text not null,
  created_by uuid not null,
  worker_name text not null,
  designation text,
  created_at timestamptz default now() not null
);
alter table public.daily_logs enable row level security;

-- ============ data_retention_policies ============
create table if not exists public.data_retention_policies (
  organization_id uuid not null,
  operational_days integer default 1095 not null,
  audit_days integer default 2190 not null,
  ai_prompt_days integer default 0 not null,
  soft_delete_grace_days integer default 30 not null,
  legal_hold boolean default false not null,
  updated_at timestamptz default now() not null,
  updated_by uuid
);
alter table public.data_retention_policies enable row level security;

-- ============ deletion_requests ============
create table if not exists public.deletion_requests (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  requested_by uuid not null,
  request_type text not null,
  target_user_id uuid,
  status text default 'requested'::text not null,
  reason text,
  scheduled_for timestamptz,
  completed_at timestamptz,
  created_at timestamptz default now() not null
);
alter table public.deletion_requests enable row level security;

-- ============ document_chunks ============
create table if not exists public.document_chunks (
  id bigint not null,
  manual_id uuid not null,
  page_number integer,
  content text not null,
  embedding vector(768),   -- pgvector; confirm dimension against your Gemini model
  created_at timestamptz default now()
);
alter table public.document_chunks enable row level security;

-- ============ file_metadata ============
create table if not exists public.file_metadata (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  plant_id uuid,
  asset_id uuid,
  bucket text default 'plant-files'::text not null,
  object_path text not null,
  file_name text not null,
  mime_type text,
  size_bytes bigint,
  category text,
  uploaded_by uuid not null,
  created_at timestamptz default now() not null,
  removed_at timestamptz,
  removed_by uuid
);
alter table public.file_metadata enable row level security;

-- ============ inventory_transactions ============
create table if not exists public.inventory_transactions (
  id uuid not null,
  spare_id uuid not null,
  quantity numeric not null,
  transaction_type text not null,
  reference text,
  performed_by uuid,
  created_at timestamptz default now()
);
alter table public.inventory_transactions enable row level security;

-- ============ invitations ============
create table if not exists public.invitations (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  plant_id uuid,
  email text,
  role text not null,
  token uuid default gen_random_uuid() not null,
  expires_at timestamptz default (now() + '7 days'::interval) not null,
  accepted_at timestamptz,
  created_by uuid,
  created_at timestamptz default now(),
  worker_details jsonb default '{}'::jsonb not null
);
alter table public.invitations enable row level security;

-- ============ legal_acceptances ============
create table if not exists public.legal_acceptances (
  id uuid default gen_random_uuid() not null,
  document_id uuid not null,
  organization_id uuid,
  user_id uuid not null,
  accepted_at timestamptz default now() not null,
  locale text,
  user_agent_hash text
);
alter table public.legal_acceptances enable row level security;

-- ============ legal_documents ============
create table if not exists public.legal_documents (
  id uuid default gen_random_uuid() not null,
  document_type text not null,
  version text not null,
  title text not null,
  content text not null,
  effective_at timestamptz not null,
  active boolean default true not null,
  created_at timestamptz default now() not null,
  required boolean default false not null,
  acceptance_scope text default 'all_users'::text not null,
  published_by uuid,
  published_at timestamptz
);
alter table public.legal_documents enable row level security;

-- ============ loto_procedures ============
create table if not exists public.loto_procedures (
  id uuid default gen_random_uuid() not null,
  plant_id uuid not null,
  asset_id uuid not null,
  work_order_id uuid,
  applied_by uuid not null,
  applied_at timestamptz default now() not null,
  removed_by uuid,
  removed_at timestamptz,
  notes text
);
alter table public.loto_procedures enable row level security;

-- ============ maintenance_completions ============
create table if not exists public.maintenance_completions (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  plant_id uuid not null,
  plan_id uuid not null,
  work_done text not null,
  worker_id uuid not null,
  worker_name text not null,
  designation text,
  shift_name text not null,
  tools_used text,
  parts_used text,
  measurements jsonb default '{}'::jsonb not null,
  root_cause text,
  corrective_action text,
  downtime_minutes integer,
  signature_data text,
  completed_at timestamptz default now() not null,
  supervisor_approved_by uuid,
  supervisor_approved_at timestamptz
);
alter table public.maintenance_completions enable row level security;

-- ============ maintenance_plans ============
create table if not exists public.maintenance_plans (
  id uuid not null,
  organization_id uuid not null,
  plant_id uuid not null,
  asset_id uuid,
  title text not null,
  frequency text not null,
  priority text default 'medium'::text,
  description text not null,
  assigned_to uuid,
  next_due date,
  status text default 'pending'::text,
  created_by uuid,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  removed_at timestamptz,
  removed_by uuid,
  last_completed_at timestamptz,
  last_completed_by uuid,
  row_version bigint default 1 not null
);
alter table public.maintenance_plans enable row level security;

-- ============ manuals ============
create table if not exists public.manuals (
  id uuid not null,
  organization_id uuid not null,
  plant_id uuid,
  asset_id uuid,
  title text not null,
  manufacturer text,
  model text,
  storage_path text not null,
  mime_type text,
  size_bytes bigint,
  status text default 'uploaded'::text,
  uploaded_by uuid,
  created_at timestamptz default now()
);
alter table public.manuals enable row level security;

-- ============ material_requests ============
create table if not exists public.material_requests (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  plant_id uuid not null,
  spare_id uuid not null,
  requested_by uuid not null,
  quantity integer default 1 not null,
  urgency text default 'normal'::text not null,
  notes text,
  status text default 'pending'::text not null,
  managed_by uuid,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null,
  purchase_order_id uuid
);
alter table public.material_requests enable row level security;

-- ============ measurement_points ============
create table if not exists public.measurement_points (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  plant_id uuid not null,
  asset_id uuid,
  name text not null,
  direction text,
  description text,
  reference_photo_path text,
  active boolean default true not null,
  created_by uuid,
  created_at timestamptz default now() not null
);
alter table public.measurement_points enable row level security;

-- ============ notifications ============
create table if not exists public.notifications (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  plant_id uuid,
  user_id uuid,
  title text not null,
  body text,
  read_at timestamptz,
  created_at timestamptz default now(),
  severity text default 'normal'::text
);
alter table public.notifications enable row level security;

-- ============ organization_entitlements ============
create table if not exists public.organization_entitlements (
  organization_id uuid not null,
  entitlement text not null,
  enabled boolean not null,
  numeric_limit bigint,
  expires_at timestamptz,
  reason text,
  updated_at timestamptz default now() not null,
  updated_by uuid
);
alter table public.organization_entitlements enable row level security;

-- ============ organization_members ============
create table if not exists public.organization_members (
  organization_id uuid not null,
  user_id uuid not null,
  role text not null,
  active boolean default true not null,
  created_at timestamptz default now() not null,
  permissions jsonb default '{}'::jsonb not null,
  deactivated_at timestamptz,
  updated_at timestamptz default now() not null
);
alter table public.organization_members enable row level security;

-- ============ organization_settings ============
create table if not exists public.organization_settings (
  organization_id uuid not null,
  app_name text default 'PlantMaster Pro'::text,
  plant_display_name text,
  logo_path text,
  primary_color text default '#3b82f6'::text,
  secondary_color text default '#06b6d4'::text,
  theme text default 'industrial'::text,
  pattern text default 'grid'::text,
  address text,
  contact text,
  email text,
  report_time time without time zone default '11:00:00'::time without time zone,
  footer_text text,
  updated_at timestamptz default now(),
  report_recipients text[] default '{}'::text[] not null,   -- CHECK TYPE
  report_approval_required boolean default true not null,
  letterhead_path text,
  signatories jsonb default '[]'::jsonb not null
);
alter table public.organization_settings enable row level security;

-- ============ organization_subscriptions ============
create table if not exists public.organization_subscriptions (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  plan_id uuid not null,
  status text default 'trial'::text not null,
  provider text,
  provider_customer_id text,
  provider_subscription_id text,
  current_period_start timestamptz default now() not null,
  current_period_end timestamptz,
  trial_ends_at timestamptz,
  cancel_at_period_end boolean default false not null,
  grace_ends_at timestamptz,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null
);
alter table public.organization_subscriptions enable row level security;

-- ============ organizations ============
create table if not exists public.organizations (
  id uuid default gen_random_uuid() not null,
  name text not null,
  slug text,
  logo_path text,
  created_by uuid not null,
  created_at timestamptz default now() not null,
  commercial_status text default 'active'::text not null,
  status_reason text,
  trial_ends_at timestamptz,
  suspended_at timestamptz,
  deletion_scheduled_at timestamptz,
  commercial_updated_at timestamptz default now() not null
);
alter table public.organizations enable row level security;

-- ============ permits ============
create table if not exists public.permits (
  id uuid default gen_random_uuid() not null,
  plant_id uuid not null,
  work_order_id uuid not null,
  permit_type text not null,
  status text default 'pending'::text not null,
  requested_by uuid not null,
  approved_by uuid,
  approved_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz default now() not null
);
alter table public.permits enable row level security;

-- ============ plant_members ============
create table if not exists public.plant_members (
  plant_id uuid not null,
  user_id uuid not null,
  created_at timestamptz default now() not null
);
alter table public.plant_members enable row level security;

-- ============ plantmaster_sync ============
create table if not exists public.plantmaster_sync (
  site_id text not null,
  data jsonb default '{}'::jsonb not null,
  updated_at timestamptz default now() not null
);
alter table public.plantmaster_sync enable row level security;

-- ============ plants ============
create table if not exists public.plants (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  name text not null,
  location text,
  created_at timestamptz default now() not null
);
alter table public.plants enable row level security;

-- ============ platform_admins ============
create table if not exists public.platform_admins (
  user_id uuid not null,
  active boolean default true not null,
  created_at timestamptz default now() not null,
  created_by uuid,
  admin_role text default 'super_admin'::text not null,
  permissions jsonb default '{}'::jsonb not null,
  display_name text,
  last_login_at timestamptz,
  updated_at timestamptz default now() not null
);
alter table public.platform_admins enable row level security;

-- ============ platform_notifications ============
create table if not exists public.platform_notifications (
  id uuid default gen_random_uuid() not null,
  severity text not null,
  title text not null,
  body text,
  component text,
  organization_id uuid,
  read_at timestamptz,
  created_at timestamptz default now() not null
);
alter table public.platform_notifications enable row level security;

-- ============ platform_support_messages ============
create table if not exists public.platform_support_messages (
  id uuid default gen_random_uuid() not null,
  ticket_id uuid not null,
  user_id uuid not null,
  message text not null,
  internal boolean default false not null,
  attachment_path text,
  created_at timestamptz default now() not null
);
alter table public.platform_support_messages enable row level security;

-- ============ platform_support_tickets ============
create table if not exists public.platform_support_tickets (
  id uuid default gen_random_uuid() not null,
  ticket_number bigint default nextval('platform_ticket_number_seq'::regclass) not null,
  organization_id uuid,
  opened_by uuid not null,
  owner_email text,
  category text not null,
  priority text default 'medium'::text not null,
  status text default 'new'::text not null,
  subject text not null,
  description text not null,
  app_version text,
  device_info jsonb default '{}'::jsonb not null,
  assigned_to uuid,
  related_incident_id uuid,
  resolution text,
  resolved_at timestamptz,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null
);
alter table public.platform_support_tickets enable row level security;

-- ============ problem_cases ============
create table if not exists public.problem_cases (
  id uuid not null,
  organization_id uuid not null,
  plant_id uuid not null,
  asset_id uuid,
  title text not null,
  symptoms text not null,
  alarm_code text,
  readings jsonb default '{}'::jsonb,
  mode text default 'offline'::text,
  ai_answer jsonb,
  actual_cause text,
  verified_solution text,
  status text default 'open'::text,
  created_by uuid,
  created_at timestamptz default now(),
  resolved_at timestamptz
);
alter table public.problem_cases enable row level security;

-- ============ profiles ============
create table if not exists public.profiles (
  id uuid not null,
  full_name text default ''::text not null,
  avatar_path text,
  created_at timestamptz default now() not null,
  employee_id text,
  designation text,
  skills text[] default '{}'::text[] not null,   -- CHECK TYPE
  contact text,
  default_shift text default 'General Shift'::text,
  updated_at timestamptz default now() not null,
  labor_rate_hourly numeric default 0.00
);
alter table public.profiles enable row level security;

-- ============ purchase_order_lines ============
create table if not exists public.purchase_order_lines (
  id uuid default gen_random_uuid() not null,
  purchase_order_id uuid not null,
  spare_id uuid,
  description text not null,
  quantity numeric not null,
  unit text default 'pcs'::text,
  unit_price numeric default 0 not null,
  line_total numeric default 0 not null,
  received_qty numeric default 0 not null,
  created_at timestamptz default now() not null
);
alter table public.purchase_order_lines enable row level security;

-- ============ purchase_orders ============
create table if not exists public.purchase_orders (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  plant_id uuid not null,
  po_number text not null,
  supplier_id uuid,
  status text default 'draft'::text not null,
  currency text default 'PKR'::text not null,
  subtotal numeric default 0 not null,
  tax_percent numeric default 0 not null,
  tax_amount numeric default 0 not null,
  total numeric default 0 not null,
  expected_date date,
  received_date date,
  notes text,
  requested_by uuid,
  approved_by uuid,
  approved_at timestamptz,
  removed_at timestamptz,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null
);
alter table public.purchase_orders enable row level security;

-- ============ push_cursors ============
create table if not exists public.push_cursors (
  organization_id uuid not null,
  last_created_at timestamptz default '1970-01-01 00:00:00+00'::timestamp with time zone not null,
  updated_at timestamptz default now() not null
);
alter table public.push_cursors enable row level security;

-- ============ push_subscriptions ============
create table if not exists public.push_subscriptions (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  user_id uuid not null,
  endpoint text not null,
  p256dh text not null,
  auth text not null,
  ua text,
  last_error_at timestamptz,
  created_at timestamptz default now() not null
);
alter table public.push_subscriptions enable row level security;

-- ============ qa_environments ============
create table if not exists public.qa_environments (
  id uuid default gen_random_uuid() not null,
  name text not null,
  organization_id uuid,
  plant_id uuid,
  isolation_organization_id uuid,
  status text default 'creating'::text not null,
  user_ids jsonb default '{}'::jsonb not null,
  seed_summary jsonb default '{}'::jsonb not null,
  last_error text,
  created_by uuid not null,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null,
  deleted_at timestamptz
);
alter table public.qa_environments enable row level security;

-- ============ qa_manual_checks ============
create table if not exists public.qa_manual_checks (
  id uuid default gen_random_uuid() not null,
  run_id uuid not null,
  category text not null,
  check_name text not null,
  instructions text not null,
  status text default 'pending'::text not null,
  result_notes text,
  tested_by uuid,
  tested_at timestamptz
);
alter table public.qa_manual_checks enable row level security;

-- ============ qa_test_results ============
create table if not exists public.qa_test_results (
  id bigint not null,
  run_id uuid not null,
  category text not null,
  test_name text not null,
  status text not null,
  expected text,
  actual text,
  error text,
  duration_ms integer,
  evidence jsonb default '{}'::jsonb not null,
  created_at timestamptz default now() not null
);
alter table public.qa_test_results enable row level security;

-- ============ qa_test_runs ============
create table if not exists public.qa_test_runs (
  id uuid default gen_random_uuid() not null,
  environment_id uuid not null,
  status text default 'running'::text not null,
  include_ai boolean default false not null,
  total_tests integer default 0 not null,
  passed integer default 0 not null,
  failed integer default 0 not null,
  blocked integer default 0 not null,
  app_version text,
  runner_version text default '1.0.0'::text not null,
  started_by uuid not null,
  started_at timestamptz default now() not null,
  completed_at timestamptz,
  summary jsonb default '{}'::jsonb not null
);
alter table public.qa_test_runs enable row level security;

-- ============ quota_overrides ============
create table if not exists public.quota_overrides (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  metric text not null,
  override_type text not null,
  value bigint,
  starts_at timestamptz default now() not null,
  ends_at timestamptz,
  reason text not null,
  active boolean default true not null,
  created_by uuid not null,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null
);
alter table public.quota_overrides enable row level security;

-- ============ report_dispatches ============
create table if not exists public.report_dispatches (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  plant_id uuid,
  report_date date not null,
  recipient text not null,
  summary text,
  status text default 'pending'::text,
  approved_by uuid,
  sent_at timestamptz,
  created_at timestamptz default now()
);
alter table public.report_dispatches enable row level security;

-- ============ restore_drills ============
create table if not exists public.restore_drills (
  id uuid default gen_random_uuid() not null,
  backup_job_id uuid,
  status text default 'planned'::text not null,
  environment text default 'non_production'::text not null,
  rpo_minutes integer,
  rto_minutes integer,
  database_verified boolean,
  storage_verified boolean,
  notes text,
  performed_by uuid,
  scheduled_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz default now() not null
);
alter table public.restore_drills enable row level security;

-- ============ scan_entity_links ============
create table if not exists public.scan_entity_links (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  scan_session_id uuid not null,
  entity_type text not null,
  entity_id text not null,
  relation text default 'attachment'::text not null,
  linked_by uuid not null,
  created_at timestamptz default now() not null
);
alter table public.scan_entity_links enable row level security;

-- ============ scan_pages ============
create table if not exists public.scan_pages (
  id uuid default gen_random_uuid() not null,
  session_id uuid not null,
  page_number integer not null,
  storage_path text,
  enhanced_path text,
  mime_type text,
  size_bytes bigint,
  width integer,
  height integer,
  rotation integer default 0 not null,
  enhancement text default 'original'::text,
  extracted_text text,
  structured_result jsonb default '{}'::jsonb not null,
  created_at timestamptz default now() not null
);
alter table public.scan_pages enable row level security;

-- ============ scan_sessions ============
create table if not exists public.scan_sessions (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  plant_id uuid,
  mode text not null,
  source_type text default 'camera'::text not null,
  status text default 'draft'::text not null,
  title text,
  original_path text,
  enhanced_path text,
  thumbnail_path text,
  mime_type text,
  file_name text,
  file_size bigint,
  detected_codes jsonb default '[]'::jsonb not null,
  extracted_text text,
  structured_result jsonb default '{}'::jsonb not null,
  confidence text,
  safety_notes text,
  linked_entity_type text,
  linked_entity_id text,
  created_by uuid not null,
  worker_name text not null,
  designation text,
  shift_name text,
  approved_by uuid,
  approved_at timestamptz,
  removed_at timestamptz,
  removed_by uuid,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null
);
alter table public.scan_sessions enable row level security;

-- ============ sensor_devices ============
create table if not exists public.sensor_devices (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  plant_id uuid,
  name text not null,
  sensor_type text not null,
  manufacturer text,
  model text,
  serial_number text,
  calibration_date date,
  calibration_due date,
  protocol_details jsonb default '{}'::jsonb not null,
  active boolean default true not null,
  created_at timestamptz default now() not null
);
alter table public.sensor_devices enable row level security;

-- ============ shift_assignments ============
create table if not exists public.shift_assignments (
  id uuid not null,
  organization_id uuid not null,
  plant_id uuid not null,
  user_id uuid not null,
  shift_name text not null,
  work_date date not null,
  status text default 'scheduled'::text,
  created_by uuid,
  created_at timestamptz default now()
);
alter table public.shift_assignments enable row level security;

-- ============ shift_handovers ============
create table if not exists public.shift_handovers (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  plant_id uuid not null,
  work_date date default CURRENT_DATE not null,
  from_shift text not null,
  to_shift text not null,
  summary text not null,
  pending_work text,
  safety_notes text,
  created_by uuid not null,
  worker_name text not null,
  designation text,
  created_at timestamptz default now() not null
);
alter table public.shift_handovers enable row level security;

-- ============ spares ============
create table if not exists public.spares (
  id uuid not null,
  organization_id uuid not null,
  plant_id uuid not null,
  part_number text,
  description text not null,
  asset_id uuid,
  stock numeric default 0,
  min_stock numeric default 0,
  unit text,
  unit_cost numeric,
  bin_location text,
  supplier text,
  updated_at timestamptz default now(),
  removed_at timestamptz,
  removed_by uuid,
  row_version bigint default 1 not null
);
alter table public.spares enable row level security;

-- ============ storage_reservations ============
create table if not exists public.storage_reservations (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  user_id uuid not null,
  bytes bigint not null,
  file_name text,
  mime_type text,
  status text default 'reserved'::text not null,
  expires_at timestamptz default (now() + '00:15:00'::interval) not null,
  created_at timestamptz default now() not null
);
alter table public.storage_reservations enable row level security;

-- ============ storage_usage_events ============
create table if not exists public.storage_usage_events (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  user_id uuid,
  event_type text not null,
  object_path text,
  bytes bigint default 0 not null,
  file_metadata_id uuid,
  created_at timestamptz default now() not null
);
alter table public.storage_usage_events enable row level security;

-- ============ subscription_plans ============
create table if not exists public.subscription_plans (
  id uuid default gen_random_uuid() not null,
  code text not null,
  name text not null,
  description text,
  active boolean default true not null,
  currency text default 'USD'::text not null,
  price_monthly numeric default 0 not null,
  price_yearly numeric default 0 not null,
  max_workers integer default 5 not null,
  max_plants integer default 1 not null,
  max_storage_bytes bigint default 524288000 not null,
  max_bandwidth_bytes_month bigint default '2147483648'::bigint not null,
  max_files integer default 500 not null,
  max_file_bytes bigint default 52428800 not null,
  ai_requests_month integer default 50 not null,
  ai_requests_day integer default 10 not null,
  ai_requests_minute_user integer default 3 not null,
  ai_input_tokens_month bigint default 250000 not null,
  ai_output_tokens_month bigint default 100000 not null,
  retention_days integer default 365 not null,
  features jsonb default '{}'::jsonb not null,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null
);
alter table public.subscription_plans enable row level security;

-- ============ suppliers ============
create table if not exists public.suppliers (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  plant_id uuid,
  name text not null,
  contact_person text,
  phone text,
  email text,
  address text,
  ntn text,
  strn text,
  payment_terms text default 'Net 30'::text,
  currency text default 'PKR'::text not null,
  rating numeric,
  notes text,
  active boolean default true not null,
  removed_at timestamptz,
  created_by uuid,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null
);
alter table public.suppliers enable row level security;

-- ============ support_messages ============
create table if not exists public.support_messages (
  id uuid not null,
  thread_id uuid not null,
  user_id uuid not null,
  message text not null,
  created_at timestamptz default now()
);
alter table public.support_messages enable row level security;

-- ============ support_threads ============
create table if not exists public.support_threads (
  id uuid not null,
  organization_id uuid not null,
  plant_id uuid not null,
  asset_id uuid,
  subject text not null,
  priority text default 'medium'::text,
  status text default 'open'::text,
  created_by uuid not null,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
alter table public.support_threads enable row level security;

-- ============ system_incidents ============
create table if not exists public.system_incidents (
  id uuid default gen_random_uuid() not null,
  organization_id uuid,
  severity text not null,
  component text not null,
  event_type text not null,
  message text not null,
  correlation_id text,
  details jsonb default '{}'::jsonb not null,
  status text default 'open'::text not null,
  first_seen_at timestamptz default now() not null,
  last_seen_at timestamptz default now() not null,
  resolved_at timestamptz
);
alter table public.system_incidents enable row level security;

-- ============ technical_experiences ============
create table if not exists public.technical_experiences (
  id uuid not null,
  organization_id uuid not null,
  plant_id uuid not null,
  asset_id uuid,
  problem text not null,
  symptoms text,
  tests text,
  root_cause text not null,
  solution text not null,
  tools text,
  parts text,
  downtime text,
  approved boolean default false,
  created_by uuid,
  created_at timestamptz default now()
);
alter table public.technical_experiences enable row level security;

-- ============ tool_transactions ============
create table if not exists public.tool_transactions (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  plant_id uuid not null,
  tool_id uuid not null,
  transaction_type text not null,
  holder_id uuid,
  condition text,
  notes text,
  performed_by uuid not null,
  worker_name text not null,
  designation text,
  shift_name text,
  created_at timestamptz default now() not null
);
alter table public.tool_transactions enable row level security;

-- ============ tools ============
create table if not exists public.tools (
  id uuid not null,
  organization_id uuid not null,
  plant_id uuid not null,
  tool_code text,
  name text not null,
  specification text,
  condition text,
  calibration_due date,
  status text default 'available'::text,
  holder_id uuid,
  updated_at timestamptz default now(),
  removed_at timestamptz,
  removed_by uuid,
  row_version bigint default 1 not null
);
alter table public.tools enable row level security;

-- ============ usage_adjustments ============
create table if not exists public.usage_adjustments (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  metric text not null,
  period_start date not null,
  quantity bigint not null,
  reason text not null,
  created_by uuid not null,
  created_at timestamptz default now() not null
);
alter table public.usage_adjustments enable row level security;

-- ============ usage_counters ============
create table if not exists public.usage_counters (
  organization_id uuid not null,
  metric text not null,
  period_start date not null,
  period_end date not null,
  quantity bigint default 0 not null,
  updated_at timestamptz default now() not null
);
alter table public.usage_counters enable row level security;

-- ============ usage_events ============
create table if not exists public.usage_events (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  user_id uuid,
  metric text not null,
  quantity bigint default 1 not null,
  source text,
  reference_id text,
  status text default 'recorded'::text not null,
  metadata jsonb default '{}'::jsonb not null,
  created_at timestamptz default now() not null
);
alter table public.usage_events enable row level security;

-- ============ work_orders ============
create table if not exists public.work_orders (
  id uuid not null,
  organization_id uuid not null,
  plant_id uuid not null,
  asset_id uuid,
  title text not null,
  description text not null,
  priority text default 'medium'::text not null,
  status text default 'open'::text not null,
  assigned_to uuid,
  due_at timestamptz,
  created_by uuid not null,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null,
  removed_at timestamptz,
  removed_by uuid,
  work_done text,
  designation text,
  shift_name text,
  tools_used text,
  parts_used text,
  measurements jsonb default '{}'::jsonb not null,
  root_cause text,
  corrective_action text,
  downtime_minutes integer,
  completed_by uuid,
  completed_at timestamptz,
  supervisor_approved_by uuid,
  supervisor_approved_at timestamptz,
  signature_data text,
  row_version bigint default 1 not null,
  started_at timestamptz,
  labor_minutes integer default 0,
  total_cost numeric default 0.00
);
alter table public.work_orders enable row level security;


-- =====================================================================
-- CONSTRAINTS
-- =====================================================================
alter table public.action_attachments add constraint action_attachments_file_metadata_id_fkey FOREIGN KEY (file_metadata_id) REFERENCES file_metadata(id) ON DELETE CASCADE;
alter table public.action_attachments add constraint action_attachments_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.action_attachments add constraint action_attachments_pkey PRIMARY KEY (id);
alter table public.action_attachments add constraint action_attachments_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.action_attachments add constraint action_attachments_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES auth.users(id);
alter table public.admin_action_logs add constraint admin_action_logs_admin_user_id_fkey FOREIGN KEY (admin_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public.admin_action_logs add constraint admin_action_logs_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE SET NULL;
alter table public.admin_action_logs add constraint admin_action_logs_pkey PRIMARY KEY (id);
alter table public.ai_usage add constraint ai_usage_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id);
alter table public.ai_usage add constraint ai_usage_pkey PRIMARY KEY (id);
alter table public.ai_usage add constraint ai_usage_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id);
alter table public.ai_usage add constraint ai_usage_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);
alter table public.api_keys add constraint api_keys_key_hash_key UNIQUE (key_hash);
alter table public.api_keys add constraint api_keys_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.api_keys add constraint api_keys_pkey PRIMARY KEY (id);
alter table public.api_keys add constraint api_keys_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.asset_status_history add constraint asset_status_history_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE;
alter table public.asset_status_history add constraint asset_status_history_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES auth.users(id);
alter table public.asset_status_history add constraint asset_status_history_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.asset_status_history add constraint asset_status_history_pkey PRIMARY KEY (id);
alter table public.asset_status_history add constraint asset_status_history_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.assets add constraint assets_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.assets add constraint assets_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.assets add constraint assets_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES assets(id) ON DELETE SET NULL;
alter table public.assets add constraint assets_pkey PRIMARY KEY (id);
alter table public.assets add constraint assets_plant_id_asset_code_key UNIQUE (plant_id, asset_code);
alter table public.assets add constraint assets_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.assets add constraint assets_removed_by_fkey FOREIGN KEY (removed_by) REFERENCES auth.users(id);
alter table public.attendance add constraint attendance_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.attendance add constraint attendance_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.attendance add constraint attendance_pkey PRIMARY KEY (id);
alter table public.attendance add constraint attendance_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.attendance add constraint attendance_plant_id_user_id_work_date_key UNIQUE (plant_id, user_id, work_date);
alter table public.attendance add constraint attendance_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);
alter table public.audit_logs add constraint audit_logs_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.audit_logs add constraint audit_logs_pkey PRIMARY KEY (id);
alter table public.audit_logs add constraint audit_logs_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.audit_logs add constraint audit_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public.backup_jobs add constraint backup_jobs_job_type_check CHECK ((job_type = ANY (ARRAY['managed_snapshot'::text, 'pitr_checkpoint'::text, 'storage_inventory'::text, 'logical_export'::text])));
alter table public.backup_jobs add constraint backup_jobs_pkey PRIMARY KEY (id);
alter table public.backup_jobs add constraint backup_jobs_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES auth.users(id);
alter table public.backup_jobs add constraint backup_jobs_status_check CHECK ((status = ANY (ARRAY['requested'::text, 'running'::text, 'completed'::text, 'failed'::text, 'cancelled'::text])));
alter table public.billing_events add constraint billing_events_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE SET NULL;
alter table public.billing_events add constraint billing_events_pkey PRIMARY KEY (id);
alter table public.billing_events add constraint billing_events_provider_event_id_key UNIQUE (provider_event_id);
alter table public.checklist_items add constraint checklist_items_pkey PRIMARY KEY (id);
alter table public.checklist_items add constraint checklist_items_template_id_fkey FOREIGN KEY (template_id) REFERENCES checklist_templates(id) ON DELETE CASCADE;
alter table public.checklist_runs add constraint checklist_runs_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES assets(id);
alter table public.checklist_runs add constraint checklist_runs_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.checklist_runs add constraint checklist_runs_performed_by_fkey FOREIGN KEY (performed_by) REFERENCES auth.users(id);
alter table public.checklist_runs add constraint checklist_runs_pkey PRIMARY KEY (id);
alter table public.checklist_runs add constraint checklist_runs_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.checklist_runs add constraint checklist_runs_supervisor_approved_by_fkey FOREIGN KEY (supervisor_approved_by) REFERENCES auth.users(id);
alter table public.checklist_runs add constraint checklist_runs_template_id_fkey FOREIGN KEY (template_id) REFERENCES checklist_templates(id);
alter table public.checklist_templates add constraint checklist_templates_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE;
alter table public.checklist_templates add constraint checklist_templates_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.checklist_templates add constraint checklist_templates_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.checklist_templates add constraint checklist_templates_pkey PRIMARY KEY (id);
alter table public.checklist_templates add constraint checklist_templates_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.checklist_templates add constraint checklist_templates_removed_by_fkey FOREIGN KEY (removed_by) REFERENCES auth.users(id);
alter table public.checklist_values add constraint checklist_values_item_id_fkey FOREIGN KEY (item_id) REFERENCES checklist_items(id);
alter table public.checklist_values add constraint checklist_values_pkey PRIMARY KEY (id);
alter table public.checklist_values add constraint checklist_values_run_id_fkey FOREIGN KEY (run_id) REFERENCES checklist_runs(id) ON DELETE CASCADE;
alter table public.code_registry add constraint code_registry_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.code_registry add constraint code_registry_organization_id_code_value_key UNIQUE (organization_id, code_value);
alter table public.code_registry add constraint code_registry_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.code_registry add constraint code_registry_pkey PRIMARY KEY (id);
alter table public.code_registry add constraint code_registry_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.company_feature_blocks add constraint company_feature_blocks_blocked_by_fkey FOREIGN KEY (blocked_by) REFERENCES auth.users(id);
alter table public.company_feature_blocks add constraint company_feature_blocks_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.company_feature_blocks add constraint company_feature_blocks_pkey PRIMARY KEY (organization_id, feature);
alter table public.complimentary_access add constraint complimentary_access_access_type_check CHECK ((access_type = ANY (ARRAY['complimentary'::text, 'internal'::text, 'manual'::text])));
alter table public.complimentary_access add constraint complimentary_access_granted_by_fkey FOREIGN KEY (granted_by) REFERENCES auth.users(id);
alter table public.complimentary_access add constraint complimentary_access_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.complimentary_access add constraint complimentary_access_pkey PRIMARY KEY (organization_id);
alter table public.complimentary_access add constraint complimentary_access_revoked_by_fkey FOREIGN KEY (revoked_by) REFERENCES auth.users(id);
alter table public.condition_alarms add constraint condition_alarms_acknowledged_by_fkey FOREIGN KEY (acknowledged_by) REFERENCES auth.users(id);
alter table public.condition_alarms add constraint condition_alarms_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE;
alter table public.condition_alarms add constraint condition_alarms_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.condition_alarms add constraint condition_alarms_pkey PRIMARY KEY (id);
alter table public.condition_alarms add constraint condition_alarms_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.condition_alarms add constraint condition_alarms_recording_id_fkey FOREIGN KEY (recording_id) REFERENCES condition_recordings(id) ON DELETE CASCADE;
alter table public.condition_alarms add constraint condition_alarms_severity_check CHECK ((severity = ANY (ARRAY['info'::text, 'warning'::text, 'alarm'::text, 'critical'::text])));
alter table public.condition_entity_links add constraint condition_entity_links_linked_by_fkey FOREIGN KEY (linked_by) REFERENCES auth.users(id);
alter table public.condition_entity_links add constraint condition_entity_links_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.condition_entity_links add constraint condition_entity_links_pkey PRIMARY KEY (id);
alter table public.condition_entity_links add constraint condition_entity_links_recording_id_entity_type_entity_id_r_key UNIQUE (recording_id, entity_type, entity_id, relation);
alter table public.condition_entity_links add constraint condition_entity_links_recording_id_fkey FOREIGN KEY (recording_id) REFERENCES condition_recordings(id) ON DELETE CASCADE;
alter table public.condition_recordings add constraint condition_recordings_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES auth.users(id);
alter table public.condition_recordings add constraint condition_recordings_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE SET NULL;
alter table public.condition_recordings add constraint condition_recordings_baseline_id_fkey FOREIGN KEY (baseline_id) REFERENCES condition_recordings(id) ON DELETE SET NULL;
alter table public.condition_recordings add constraint condition_recordings_calibration_status_check CHECK ((calibration_status = ANY (ARRAY['uncalibrated'::text, 'relative'::text, 'calibrated'::text])));
alter table public.condition_recordings add constraint condition_recordings_condition_status_check CHECK ((condition_status = ANY (ARRAY['normal'::text, 'changed'::text, 'warning'::text, 'alarm'::text, 'unverified'::text])));
alter table public.condition_recordings add constraint condition_recordings_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.condition_recordings add constraint condition_recordings_measurement_point_id_fkey FOREIGN KEY (measurement_point_id) REFERENCES measurement_points(id) ON DELETE SET NULL;
alter table public.condition_recordings add constraint condition_recordings_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.condition_recordings add constraint condition_recordings_pkey PRIMARY KEY (id);
alter table public.condition_recordings add constraint condition_recordings_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.condition_recordings add constraint condition_recordings_recording_type_check CHECK ((recording_type = ANY (ARRAY['voice_note'::text, 'machine_sound'::text, 'phone_vibration'::text, 'external_vibration'::text])));
alter table public.condition_recordings add constraint condition_recordings_removed_by_fkey FOREIGN KEY (removed_by) REFERENCES auth.users(id);
alter table public.condition_recordings add constraint condition_recordings_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'recording'::text, 'processing'::text, 'completed'::text, 'submitted'::text, 'approved'::text, 'failed'::text])));
alter table public.daily_logs add constraint daily_logs_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.daily_logs add constraint daily_logs_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.daily_logs add constraint daily_logs_pkey PRIMARY KEY (id);
alter table public.daily_logs add constraint daily_logs_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.data_retention_policies add constraint data_retention_policies_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.data_retention_policies add constraint data_retention_policies_pkey PRIMARY KEY (organization_id);
alter table public.data_retention_policies add constraint data_retention_policies_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id);
alter table public.deletion_requests add constraint deletion_requests_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.deletion_requests add constraint deletion_requests_pkey PRIMARY KEY (id);
alter table public.deletion_requests add constraint deletion_requests_request_type_check CHECK ((request_type = ANY (ARRAY['user'::text, 'organization'::text, 'export_and_delete'::text])));
alter table public.deletion_requests add constraint deletion_requests_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES auth.users(id);
alter table public.deletion_requests add constraint deletion_requests_status_check CHECK ((status = ANY (ARRAY['requested'::text, 'verified'::text, 'scheduled'::text, 'cancelled'::text, 'completed'::text, 'failed'::text])));
alter table public.deletion_requests add constraint deletion_requests_target_user_id_fkey FOREIGN KEY (target_user_id) REFERENCES auth.users(id);
alter table public.document_chunks add constraint document_chunks_manual_id_fkey FOREIGN KEY (manual_id) REFERENCES manuals(id) ON DELETE CASCADE;
alter table public.document_chunks add constraint document_chunks_pkey PRIMARY KEY (id);
alter table public.file_metadata add constraint file_metadata_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE SET NULL;
alter table public.file_metadata add constraint file_metadata_object_path_key UNIQUE (object_path);
alter table public.file_metadata add constraint file_metadata_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.file_metadata add constraint file_metadata_pkey PRIMARY KEY (id);
alter table public.file_metadata add constraint file_metadata_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.file_metadata add constraint file_metadata_removed_by_fkey FOREIGN KEY (removed_by) REFERENCES auth.users(id);
alter table public.file_metadata add constraint file_metadata_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES auth.users(id);
alter table public.inventory_transactions add constraint inventory_transactions_performed_by_fkey FOREIGN KEY (performed_by) REFERENCES auth.users(id);
alter table public.inventory_transactions add constraint inventory_transactions_pkey PRIMARY KEY (id);
alter table public.inventory_transactions add constraint inventory_transactions_spare_id_fkey FOREIGN KEY (spare_id) REFERENCES spares(id);
alter table public.invitations add constraint invitations_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.invitations add constraint invitations_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.invitations add constraint invitations_pkey PRIMARY KEY (id);
alter table public.invitations add constraint invitations_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.legal_acceptances add constraint legal_acceptances_document_id_fkey FOREIGN KEY (document_id) REFERENCES legal_documents(id);
alter table public.legal_acceptances add constraint legal_acceptances_document_id_user_id_key UNIQUE (document_id, user_id);
alter table public.legal_acceptances add constraint legal_acceptances_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.legal_acceptances add constraint legal_acceptances_pkey PRIMARY KEY (id);
alter table public.legal_acceptances add constraint legal_acceptances_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.legal_documents add constraint legal_acceptance_scope_check CHECK ((acceptance_scope = ANY (ARRAY['all_users'::text, 'owners'::text, 'platform_admins'::text])));
alter table public.legal_documents add constraint legal_documents_document_type_version_key UNIQUE (document_type, version);
alter table public.legal_documents add constraint legal_documents_pkey PRIMARY KEY (id);
alter table public.legal_documents add constraint legal_documents_published_by_fkey FOREIGN KEY (published_by) REFERENCES auth.users(id);
alter table public.loto_procedures add constraint loto_procedures_applied_by_fkey FOREIGN KEY (applied_by) REFERENCES auth.users(id);
alter table public.loto_procedures add constraint loto_procedures_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE;
alter table public.loto_procedures add constraint loto_procedures_pkey PRIMARY KEY (id);
alter table public.loto_procedures add constraint loto_procedures_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.loto_procedures add constraint loto_procedures_removed_by_fkey FOREIGN KEY (removed_by) REFERENCES auth.users(id);
alter table public.loto_procedures add constraint loto_procedures_work_order_id_fkey FOREIGN KEY (work_order_id) REFERENCES work_orders(id) ON DELETE CASCADE;
alter table public.maintenance_completions add constraint maintenance_completions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.maintenance_completions add constraint maintenance_completions_pkey PRIMARY KEY (id);
alter table public.maintenance_completions add constraint maintenance_completions_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES maintenance_plans(id) ON DELETE CASCADE;
alter table public.maintenance_completions add constraint maintenance_completions_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.maintenance_completions add constraint maintenance_completions_supervisor_approved_by_fkey FOREIGN KEY (supervisor_approved_by) REFERENCES auth.users(id);
alter table public.maintenance_completions add constraint maintenance_completions_worker_id_fkey FOREIGN KEY (worker_id) REFERENCES auth.users(id);
alter table public.maintenance_plans add constraint maintenance_plans_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES assets(id);
alter table public.maintenance_plans add constraint maintenance_plans_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES auth.users(id);
alter table public.maintenance_plans add constraint maintenance_plans_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.maintenance_plans add constraint maintenance_plans_last_completed_by_fkey FOREIGN KEY (last_completed_by) REFERENCES auth.users(id);
alter table public.maintenance_plans add constraint maintenance_plans_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.maintenance_plans add constraint maintenance_plans_pkey PRIMARY KEY (id);
alter table public.maintenance_plans add constraint maintenance_plans_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.maintenance_plans add constraint maintenance_plans_removed_by_fkey FOREIGN KEY (removed_by) REFERENCES auth.users(id);
alter table public.manuals add constraint manuals_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES assets(id);
alter table public.manuals add constraint manuals_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.manuals add constraint manuals_pkey PRIMARY KEY (id);
alter table public.manuals add constraint manuals_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id);
alter table public.manuals add constraint manuals_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES auth.users(id);
alter table public.material_requests add constraint material_requests_managed_by_fkey FOREIGN KEY (managed_by) REFERENCES auth.users(id);
alter table public.material_requests add constraint material_requests_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.material_requests add constraint material_requests_pkey PRIMARY KEY (id);
alter table public.material_requests add constraint material_requests_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.material_requests add constraint material_requests_purchase_order_id_fkey FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders(id) ON DELETE SET NULL;
alter table public.material_requests add constraint material_requests_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES auth.users(id);
alter table public.material_requests add constraint material_requests_spare_id_fkey FOREIGN KEY (spare_id) REFERENCES spares(id) ON DELETE CASCADE;
alter table public.measurement_points add constraint measurement_points_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE CASCADE;
alter table public.measurement_points add constraint measurement_points_asset_id_name_direction_key UNIQUE (asset_id, name, direction);
alter table public.measurement_points add constraint measurement_points_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.measurement_points add constraint measurement_points_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.measurement_points add constraint measurement_points_pkey PRIMARY KEY (id);
alter table public.measurement_points add constraint measurement_points_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.notifications add constraint notifications_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.notifications add constraint notifications_pkey PRIMARY KEY (id);
alter table public.notifications add constraint notifications_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id);
alter table public.notifications add constraint notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);
alter table public.organization_entitlements add constraint organization_entitlements_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.organization_entitlements add constraint organization_entitlements_pkey PRIMARY KEY (organization_id, entitlement);
alter table public.organization_entitlements add constraint organization_entitlements_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id);
alter table public.organization_members add constraint organization_members_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.organization_members add constraint organization_members_pkey PRIMARY KEY (organization_id, user_id);
alter table public.organization_members add constraint organization_members_role_check CHECK ((role = ANY (ARRAY['owner'::text, 'manager'::text, 'deputy_manager'::text, 'assistant_manager'::text, 'supervisor'::text, 'engineer'::text, 'mechanical_engineer'::text, 'electrical_engineer'::text, 'production_engineer'::text, 'utility_engineer'::text, 'power_house_engineer'::text, 'technical_officer'::text, 'senior_technical_officer'::text, 'technician'::text, 'senior_technician'::text, 'operator'::text, 'assistant_operator'::text, 'senior_operator'::text, 'worker'::text, 'checker'::text, 'quality_control_officer'::text, 'store'::text, 'admin_officer'::text, 'time_officer'::text, 'viewer'::text])));
alter table public.organization_members add constraint organization_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.organization_settings add constraint organization_settings_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.organization_settings add constraint organization_settings_pkey PRIMARY KEY (organization_id);
alter table public.organization_subscriptions add constraint organization_subscription_status_check CHECK ((status = ANY (ARRAY['trial'::text, 'active'::text, 'past_due'::text, 'suspended'::text, 'cancelled'::text])));
alter table public.organization_subscriptions add constraint organization_subscriptions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.organization_subscriptions add constraint organization_subscriptions_organization_id_key UNIQUE (organization_id);
alter table public.organization_subscriptions add constraint organization_subscriptions_pkey PRIMARY KEY (id);
alter table public.organization_subscriptions add constraint organization_subscriptions_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES subscription_plans(id);
alter table public.organizations add constraint organizations_commercial_status_check CHECK ((commercial_status = ANY (ARRAY['trial'::text, 'active'::text, 'past_due'::text, 'suspended'::text, 'cancelled'::text, 'deletion_pending'::text])));
alter table public.organizations add constraint organizations_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.organizations add constraint organizations_pkey PRIMARY KEY (id);
alter table public.organizations add constraint organizations_slug_key UNIQUE (slug);
alter table public.permits add constraint permits_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES auth.users(id);
alter table public.permits add constraint permits_pkey PRIMARY KEY (id);
alter table public.permits add constraint permits_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.permits add constraint permits_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES auth.users(id);
alter table public.permits add constraint permits_work_order_id_fkey FOREIGN KEY (work_order_id) REFERENCES work_orders(id) ON DELETE CASCADE;
alter table public.plant_members add constraint plant_members_pkey PRIMARY KEY (plant_id, user_id);
alter table public.plant_members add constraint plant_members_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.plant_members add constraint plant_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.plantmaster_sync add constraint plantmaster_sync_pkey PRIMARY KEY (site_id);
alter table public.plants add constraint plants_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.plants add constraint plants_pkey PRIMARY KEY (id);
alter table public.platform_admins add constraint platform_admin_role_check CHECK ((admin_role = ANY (ARRAY['super_admin'::text, 'operations'::text, 'support'::text, 'billing'::text, 'auditor'::text])));
alter table public.platform_admins add constraint platform_admins_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.platform_admins add constraint platform_admins_pkey PRIMARY KEY (user_id);
alter table public.platform_admins add constraint platform_admins_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.platform_notifications add constraint platform_notifications_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.platform_notifications add constraint platform_notifications_pkey PRIMARY KEY (id);
alter table public.platform_notifications add constraint platform_notifications_severity_check CHECK ((severity = ANY (ARRAY['info'::text, 'warning'::text, 'error'::text, 'critical'::text])));
alter table public.platform_support_messages add constraint platform_support_messages_pkey PRIMARY KEY (id);
alter table public.platform_support_messages add constraint platform_support_messages_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES platform_support_tickets(id) ON DELETE CASCADE;
alter table public.platform_support_messages add constraint platform_support_messages_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);
alter table public.platform_support_tickets add constraint platform_support_tickets_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES auth.users(id);
alter table public.platform_support_tickets add constraint platform_support_tickets_opened_by_fkey FOREIGN KEY (opened_by) REFERENCES auth.users(id);
alter table public.platform_support_tickets add constraint platform_support_tickets_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE SET NULL;
alter table public.platform_support_tickets add constraint platform_support_tickets_pkey PRIMARY KEY (id);
alter table public.platform_support_tickets add constraint platform_support_tickets_priority_check CHECK ((priority = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text])));
alter table public.platform_support_tickets add constraint platform_support_tickets_related_incident_id_fkey FOREIGN KEY (related_incident_id) REFERENCES system_incidents(id) ON DELETE SET NULL;
alter table public.platform_support_tickets add constraint platform_support_tickets_status_check CHECK ((status = ANY (ARRAY['new'::text, 'acknowledged'::text, 'investigating'::text, 'waiting_customer'::text, 'resolved'::text, 'closed'::text])));
alter table public.platform_support_tickets add constraint platform_support_tickets_ticket_number_key UNIQUE (ticket_number);
alter table public.problem_cases add constraint problem_cases_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES assets(id);
alter table public.problem_cases add constraint problem_cases_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.problem_cases add constraint problem_cases_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.problem_cases add constraint problem_cases_pkey PRIMARY KEY (id);
alter table public.problem_cases add constraint problem_cases_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.profiles add constraint profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.profiles add constraint profiles_pkey PRIMARY KEY (id);
alter table public.purchase_order_lines add constraint purchase_order_lines_pkey PRIMARY KEY (id);
alter table public.purchase_order_lines add constraint purchase_order_lines_purchase_order_id_fkey FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders(id) ON DELETE CASCADE;
alter table public.purchase_order_lines add constraint purchase_order_lines_quantity_check CHECK ((quantity > (0)::numeric));
alter table public.purchase_order_lines add constraint purchase_order_lines_spare_id_fkey FOREIGN KEY (spare_id) REFERENCES spares(id) ON DELETE SET NULL;
alter table public.purchase_orders add constraint purchase_orders_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES auth.users(id);
alter table public.purchase_orders add constraint purchase_orders_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.purchase_orders add constraint purchase_orders_organization_id_po_number_key UNIQUE (organization_id, po_number);
alter table public.purchase_orders add constraint purchase_orders_pkey PRIMARY KEY (id);
alter table public.purchase_orders add constraint purchase_orders_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.purchase_orders add constraint purchase_orders_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES auth.users(id);
alter table public.purchase_orders add constraint purchase_orders_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'pending_approval'::text, 'approved'::text, 'sent'::text, 'partially_received'::text, 'received'::text, 'cancelled'::text])));
alter table public.purchase_orders add constraint purchase_orders_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL;
alter table public.push_cursors add constraint push_cursors_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.push_cursors add constraint push_cursors_pkey PRIMARY KEY (organization_id);
alter table public.push_subscriptions add constraint push_subscriptions_endpoint_key UNIQUE (endpoint);
alter table public.push_subscriptions add constraint push_subscriptions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.push_subscriptions add constraint push_subscriptions_pkey PRIMARY KEY (id);
alter table public.push_subscriptions add constraint push_subscriptions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.qa_environments add constraint qa_environments_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.qa_environments add constraint qa_environments_isolation_organization_id_fkey FOREIGN KEY (isolation_organization_id) REFERENCES organizations(id) ON DELETE SET NULL;
alter table public.qa_environments add constraint qa_environments_name_key UNIQUE (name);
alter table public.qa_environments add constraint qa_environments_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE SET NULL;
alter table public.qa_environments add constraint qa_environments_pkey PRIMARY KEY (id);
alter table public.qa_environments add constraint qa_environments_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE SET NULL;
alter table public.qa_environments add constraint qa_environments_status_check CHECK ((status = ANY (ARRAY['creating'::text, 'ready'::text, 'testing'::text, 'failed'::text, 'deleting'::text, 'deleted'::text])));
alter table public.qa_manual_checks add constraint qa_manual_checks_pkey PRIMARY KEY (id);
alter table public.qa_manual_checks add constraint qa_manual_checks_run_id_fkey FOREIGN KEY (run_id) REFERENCES qa_test_runs(id) ON DELETE CASCADE;
alter table public.qa_manual_checks add constraint qa_manual_checks_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'passed'::text, 'failed'::text, 'not_available'::text])));
alter table public.qa_manual_checks add constraint qa_manual_checks_tested_by_fkey FOREIGN KEY (tested_by) REFERENCES auth.users(id);
alter table public.qa_test_results add constraint qa_test_results_pkey PRIMARY KEY (id);
alter table public.qa_test_results add constraint qa_test_results_run_id_fkey FOREIGN KEY (run_id) REFERENCES qa_test_runs(id) ON DELETE CASCADE;
alter table public.qa_test_results add constraint qa_test_results_status_check CHECK ((status = ANY (ARRAY['passed'::text, 'failed'::text, 'blocked'::text, 'manual_required'::text])));
alter table public.qa_test_runs add constraint qa_test_runs_environment_id_fkey FOREIGN KEY (environment_id) REFERENCES qa_environments(id) ON DELETE CASCADE;
alter table public.qa_test_runs add constraint qa_test_runs_pkey PRIMARY KEY (id);
alter table public.qa_test_runs add constraint qa_test_runs_started_by_fkey FOREIGN KEY (started_by) REFERENCES auth.users(id);
alter table public.qa_test_runs add constraint qa_test_runs_status_check CHECK ((status = ANY (ARRAY['running'::text, 'passed'::text, 'failed'::text, 'partial'::text, 'cancelled'::text])));
alter table public.quota_overrides add constraint quota_overrides_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.quota_overrides add constraint quota_overrides_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.quota_overrides add constraint quota_overrides_override_type_check CHECK ((override_type = ANY (ARRAY['absolute'::text, 'bonus'::text, 'block'::text])));
alter table public.quota_overrides add constraint quota_overrides_pkey PRIMARY KEY (id);
alter table public.report_dispatches add constraint report_dispatches_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES auth.users(id);
alter table public.report_dispatches add constraint report_dispatches_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.report_dispatches add constraint report_dispatches_pkey PRIMARY KEY (id);
alter table public.report_dispatches add constraint report_dispatches_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id);
alter table public.restore_drills add constraint restore_drills_backup_job_id_fkey FOREIGN KEY (backup_job_id) REFERENCES backup_jobs(id) ON DELETE SET NULL;
alter table public.restore_drills add constraint restore_drills_performed_by_fkey FOREIGN KEY (performed_by) REFERENCES auth.users(id);
alter table public.restore_drills add constraint restore_drills_pkey PRIMARY KEY (id);
alter table public.restore_drills add constraint restore_drills_status_check CHECK ((status = ANY (ARRAY['planned'::text, 'running'::text, 'passed'::text, 'failed'::text, 'cancelled'::text])));
alter table public.scan_entity_links add constraint scan_entity_links_linked_by_fkey FOREIGN KEY (linked_by) REFERENCES auth.users(id);
alter table public.scan_entity_links add constraint scan_entity_links_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.scan_entity_links add constraint scan_entity_links_pkey PRIMARY KEY (id);
alter table public.scan_entity_links add constraint scan_entity_links_scan_session_id_entity_type_entity_id_rel_key UNIQUE (scan_session_id, entity_type, entity_id, relation);
alter table public.scan_entity_links add constraint scan_entity_links_scan_session_id_fkey FOREIGN KEY (scan_session_id) REFERENCES scan_sessions(id) ON DELETE CASCADE;
alter table public.scan_pages add constraint scan_pages_pkey PRIMARY KEY (id);
alter table public.scan_pages add constraint scan_pages_session_id_fkey FOREIGN KEY (session_id) REFERENCES scan_sessions(id) ON DELETE CASCADE;
alter table public.scan_pages add constraint scan_pages_session_id_page_number_key UNIQUE (session_id, page_number);
alter table public.scan_sessions add constraint scan_sessions_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES auth.users(id);
alter table public.scan_sessions add constraint scan_sessions_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.scan_sessions add constraint scan_sessions_mode_check CHECK ((mode = ANY (ARRAY['qr_barcode'::text, 'document'::text, 'nameplate'::text, 'identify'::text, 'import'::text])));
alter table public.scan_sessions add constraint scan_sessions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.scan_sessions add constraint scan_sessions_pkey PRIMARY KEY (id);
alter table public.scan_sessions add constraint scan_sessions_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.scan_sessions add constraint scan_sessions_removed_by_fkey FOREIGN KEY (removed_by) REFERENCES auth.users(id);
alter table public.scan_sessions add constraint scan_sessions_source_type_check CHECK ((source_type = ANY (ARRAY['camera'::text, 'gallery'::text, 'file'::text, 'offline'::text])));
alter table public.scan_sessions add constraint scan_sessions_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'processing'::text, 'completed'::text, 'failed'::text, 'submitted'::text, 'approved'::text])));
alter table public.sensor_devices add constraint sensor_devices_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.sensor_devices add constraint sensor_devices_pkey PRIMARY KEY (id);
alter table public.sensor_devices add constraint sensor_devices_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.sensor_devices add constraint sensor_devices_sensor_type_check CHECK ((sensor_type = ANY (ARRAY['phone'::text, 'bluetooth_accelerometer'::text, 'usb_sensor'::text, 'industrial_monitor'::text])));
alter table public.shift_assignments add constraint shift_assignments_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.shift_assignments add constraint shift_assignments_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.shift_assignments add constraint shift_assignments_pkey PRIMARY KEY (id);
alter table public.shift_assignments add constraint shift_assignments_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.shift_assignments add constraint shift_assignments_plant_id_user_id_work_date_key UNIQUE (plant_id, user_id, work_date);
alter table public.shift_assignments add constraint shift_assignments_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);
alter table public.shift_handovers add constraint shift_handovers_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.shift_handovers add constraint shift_handovers_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.shift_handovers add constraint shift_handovers_pkey PRIMARY KEY (id);
alter table public.shift_handovers add constraint shift_handovers_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.spares add constraint spares_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES assets(id);
alter table public.spares add constraint spares_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.spares add constraint spares_pkey PRIMARY KEY (id);
alter table public.spares add constraint spares_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.spares add constraint spares_removed_by_fkey FOREIGN KEY (removed_by) REFERENCES auth.users(id);
alter table public.storage_reservations add constraint storage_reservations_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.storage_reservations add constraint storage_reservations_pkey PRIMARY KEY (id);
alter table public.storage_reservations add constraint storage_reservations_status_check CHECK ((status = ANY (ARRAY['reserved'::text, 'completed'::text, 'cancelled'::text, 'expired'::text])));
alter table public.storage_reservations add constraint storage_reservations_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.storage_usage_events add constraint storage_usage_events_event_type_check CHECK ((event_type = ANY (ARRAY['upload'::text, 'download'::text, 'delete'::text, 'reconcile'::text, 'restore'::text])));
alter table public.storage_usage_events add constraint storage_usage_events_file_metadata_id_fkey FOREIGN KEY (file_metadata_id) REFERENCES file_metadata(id) ON DELETE SET NULL;
alter table public.storage_usage_events add constraint storage_usage_events_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.storage_usage_events add constraint storage_usage_events_pkey PRIMARY KEY (id);
alter table public.storage_usage_events add constraint storage_usage_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public.subscription_plans add constraint subscription_plans_code_key UNIQUE (code);
alter table public.subscription_plans add constraint subscription_plans_pkey PRIMARY KEY (id);
alter table public.suppliers add constraint suppliers_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.suppliers add constraint suppliers_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.suppliers add constraint suppliers_pkey PRIMARY KEY (id);
alter table public.suppliers add constraint suppliers_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE SET NULL;
alter table public.suppliers add constraint suppliers_rating_check CHECK (((rating >= (0)::numeric) AND (rating <= (5)::numeric)));
alter table public.support_messages add constraint support_messages_pkey PRIMARY KEY (id);
alter table public.support_messages add constraint support_messages_thread_id_fkey FOREIGN KEY (thread_id) REFERENCES support_threads(id) ON DELETE CASCADE;
alter table public.support_messages add constraint support_messages_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);
alter table public.support_threads add constraint support_threads_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES assets(id);
alter table public.support_threads add constraint support_threads_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.support_threads add constraint support_threads_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.support_threads add constraint support_threads_pkey PRIMARY KEY (id);
alter table public.support_threads add constraint support_threads_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.system_incidents add constraint system_incidents_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.system_incidents add constraint system_incidents_pkey PRIMARY KEY (id);
alter table public.system_incidents add constraint system_incidents_severity_check CHECK ((severity = ANY (ARRAY['info'::text, 'warning'::text, 'error'::text, 'critical'::text])));
alter table public.system_incidents add constraint system_incidents_status_check CHECK ((status = ANY (ARRAY['open'::text, 'acknowledged'::text, 'resolved'::text])));
alter table public.technical_experiences add constraint technical_experiences_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES assets(id);
alter table public.technical_experiences add constraint technical_experiences_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.technical_experiences add constraint technical_experiences_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.technical_experiences add constraint technical_experiences_pkey PRIMARY KEY (id);
alter table public.technical_experiences add constraint technical_experiences_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.tool_transactions add constraint tool_transactions_holder_id_fkey FOREIGN KEY (holder_id) REFERENCES auth.users(id);
alter table public.tool_transactions add constraint tool_transactions_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.tool_transactions add constraint tool_transactions_performed_by_fkey FOREIGN KEY (performed_by) REFERENCES auth.users(id);
alter table public.tool_transactions add constraint tool_transactions_pkey PRIMARY KEY (id);
alter table public.tool_transactions add constraint tool_transactions_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.tool_transactions add constraint tool_transactions_tool_id_fkey FOREIGN KEY (tool_id) REFERENCES tools(id) ON DELETE CASCADE;
alter table public.tool_transactions add constraint tool_transactions_transaction_type_check CHECK ((transaction_type = ANY (ARRAY['checkout'::text, 'return'::text, 'calibration'::text, 'inspection'::text])));
alter table public.tools add constraint tools_holder_id_fkey FOREIGN KEY (holder_id) REFERENCES auth.users(id);
alter table public.tools add constraint tools_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.tools add constraint tools_pkey PRIMARY KEY (id);
alter table public.tools add constraint tools_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.tools add constraint tools_removed_by_fkey FOREIGN KEY (removed_by) REFERENCES auth.users(id);
alter table public.usage_adjustments add constraint usage_adjustments_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.usage_adjustments add constraint usage_adjustments_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.usage_adjustments add constraint usage_adjustments_pkey PRIMARY KEY (id);
alter table public.usage_counters add constraint usage_counters_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.usage_counters add constraint usage_counters_pkey PRIMARY KEY (organization_id, metric, period_start);
alter table public.usage_events add constraint usage_events_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.usage_events add constraint usage_events_pkey PRIMARY KEY (id);
alter table public.usage_events add constraint usage_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public.work_orders add constraint work_orders_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES assets(id) ON DELETE SET NULL;
alter table public.work_orders add constraint work_orders_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES auth.users(id);
alter table public.work_orders add constraint work_orders_completed_by_fkey FOREIGN KEY (completed_by) REFERENCES auth.users(id);
alter table public.work_orders add constraint work_orders_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.work_orders add constraint work_orders_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE CASCADE;
alter table public.work_orders add constraint work_orders_pkey PRIMARY KEY (id);
alter table public.work_orders add constraint work_orders_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES plants(id) ON DELETE CASCADE;
alter table public.work_orders add constraint work_orders_removed_by_fkey FOREIGN KEY (removed_by) REFERENCES auth.users(id);
alter table public.work_orders add constraint work_orders_supervisor_approved_by_fkey FOREIGN KEY (supervisor_approved_by) REFERENCES auth.users(id);


-- =====================================================================
-- INDEXES
-- =====================================================================
CREATE INDEX IF NOT EXISTS admin_action_time_idx ON public.admin_action_logs USING btree (created_at DESC);
CREATE INDEX IF NOT EXISTS ai_usage_org_time_idx ON public.ai_usage USING btree (organization_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS ai_usage_request_id_idx ON public.ai_usage USING btree (request_id);
CREATE INDEX IF NOT EXISTS api_keys_hash_idx ON public.api_keys USING btree (key_hash);
CREATE INDEX IF NOT EXISTS api_keys_org_idx ON public.api_keys USING btree (organization_id);
CREATE INDEX IF NOT EXISTS assets_plant_updated_idx ON public.assets USING btree (plant_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS code_registry_entity_idx ON public.code_registry USING btree (organization_id, entity_type, entity_id);
CREATE INDEX IF NOT EXISTS condition_alarms_org_time_idx ON public.condition_alarms USING btree (organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS condition_recordings_asset_time_idx ON public.condition_recordings USING btree (asset_id, created_at DESC);
CREATE INDEX IF NOT EXISTS condition_recordings_baseline_idx ON public.condition_recordings USING btree (asset_id, measurement_point_id, is_baseline) WHERE (removed_at IS NULL);
CREATE INDEX IF NOT EXISTS condition_recordings_org_time_idx ON public.condition_recordings USING btree (organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS daily_logs_plant_date_idx ON public.daily_logs USING btree (plant_id, log_date DESC);
CREATE INDEX IF NOT EXISTS document_chunks_embedding_idx ON public.document_chunks USING hnsw (embedding vector_cosine_ops);
CREATE INDEX IF NOT EXISTS maintenance_completion_plan_idx ON public.maintenance_completions USING btree (plan_id, completed_at DESC);
CREATE INDEX IF NOT EXISTS notifications_org_created_idx ON public.notifications USING btree (organization_id, created_at);
CREATE INDEX IF NOT EXISTS platform_tickets_status_priority_idx ON public.platform_support_tickets USING btree (status, priority, updated_at DESC);
CREATE INDEX IF NOT EXISTS pol_po_idx ON public.purchase_order_lines USING btree (purchase_order_id);
CREATE INDEX IF NOT EXISTS po_plant_idx ON public.purchase_orders USING btree (plant_id) WHERE (removed_at IS NULL);
CREATE INDEX IF NOT EXISTS po_status_idx ON public.purchase_orders USING btree (status) WHERE (removed_at IS NULL);
CREATE INDEX IF NOT EXISTS po_supplier_idx ON public.purchase_orders USING btree (supplier_id) WHERE (removed_at IS NULL);
CREATE INDEX IF NOT EXISTS push_subs_org_idx ON public.push_subscriptions USING btree (organization_id);
CREATE INDEX IF NOT EXISTS qa_results_run_status_idx ON public.qa_test_results USING btree (run_id, status, category);
CREATE INDEX IF NOT EXISTS quota_overrides_org_metric_idx ON public.quota_overrides USING btree (organization_id, metric, active);
CREATE INDEX IF NOT EXISTS scan_sessions_link_idx ON public.scan_sessions USING btree (organization_id, linked_entity_type, linked_entity_id);
CREATE INDEX IF NOT EXISTS scan_sessions_org_time_idx ON public.scan_sessions USING btree (organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS scan_sessions_plant_mode_idx ON public.scan_sessions USING btree (plant_id, mode, status);
CREATE INDEX IF NOT EXISTS handovers_plant_date_idx ON public.shift_handovers USING btree (plant_id, work_date DESC);
CREATE INDEX IF NOT EXISTS storage_reservations_org_status_idx ON public.storage_reservations USING btree (organization_id, status, expires_at);
CREATE INDEX IF NOT EXISTS storage_usage_org_time_idx ON public.storage_usage_events USING btree (organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS suppliers_org_idx ON public.suppliers USING btree (organization_id) WHERE (removed_at IS NULL);
CREATE INDEX IF NOT EXISTS suppliers_plant_idx ON public.suppliers USING btree (plant_id) WHERE (removed_at IS NULL);
CREATE INDEX IF NOT EXISTS incidents_status_severity_idx ON public.system_incidents USING btree (status, severity, last_seen_at DESC);
CREATE INDEX IF NOT EXISTS tool_transactions_tool_idx ON public.tool_transactions USING btree (tool_id, created_at DESC);
CREATE INDEX IF NOT EXISTS usage_counters_org_period_idx ON public.usage_counters USING btree (organization_id, period_start DESC);
CREATE INDEX IF NOT EXISTS usage_events_org_metric_time_idx ON public.usage_events USING btree (organization_id, metric, created_at DESC);
CREATE INDEX IF NOT EXISTS usage_events_user_metric_time_idx ON public.usage_events USING btree (user_id, metric, created_at DESC);
CREATE INDEX IF NOT EXISTS work_orders_plant_updated_idx ON public.work_orders USING btree (plant_id, updated_at DESC);


-- =====================================================================
-- TRIGGERS  (run AFTER 02-function-source.sql)
-- =====================================================================
drop trigger if exists commercial_write_guard_action_attachments on public.action_attachments;
CREATE TRIGGER commercial_write_guard_action_attachments BEFORE INSERT OR DELETE OR UPDATE ON public.action_attachments FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists admin_logs_append_only on public.admin_action_logs;
CREATE TRIGGER admin_logs_append_only BEFORE DELETE OR UPDATE ON public.admin_action_logs FOR EACH ROW EXECUTE FUNCTION deny_admin_log_mutation();
drop trigger if exists bump_version_assets on public.assets;
CREATE TRIGGER bump_version_assets BEFORE UPDATE ON public.assets FOR EACH ROW EXECUTE FUNCTION bump_row_version();
drop trigger if exists commercial_write_guard_assets on public.assets;
CREATE TRIGGER commercial_write_guard_assets BEFORE INSERT OR DELETE OR UPDATE ON public.assets FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists owner_hard_delete_assets on public.assets;
CREATE TRIGGER owner_hard_delete_assets BEFORE DELETE ON public.assets FOR EACH ROW EXECUTE FUNCTION require_owner_for_hard_delete();
drop trigger if exists commercial_write_guard_attendance on public.attendance;
CREATE TRIGGER commercial_write_guard_attendance BEFORE INSERT OR DELETE OR UPDATE ON public.attendance FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists commercial_write_guard_checklist_runs on public.checklist_runs;
CREATE TRIGGER commercial_write_guard_checklist_runs BEFORE INSERT OR DELETE OR UPDATE ON public.checklist_runs FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists bump_version_checklist_templates on public.checklist_templates;
CREATE TRIGGER bump_version_checklist_templates BEFORE UPDATE ON public.checklist_templates FOR EACH ROW EXECUTE FUNCTION bump_row_version();
drop trigger if exists commercial_write_guard_checklist_templates on public.checklist_templates;
CREATE TRIGGER commercial_write_guard_checklist_templates BEFORE INSERT OR DELETE OR UPDATE ON public.checklist_templates FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists owner_hard_delete_checklist_templates on public.checklist_templates;
CREATE TRIGGER owner_hard_delete_checklist_templates BEFORE DELETE ON public.checklist_templates FOR EACH ROW EXECUTE FUNCTION require_owner_for_hard_delete();
drop trigger if exists commercial_write_guard_code_registry on public.code_registry;
CREATE TRIGGER commercial_write_guard_code_registry BEFORE INSERT OR DELETE OR UPDATE ON public.code_registry FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists commercial_write_guard_condition_alarms on public.condition_alarms;
CREATE TRIGGER commercial_write_guard_condition_alarms BEFORE INSERT OR DELETE OR UPDATE ON public.condition_alarms FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists commercial_write_guard_condition_entity_links on public.condition_entity_links;
CREATE TRIGGER commercial_write_guard_condition_entity_links BEFORE INSERT OR DELETE OR UPDATE ON public.condition_entity_links FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists commercial_write_guard_condition_recordings on public.condition_recordings;
CREATE TRIGGER commercial_write_guard_condition_recordings BEFORE INSERT OR DELETE OR UPDATE ON public.condition_recordings FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists owner_hard_delete_condition_recordings on public.condition_recordings;
CREATE TRIGGER owner_hard_delete_condition_recordings BEFORE DELETE ON public.condition_recordings FOR EACH ROW EXECUTE FUNCTION require_owner_for_hard_delete();
drop trigger if exists protect_condition_baseline on public.condition_recordings;
CREATE TRIGGER protect_condition_baseline BEFORE INSERT OR UPDATE OF is_baseline ON public.condition_recordings FOR EACH ROW EXECUTE FUNCTION protect_condition_baseline();
drop trigger if exists commercial_write_guard_daily_logs on public.daily_logs;
CREATE TRIGGER commercial_write_guard_daily_logs BEFORE INSERT OR DELETE OR UPDATE ON public.daily_logs FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists commercial_write_guard_file_metadata on public.file_metadata;
CREATE TRIGGER commercial_write_guard_file_metadata BEFORE INSERT OR DELETE OR UPDATE ON public.file_metadata FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists owner_hard_delete_file_metadata on public.file_metadata;
CREATE TRIGGER owner_hard_delete_file_metadata BEFORE DELETE ON public.file_metadata FOR EACH ROW EXECUTE FUNCTION require_owner_for_hard_delete();
drop trigger if exists commercial_write_guard_invitations on public.invitations;
CREATE TRIGGER commercial_write_guard_invitations BEFORE INSERT OR DELETE OR UPDATE ON public.invitations FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists invitation_plan_limit on public.invitations;
CREATE TRIGGER invitation_plan_limit BEFORE INSERT OR UPDATE OF accepted_at, expires_at ON public.invitations FOR EACH ROW EXECUTE FUNCTION enforce_worker_plan_limit();
drop trigger if exists protect_invitation_owner_role on public.invitations;
CREATE TRIGGER protect_invitation_owner_role BEFORE INSERT OR UPDATE ON public.invitations FOR EACH ROW EXECUTE FUNCTION protect_owner_role();
drop trigger if exists commercial_write_guard_maintenance_completions on public.maintenance_completions;
CREATE TRIGGER commercial_write_guard_maintenance_completions BEFORE INSERT OR DELETE OR UPDATE ON public.maintenance_completions FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists bump_version_maintenance_plans on public.maintenance_plans;
CREATE TRIGGER bump_version_maintenance_plans BEFORE UPDATE ON public.maintenance_plans FOR EACH ROW EXECUTE FUNCTION bump_row_version();
drop trigger if exists commercial_write_guard_maintenance_plans on public.maintenance_plans;
CREATE TRIGGER commercial_write_guard_maintenance_plans BEFORE INSERT OR DELETE OR UPDATE ON public.maintenance_plans FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists owner_hard_delete_maintenance_plans on public.maintenance_plans;
CREATE TRIGGER owner_hard_delete_maintenance_plans BEFORE DELETE ON public.maintenance_plans FOR EACH ROW EXECUTE FUNCTION require_owner_for_hard_delete();
drop trigger if exists commercial_write_guard_manuals on public.manuals;
CREATE TRIGGER commercial_write_guard_manuals BEFORE INSERT OR DELETE OR UPDATE ON public.manuals FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists commercial_write_guard_measurement_points on public.measurement_points;
CREATE TRIGGER commercial_write_guard_measurement_points BEFORE INSERT OR DELETE OR UPDATE ON public.measurement_points FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists commercial_write_guard_notifications on public.notifications;
CREATE TRIGGER commercial_write_guard_notifications BEFORE INSERT OR DELETE OR UPDATE ON public.notifications FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists member_plan_limit on public.organization_members;
CREATE TRIGGER member_plan_limit BEFORE INSERT OR UPDATE OF active ON public.organization_members FOR EACH ROW EXECUTE FUNCTION enforce_worker_plan_limit();
drop trigger if exists protect_member_owner_role on public.organization_members;
CREATE TRIGGER protect_member_owner_role BEFORE UPDATE ON public.organization_members FOR EACH ROW EXECUTE FUNCTION protect_owner_role();
drop trigger if exists commercial_write_guard_organization_settings on public.organization_settings;
CREATE TRIGGER commercial_write_guard_organization_settings BEFORE INSERT OR DELETE OR UPDATE ON public.organization_settings FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists organization_commercial_defaults on public.organizations;
CREATE TRIGGER organization_commercial_defaults AFTER INSERT ON public.organizations FOR EACH ROW EXECUTE FUNCTION create_default_commercial_records();
drop trigger if exists organizations_push_cursor on public.organizations;
CREATE TRIGGER organizations_push_cursor AFTER INSERT ON public.organizations FOR EACH ROW EXECUTE FUNCTION new_push_cursor();
drop trigger if exists plantmaster_sync_updated_at on public.plantmaster_sync;
CREATE TRIGGER plantmaster_sync_updated_at BEFORE UPDATE ON public.plantmaster_sync FOR EACH ROW EXECUTE FUNCTION set_plantmaster_updated_at();
drop trigger if exists plant_plan_limit on public.plants;
CREATE TRIGGER plant_plan_limit BEFORE INSERT OR UPDATE OF organization_id ON public.plants FOR EACH ROW EXECUTE FUNCTION enforce_plant_plan_limit();
drop trigger if exists ticket_platform_alert on public.platform_support_tickets;
CREATE TRIGGER ticket_platform_alert AFTER INSERT ON public.platform_support_tickets FOR EACH ROW EXECUTE FUNCTION create_platform_alert();
drop trigger if exists commercial_write_guard_problem_cases on public.problem_cases;
CREATE TRIGGER commercial_write_guard_problem_cases BEFORE INSERT OR DELETE OR UPDATE ON public.problem_cases FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists trg_po_line_aid on public.purchase_order_lines;
CREATE TRIGGER trg_po_line_aid AFTER INSERT OR DELETE OR UPDATE ON public.purchase_order_lines FOR EACH ROW EXECUTE FUNCTION po_line_after_change();
drop trigger if exists trg_po_line_biu on public.purchase_order_lines;
CREATE TRIGGER trg_po_line_biu BEFORE INSERT OR UPDATE ON public.purchase_order_lines FOR EACH ROW EXECUTE FUNCTION po_line_after_change();
drop trigger if exists commercial_write_guard_report_dispatches on public.report_dispatches;
CREATE TRIGGER commercial_write_guard_report_dispatches BEFORE INSERT OR DELETE OR UPDATE ON public.report_dispatches FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists commercial_write_guard_scan_entity_links on public.scan_entity_links;
CREATE TRIGGER commercial_write_guard_scan_entity_links BEFORE INSERT OR DELETE OR UPDATE ON public.scan_entity_links FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists commercial_write_guard_scan_sessions on public.scan_sessions;
CREATE TRIGGER commercial_write_guard_scan_sessions BEFORE INSERT OR DELETE OR UPDATE ON public.scan_sessions FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists owner_hard_delete_scan_sessions on public.scan_sessions;
CREATE TRIGGER owner_hard_delete_scan_sessions BEFORE DELETE ON public.scan_sessions FOR EACH ROW EXECUTE FUNCTION require_owner_for_hard_delete();
drop trigger if exists commercial_write_guard_sensor_devices on public.sensor_devices;
CREATE TRIGGER commercial_write_guard_sensor_devices BEFORE INSERT OR DELETE OR UPDATE ON public.sensor_devices FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists commercial_write_guard_shift_assignments on public.shift_assignments;
CREATE TRIGGER commercial_write_guard_shift_assignments BEFORE INSERT OR DELETE OR UPDATE ON public.shift_assignments FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists commercial_write_guard_shift_handovers on public.shift_handovers;
CREATE TRIGGER commercial_write_guard_shift_handovers BEFORE INSERT OR DELETE OR UPDATE ON public.shift_handovers FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists bump_version_spares on public.spares;
CREATE TRIGGER bump_version_spares BEFORE UPDATE ON public.spares FOR EACH ROW EXECUTE FUNCTION bump_row_version();
drop trigger if exists commercial_write_guard_spares on public.spares;
CREATE TRIGGER commercial_write_guard_spares BEFORE INSERT OR DELETE OR UPDATE ON public.spares FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists owner_hard_delete_spares on public.spares;
CREATE TRIGGER owner_hard_delete_spares BEFORE DELETE ON public.spares FOR EACH ROW EXECUTE FUNCTION require_owner_for_hard_delete();
drop trigger if exists commercial_write_guard_support_threads on public.support_threads;
CREATE TRIGGER commercial_write_guard_support_threads BEFORE INSERT OR DELETE OR UPDATE ON public.support_threads FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists incident_platform_alert on public.system_incidents;
CREATE TRIGGER incident_platform_alert AFTER INSERT ON public.system_incidents FOR EACH ROW EXECUTE FUNCTION create_platform_alert();
drop trigger if exists commercial_write_guard_technical_experiences on public.technical_experiences;
CREATE TRIGGER commercial_write_guard_technical_experiences BEFORE INSERT OR DELETE OR UPDATE ON public.technical_experiences FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists commercial_write_guard_tool_transactions on public.tool_transactions;
CREATE TRIGGER commercial_write_guard_tool_transactions BEFORE INSERT OR DELETE OR UPDATE ON public.tool_transactions FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists bump_version_tools on public.tools;
CREATE TRIGGER bump_version_tools BEFORE UPDATE ON public.tools FOR EACH ROW EXECUTE FUNCTION bump_row_version();
drop trigger if exists commercial_write_guard_tools on public.tools;
CREATE TRIGGER commercial_write_guard_tools BEFORE INSERT OR DELETE OR UPDATE ON public.tools FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists owner_hard_delete_tools on public.tools;
CREATE TRIGGER owner_hard_delete_tools BEFORE DELETE ON public.tools FOR EACH ROW EXECUTE FUNCTION require_owner_for_hard_delete();
drop trigger if exists usage_adjustments_append_only on public.usage_adjustments;
CREATE TRIGGER usage_adjustments_append_only BEFORE DELETE OR UPDATE ON public.usage_adjustments FOR EACH ROW EXECUTE FUNCTION deny_admin_log_mutation();
drop trigger if exists bump_version_work_orders on public.work_orders;
CREATE TRIGGER bump_version_work_orders BEFORE UPDATE ON public.work_orders FOR EACH ROW EXECUTE FUNCTION bump_row_version();
drop trigger if exists commercial_write_guard_work_orders on public.work_orders;
CREATE TRIGGER commercial_write_guard_work_orders BEFORE INSERT OR DELETE OR UPDATE ON public.work_orders FOR EACH ROW EXECUTE FUNCTION require_commercial_write_access();
drop trigger if exists owner_hard_delete_work_orders on public.work_orders;
CREATE TRIGGER owner_hard_delete_work_orders BEFORE DELETE ON public.work_orders FOR EACH ROW EXECUTE FUNCTION require_owner_for_hard_delete();