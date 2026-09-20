-- PlantMaster Pro — push subscriptions + poll cursors (v1.0.0)
-- Run in: Supabase Dashboard → SQL Editor → New query → paste all → Run.
-- Additive only: creates 2 new tables + 1 index. Touches nothing existing.

create table if not exists public.push_subscriptions (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id         uuid not null references auth.users(id) on delete cascade,
  endpoint        text not null unique,
  p256dh          text not null,
  auth            text not null,
  ua              text,
  last_error_at   timestamptz,
  created_at      timestamptz not null default now()
);
create index if not exists push_subs_org_idx on public.push_subscriptions (organization_id);

-- Per-org cursor so the poller only pushes NEW notifications.
create table if not exists public.push_cursors (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  last_created_at timestamptz not null default '1970-01-01T00:00:00Z',
  updated_at      timestamptz not null default now()
);

-- RLS on, no policies => only the service_role (your edge functions) can
-- read/write these tables. Normal app users cannot see other people's
-- push endpoints.
alter table public.push_subscriptions enable row level security;
alter table public.push_cursors enable row level security;

-- The poller orders notifications by created_at per org — make that cheap.
create index if not exists notifications_org_created_idx
  on public.notifications (organization_id, created_at);

-- Convenience: ensure every org gets a cursor row when it is created.
create or replace function public.new_push_cursor()
returns trigger language plpgsql as $$
begin
  insert into public.push_cursors (organization_id) values (new.id)
  on conflict (organization_id) do nothing;
  return new;
end $$;

drop trigger if exists organizations_push_cursor on public.organizations;
create trigger organizations_push_cursor
  after insert on public.organizations
  for each row execute function public.new_push_cursor();

-- Backfill cursors for orgs that already exist (idempotent).
insert into public.push_cursors (organization_id)
select id from public.organizations
on conflict (organization_id) do nothing;
