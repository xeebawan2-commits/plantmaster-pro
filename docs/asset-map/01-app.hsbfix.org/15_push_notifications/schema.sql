-- ============================================================
-- Schema for this section (auto-extracted from the repo / live snapshot)
-- ============================================================


-- ---------- TABLES ----------


-- [notifications]  source: 0004_knowledge_files.sql
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
