-- =============================================================
-- PlantMaster Pro — push setup fix (v9.1)
-- Paste ALL of this into: Supabase → SQL Editor → New query → Run
-- Idempotent: safe to run even if parts already exist.
-- =============================================================

-- 1) THE SILENT KILLER: the push poller reads notifications.severity.
--    The column never existed, so every poll failed quietly and no
--    push was ever sent. Fix it here (adds nothing if it exists).
alter table public.notifications add column if not exists severity text default 'normal';

-- 2) Push subscription + cursor tables (no-ops if you already ran them).
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

create table if not exists public.push_cursors (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  last_created_at timestamptz not null default '1970-01-01T00:00:00Z',
  updated_at      timestamptz not null default now()
);

alter table public.push_subscriptions enable row level security;
alter table public.push_cursors enable row level security;

create index if not exists notifications_org_created_idx
  on public.notifications (organization_id, created_at);

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

insert into public.push_cursors (organization_id)
select id from public.organizations
on conflict (organization_id) do nothing;

-- 3) Cursor reset: only notifications created AFTER this moment get pushed
--    (prevents a one-time burst of old alerts on the very first poll).
update public.push_cursors set last_created_at = now() where last_created_at < '2000-01-01';
