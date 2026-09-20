-- ===========================================================================
-- PlantMaster Pro — 0009 edge function support
--
-- Adds the columns, tables and helpers the edge functions in
-- supabase/functions/ depend on. Every statement is idempotent so this can be
-- applied to the live database without disturbing existing rows.
--
--   * manuals.chunk_count / indexed_at   — ingest-manual progress reporting
--   * document_chunks.heading            — section title kept with each chunk
--   * daily_report_runs                  — makes daily-reports idempotent
--   * bump_push_failures()               — parks failing push subscriptions
--   * ai usage / chunk search indexes    — the functions' hot query paths
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. Manual indexing progress.
--    ingest-manual writes these back so the UI can show "indexed, 412 chunks"
--    instead of a spinner that never resolves.
-- ---------------------------------------------------------------------------
alter table public.manuals
  add column if not exists chunk_count int     not null default 0,
  add column if not exists indexed_at  timestamptz,
  add column if not exists removed_by  uuid references auth.users(id) on delete set null;

-- The status vocabulary the function writes must be the one the app reads.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.manuals'::regclass and conname = 'manuals_status_chk'
  ) then
    -- Normalise any legacy value first so the constraint can be trusted.
    update public.manuals
       set status = 'stored'
     where status is null
        or status not in ('stored','indexing','indexed','failed','deleted');

    alter table public.manuals
      add constraint manuals_status_chk
      check (status in ('stored','indexing','indexed','failed','deleted'));
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 2. Chunk headings. smart-responder cites "Section 4.2, page 51", which needs
--    the heading stored alongside the text.
-- ---------------------------------------------------------------------------
alter table public.document_chunks
  add column if not exists heading text;

-- Retrieval is an ILIKE scan over content scoped to one tenant. Without
-- pg_trgm that is a sequential scan of every chunk the company owns.
--
-- pg_trgm ships with Supabase but not with every Postgres build (the PGlite
-- harness used by `npm run verify:db` has no contrib modules), so this is
-- best-effort: if the extension cannot be installed the schema is still
-- correct, only the ILIKE path is slower.
do $$
begin
  begin
    create extension if not exists pg_trgm;
  exception when others then
    raise notice 'pg_trgm unavailable (%), skipping trigram index', sqlerrm;
  end;

  if exists (select 1 from pg_extension where extname = 'pg_trgm') then
    create index if not exists chunks_content_trgm_idx
      on public.document_chunks using gin (content gin_trgm_ops);
  end if;
end $$;

create index if not exists chunks_org_manual_idx
  on public.document_chunks(organization_id, manual_id, chunk_index);

-- ---------------------------------------------------------------------------
-- 3. Daily report run ledger.
--    The unique key is the whole point: a duplicate scheduler fire, a manual
--    re-run or a retry after a timeout cannot email a company twice.
-- ---------------------------------------------------------------------------
create table if not exists public.daily_report_runs (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  report_date     date not null,
  recipients      int  not null default 0,
  status          text not null default 'claimed',  -- claimed|sent|failed
  error           text,
  sent_at         timestamptz,
  created_at      timestamptz not null default now(),
  unique (organization_id, report_date)
);

create index if not exists daily_report_runs_date_idx
  on public.daily_report_runs(report_date desc);

alter table public.daily_report_runs enable row level security;

-- Owners and managers may see their own company's send history; nobody
-- writes to it from the client — only the service role does.
drop policy if exists daily_report_runs_read on public.daily_report_runs;
create policy daily_report_runs_read on public.daily_report_runs
  for select to authenticated
  using (public.has_org_role(organization_id, 'supervisor'));

revoke insert, update, delete on public.daily_report_runs from authenticated;

-- ---------------------------------------------------------------------------
-- 4. Push failure accounting.
--    A push endpoint that returns 500 once is not dead; one that fails
--    repeatedly is. Parking at 10 consecutive failures stops the poller
--    wasting its budget while preserving the row for diagnosis.
-- ---------------------------------------------------------------------------
create or replace function public.bump_push_failures(p_ids uuid[])
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  update public.push_subscriptions
     set failure_count = failure_count + 1,
         active        = (failure_count + 1) < 10,
         updated_at    = now()
   where id = any(p_ids);
$$;

revoke all on function public.bump_push_failures(uuid[]) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. AI usage accounting index.
--    guard.ts counts this month's rows on every single AI call, so the
--    (organization_id, created_at) path must be indexed.
-- ---------------------------------------------------------------------------
create index if not exists ai_usage_org_month_idx
  on public.ai_usage_events(organization_id, created_at desc);

create index if not exists ai_usage_fn_idx
  on public.ai_usage_events(organization_id, function_name, created_at desc);

-- Usage rows are written by the edge functions with the service key only.
revoke insert, update, delete on public.ai_usage_events from authenticated;

-- ---------------------------------------------------------------------------
-- 6. Notification delivery index for the poller's exact predicate.
-- ---------------------------------------------------------------------------
create index if not exists notif_pending_push_idx
  on public.notifications(created_at)
  where pushed_at is null and user_id is not null;

-- ---------------------------------------------------------------------------
-- 7. Condition baseline lookup used by condition-analyzer.
-- ---------------------------------------------------------------------------
create index if not exists condition_baseline_idx
  on public.condition_recordings(organization_id, asset_id, recording_type)
  where is_baseline and removed_at is null;

create index if not exists condition_recent_idx
  on public.condition_recordings(organization_id, asset_id, recording_type, created_at desc)
  where removed_at is null;
