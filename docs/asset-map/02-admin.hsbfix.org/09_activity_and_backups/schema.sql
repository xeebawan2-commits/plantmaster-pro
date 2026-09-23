-- ============================================================
-- Schema for this section (auto-extracted from the repo / live snapshot)
-- ============================================================


-- ---------- TABLES ----------


-- [admin_action_logs]  source: 05-tables-constraints-indexes.sql (LIVE snapshot)
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
