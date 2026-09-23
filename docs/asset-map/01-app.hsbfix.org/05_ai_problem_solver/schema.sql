-- ============================================================
-- Schema for this section (auto-extracted from the repo / live snapshot)
-- ============================================================


-- ---------- TABLES ----------


-- [problem_cases]  source: 0004_knowledge_files.sql
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


-- [manuals]  source: 0004_knowledge_files.sql
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


-- [document_chunks]  source: 0004_knowledge_files.sql
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


-- [technical_experiences]  source: 0004_knowledge_files.sql
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
