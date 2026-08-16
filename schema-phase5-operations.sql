-- PlantMaster Pro v4.4 Operations migration
-- Additive/idempotent: preserves all existing organizations, plants, users and records.

create extension if not exists pgcrypto;

-- Worker identity and employment details.
alter table public.profiles add column if not exists employee_id text;
alter table public.profiles add column if not exists designation text;
alter table public.profiles add column if not exists skills text[] not null default '{}';
alter table public.profiles add column if not exists contact text;
alter table public.profiles add column if not exists default_shift text default 'General Shift';
alter table public.profiles add column if not exists updated_at timestamptz not null default now();

alter table public.organization_members add column if not exists permissions jsonb not null default '{}'::jsonb;
alter table public.organization_members add column if not exists deactivated_at timestamptz;
alter table public.organization_members add column if not exists updated_at timestamptz not null default now();
alter table public.invitations add column if not exists worker_details jsonb not null default '{}'::jsonb;

-- Organization members may see co-worker directory fields; only the owner may edit another worker.
do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='profiles' and policyname='members read coworker profiles') then
    create policy "members read coworker profiles" on public.profiles for select to authenticated
      using(exists(select 1 from public.organization_members target
                   where target.user_id=profiles.id and public.is_org_member(target.organization_id)));
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='profiles' and policyname='owner updates coworker profiles') then
    create policy "owner updates coworker profiles" on public.profiles for update to authenticated
      using(exists(select 1 from public.organization_members target
                   where target.user_id=profiles.id and public.org_role(target.organization_id)='owner'))
      with check(exists(select 1 from public.organization_members target
                   where target.user_id=profiles.id and public.org_role(target.organization_id)='owner'));
  end if;
end $$;

-- Recovery metadata. Existing rows remain active.
do $$
declare t text;
begin
  foreach t in array array['assets','work_orders','file_metadata','checklist_templates','maintenance_plans','spares','tools'] loop
    execute format('alter table public.%I add column if not exists removed_at timestamptz',t);
    execute format('alter table public.%I add column if not exists removed_by uuid references auth.users(id)',t);
  end loop;
end $$;

-- Rich operational completion data.
alter table public.work_orders add column if not exists work_done text;
alter table public.work_orders add column if not exists designation text;
alter table public.work_orders add column if not exists shift_name text;
alter table public.work_orders add column if not exists tools_used text;
alter table public.work_orders add column if not exists parts_used text;
alter table public.work_orders add column if not exists measurements jsonb not null default '{}'::jsonb;
alter table public.work_orders add column if not exists root_cause text;
alter table public.work_orders add column if not exists corrective_action text;
alter table public.work_orders add column if not exists downtime_minutes integer;
alter table public.work_orders add column if not exists completed_by uuid references auth.users(id);
alter table public.work_orders add column if not exists completed_at timestamptz;
alter table public.work_orders add column if not exists supervisor_approved_by uuid references auth.users(id);
alter table public.work_orders add column if not exists supervisor_approved_at timestamptz;
alter table public.work_orders add column if not exists signature_data text;

alter table public.checklist_runs add column if not exists designation text;
alter table public.checklist_runs add column if not exists completed_at timestamptz;
alter table public.checklist_runs add column if not exists supervisor_approved_by uuid references auth.users(id);
alter table public.checklist_runs add column if not exists supervisor_approved_at timestamptz;
alter table public.checklist_runs add column if not exists signature_data text;
alter table public.checklist_values add column if not exists failed boolean not null default false;
alter table public.checklist_values add column if not exists note text;

alter table public.maintenance_plans add column if not exists last_completed_at timestamptz;
alter table public.maintenance_plans add column if not exists last_completed_by uuid references auth.users(id);

create table if not exists public.maintenance_completions(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id uuid not null references public.plants(id) on delete cascade,
  plan_id uuid not null references public.maintenance_plans(id) on delete cascade,
  work_done text not null,
  worker_id uuid not null references auth.users(id),
  worker_name text not null,
  designation text,
  shift_name text not null,
  tools_used text,
  parts_used text,
  measurements jsonb not null default '{}'::jsonb,
  root_cause text,
  corrective_action text,
  downtime_minutes integer,
  signature_data text,
  completed_at timestamptz not null default now(),
  supervisor_approved_by uuid references auth.users(id),
  supervisor_approved_at timestamptz
);

create table if not exists public.shift_handovers(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id uuid not null references public.plants(id) on delete cascade,
  work_date date not null default current_date,
  from_shift text not null,
  to_shift text not null,
  summary text not null,
  pending_work text,
  safety_notes text,
  created_by uuid not null references auth.users(id),
  worker_name text not null,
  designation text,
  created_at timestamptz not null default now()
);

create table if not exists public.daily_logs(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id uuid not null references public.plants(id) on delete cascade,
  log_date date not null default current_date,
  shift_name text not null,
  category text not null default 'operations',
  entry text not null,
  created_by uuid not null references auth.users(id),
  worker_name text not null,
  designation text,
  created_at timestamptz not null default now()
);

create table if not exists public.tool_transactions(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id uuid not null references public.plants(id) on delete cascade,
  tool_id uuid not null references public.tools(id) on delete cascade,
  transaction_type text not null check(transaction_type in ('checkout','return','calibration','inspection')),
  holder_id uuid references auth.users(id),
  condition text,
  notes text,
  performed_by uuid not null references auth.users(id),
  worker_name text not null,
  designation text,
  shift_name text,
  created_at timestamptz not null default now()
);

