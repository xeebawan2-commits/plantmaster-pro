-- ============================================================
-- Schema for this section (auto-extracted from the repo / live snapshot)
-- ============================================================


-- ---------- TABLES ----------


-- [platform_support_tickets]  source: 05-tables-constraints-indexes.sql (LIVE snapshot)
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


-- [platform_support_messages]  source: 05-tables-constraints-indexes.sql (LIVE snapshot)
create table if not exists public.platform_support_messages (
  id uuid default gen_random_uuid() not null,
  ticket_id uuid not null,
  user_id uuid not null,
  message text not null,
  internal boolean default false not null,
  attachment_path text,
  created_at timestamptz default now() not null
);
