-- ============================================================
-- Schema for this section (auto-extracted from the repo / live snapshot)
-- ============================================================


-- ---------- TABLES ----------


-- [support_threads]  source: 0005_platform_commercial.sql
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


-- [support_messages]  source: 0005_platform_commercial.sql
create table if not exists public.support_messages (
  id          uuid primary key default gen_random_uuid(),
  thread_id   uuid not null references public.support_threads(id) on delete cascade,
  user_id     uuid references auth.users(id) on delete set null,
  message     text not null,
  attachment_path text,
  created_at  timestamptz not null default now()
);


-- [system_incidents]  source: 0005_platform_commercial.sql
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



-- ---------- FUNCTIONS / RPCs ----------


-- [submit_app_complaint()]  source: 0006_rpc.sql
create or replace function public.submit_app_complaint(
  p_organization_id uuid,
  p_category        text,
  p_priority        text,
  p_subject         text,
  p_description     text,
  p_app_version     text default null,
  p_device_info     jsonb default '{}'::jsonb
) returns public.app_complaints
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare t public.app_complaints;
begin
  if not public.is_org_owner(p_organization_id) then
    raise exception 'Only the workspace owner can raise a platform complaint'
      using errcode = '42501';
  end if;
  insert into public.app_complaints
    (organization_id, category, priority, subject, description,
     app_version, device_info, created_by)
  values (p_organization_id, coalesce(p_category,'application'),
          coalesce(p_priority,'medium'), p_subject, p_description,
          p_app_version, coalesce(p_device_info,'{}'::jsonb), auth.uid())
  returning * into t;
  return t;
end $$;


-- [reply_app_complaint()]  source: 0006_rpc.sql
create or replace function public.reply_app_complaint(
  p_ticket_id uuid,
  p_message   text
) returns public.app_complaint_messages
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c public.app_complaints;
  m public.app_complaint_messages;
  staff boolean := public.is_platform_admin();
begin
  select * into c from public.app_complaints where id = p_ticket_id;
  if not found then
    raise exception 'Ticket not found' using errcode = 'P0002';
  end if;
  if not (staff or public.is_org_owner(c.organization_id)) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  insert into public.app_complaint_messages (ticket_id, user_id, message, is_staff)
  values (p_ticket_id, auth.uid(), p_message, staff)
  returning * into m;

  update public.app_complaints
     set updated_at = now(),
         status = case when staff and status = 'open' then 'in_progress' else status end
   where id = p_ticket_id;

  return m;
end $$;


-- [owner_app_complaints()]  source: 0006_rpc.sql
create or replace function public.owner_app_complaints(p_organization_id uuid)
returns setof public.app_complaints
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select c.* from public.app_complaints c
   where c.organization_id = p_organization_id
     and (public.is_org_owner(p_organization_id) or public.is_platform_admin())
   order by c.updated_at desc;
$$;


-- [owner_app_complaint_messages()]  source: 0006_rpc.sql
create or replace function public.owner_app_complaint_messages(p_ticket_id uuid)
returns setof public.app_complaint_messages
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select m.* from public.app_complaint_messages m
   join public.app_complaints c on c.id = m.ticket_id
  where m.ticket_id = p_ticket_id
    and (public.is_org_owner(c.organization_id) or public.is_platform_admin())
  order by m.created_at;
$$;
