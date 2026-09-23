-- ============================================================
-- Schema for this section (auto-extracted from the repo / live snapshot)
-- ============================================================


-- ---------- TABLES ----------


-- [signup_requests]  source: R2-control-center.sql
create table if not exists public.signup_requests (
  id             uuid primary key default gen_random_uuid(),
  company_name   text not null,
  contact_name   text not null,
  email          text not null,
  phone          text,
  city           text,
  plant_type     text,
  team_size      text,
  plan_interest  text,
  message        text,
  source         text default 'website',
  status         text not null default 'new'
                 check (status in ('new','contacted','approved','rejected','spam')),
  reviewed_by    uuid references auth.users(id),
  reviewed_at    timestamptz,
  review_notes   text,
  created_at     timestamptz not null default now()
);