create table if not exists public.action_attachments(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id uuid references public.plants(id) on delete cascade,
  entity_type text not null,
  entity_id uuid not null,
  file_metadata_id uuid not null references public.file_metadata(id) on delete cascade,
  uploaded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

alter table public.organization_settings add column if not exists report_recipients text[] not null default '{}';
alter table public.organization_settings add column if not exists report_approval_required boolean not null default true;
alter table public.organization_settings add column if not exists letterhead_path text;
alter table public.organization_settings add column if not exists signatories jsonb not null default '[]'::jsonb;

-- Tenant RLS for new operational tables.
do $$
declare t text;
begin
  foreach t in array array['maintenance_completions','shift_handovers','daily_logs','tool_transactions','action_attachments'] loop
    execute format('alter table public.%I enable row level security',t);
    if not exists(select 1 from pg_policies where schemaname='public' and tablename=t and policyname=t||'_member') then
      execute format('create policy %I on public.%I for all to authenticated using(public.is_org_member(organization_id)) with check(public.is_org_member(organization_id))',t||'_member',t);
    end if;
  end loop;
end $$;

grant select,insert,update,delete on public.maintenance_completions,public.shift_handovers,public.daily_logs,public.tool_transactions,public.action_attachments to authenticated;
grant usage,select on all sequences in schema public to authenticated;

-- Owner-only member administration. Existing read policy remains intact.
do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='organization_members' and policyname='owner manages members') then
    create policy "owner manages members" on public.organization_members
      for update to authenticated
      using(public.org_role(organization_id)='owner')
      with check(public.org_role(organization_id)='owner');
  end if;
end $$;

-- Hard deletes are an owner-only last resort. Normal UI actions use removed_at recovery.
create or replace function public.require_owner_for_hard_delete()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if public.org_role(old.organization_id) <> 'owner' then
    raise exception 'Only the company owner can permanently erase records';
  end if;
  return old;
end $$;

do $$
declare t text; trigger_name text;
begin
  foreach t in array array['assets','work_orders','file_metadata','checklist_templates','maintenance_plans','spares','tools'] loop
    trigger_name := 'owner_hard_delete_'||t;
    if not exists(select 1 from pg_trigger where tgname=trigger_name and not tgisinternal) then
      execute format('create trigger %I before delete on public.%I for each row execute function public.require_owner_for_hard_delete()',trigger_name,t);
    end if;
  end loop;
end $$;

create index if not exists handovers_plant_date_idx on public.shift_handovers(plant_id,work_date desc);
create index if not exists daily_logs_plant_date_idx on public.daily_logs(plant_id,log_date desc);
create index if not exists maintenance_completion_plan_idx on public.maintenance_completions(plan_id,completed_at desc);
create index if not exists tool_transactions_tool_idx on public.tool_transactions(tool_id,created_at desc);

-- Secure invitation acceptance: called by the signed-in invited worker.
create or replace function public.accept_invitation(invite_token uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare
  inv public.invitations%rowtype;
  token_email text;
  skill_list text[];
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into inv from public.invitations where token=invite_token for update;
  if not found then raise exception 'Invitation not found'; end if;
  if inv.accepted_at is not null then raise exception 'Invitation has already been accepted'; end if;
  if inv.expires_at < now() then raise exception 'Invitation has expired'; end if;
  token_email := lower(coalesce(auth.jwt()->>'email',''));
  if inv.email is not null and inv.email <> '' and lower(inv.email) <> token_email then
    raise exception 'Sign in with the invited email address';
  end if;
  insert into public.organization_members(organization_id,user_id,role,active)
    values(inv.organization_id,auth.uid(),inv.role,true)
    on conflict(organization_id,user_id) do update set role=excluded.role,active=true,deactivated_at=null,updated_at=now();
  if inv.plant_id is not null then
    insert into public.plant_members(plant_id,user_id) values(inv.plant_id,auth.uid()) on conflict do nothing;
  end if;
  if jsonb_typeof(inv.worker_details->'skills')='array' then
    select coalesce(array_agg(v),'{}') into skill_list from jsonb_array_elements_text(inv.worker_details->'skills') v;
  else skill_list := '{}'; end if;
  update public.profiles set
    full_name=coalesce(nullif(inv.worker_details->>'full_name',''),full_name),
    employee_id=coalesce(nullif(inv.worker_details->>'employee_id',''),employee_id),
    designation=coalesce(nullif(inv.worker_details->>'designation',''),designation),
    contact=coalesce(nullif(inv.worker_details->>'contact',''),contact),
    default_shift=coalesce(nullif(inv.worker_details->>'default_shift',''),default_shift),
    skills=case when cardinality(skill_list)>0 then skill_list else skills end,
    updated_at=now()
  where id=auth.uid();
  update public.invitations set accepted_at=now() where id=inv.id;
  insert into public.audit_logs(organization_id,plant_id,user_id,action,entity_type,entity_id,details)
    values(inv.organization_id,inv.plant_id,auth.uid(),'invitation_accepted','invitation',inv.id::text,jsonb_build_object('role',inv.role,'timestamp',now()));
  return inv.organization_id;
end $$;
grant execute on function public.accept_invitation(uuid) to authenticated;
