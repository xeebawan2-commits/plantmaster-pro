-- PlantMaster Control Center v1.2 — QA Lab
-- Additive/idempotent. Requires schemas through Phase 11c.

create table if not exists public.qa_environments(
 id uuid primary key default gen_random_uuid(),
 name text not null unique,
 organization_id uuid references public.organizations(id) on delete set null,
 plant_id uuid references public.plants(id) on delete set null,
 isolation_organization_id uuid references public.organizations(id) on delete set null,
 status text not null default 'creating' check(status in('creating','ready','testing','failed','deleting','deleted')),
 user_ids jsonb not null default '{}'::jsonb,
 seed_summary jsonb not null default '{}'::jsonb,
 last_error text,
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 deleted_at timestamptz
);
create table if not exists public.qa_test_runs(
 id uuid primary key default gen_random_uuid(),environment_id uuid not null references public.qa_environments(id) on delete cascade,
 status text not null default 'running' check(status in('running','passed','failed','partial','cancelled')),
 include_ai boolean not null default false,total_tests integer not null default 0,passed integer not null default 0,failed integer not null default 0,blocked integer not null default 0,
 app_version text,runner_version text not null default '1.0.0',started_by uuid not null references auth.users(id),started_at timestamptz not null default now(),completed_at timestamptz,summary jsonb not null default '{}'::jsonb
);
create table if not exists public.qa_test_results(
 id bigint generated always as identity primary key,run_id uuid not null references public.qa_test_runs(id) on delete cascade,
 category text not null,test_name text not null,status text not null check(status in('passed','failed','blocked','manual_required')),
 expected text,actual text,error text,duration_ms integer,evidence jsonb not null default '{}'::jsonb,created_at timestamptz not null default now()
);
create index if not exists qa_results_run_status_idx on public.qa_test_results(run_id,status,category);
create table if not exists public.qa_manual_checks(
 id uuid primary key default gen_random_uuid(),run_id uuid not null references public.qa_test_runs(id) on delete cascade,
 category text not null,check_name text not null,instructions text not null,status text not null default 'pending' check(status in('pending','passed','failed','not_available')),
 result_notes text,tested_by uuid references auth.users(id),tested_at timestamptz
);

alter table public.qa_environments enable row level security;alter table public.qa_test_runs enable row level security;alter table public.qa_test_results enable row level security;alter table public.qa_manual_checks enable row level security;
do $$ begin
 if not exists(select 1 from pg_policies where tablename='qa_environments' and policyname='platform qa environment access') then create policy "platform qa environment access" on public.qa_environments for all to authenticated using(public.platform_has_permission('qa.manage')) with check(public.platform_has_permission('qa.manage'));end if;
 if not exists(select 1 from pg_policies where tablename='qa_test_runs' and policyname='platform qa run access') then create policy "platform qa run access" on public.qa_test_runs for all to authenticated using(public.platform_has_permission('qa.manage')) with check(public.platform_has_permission('qa.manage'));end if;
 if not exists(select 1 from pg_policies where tablename='qa_test_results' and policyname='platform qa result access') then create policy "platform qa result access" on public.qa_test_results for all to authenticated using(public.platform_has_permission('qa.manage')) with check(public.platform_has_permission('qa.manage'));end if;
 if not exists(select 1 from pg_policies where tablename='qa_manual_checks' and policyname='platform qa manual access') then create policy "platform qa manual access" on public.qa_manual_checks for all to authenticated using(public.platform_has_permission('qa.manage')) with check(public.platform_has_permission('qa.manage'));end if;
end $$;
grant select,insert,update,delete on public.qa_environments,public.qa_test_runs,public.qa_test_results,public.qa_manual_checks to authenticated;grant usage,select on all sequences in schema public to authenticated;

-- Trusted service-role cleanup is required for isolated QA tenants; customer hard
-- deletes remain owner-only.
create or replace function public.require_owner_for_hard_delete()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')='service_role' then return old;end if;
 if public.org_role(old.organization_id)<>'owner' then raise exception 'Only the company owner can permanently erase records';end if;
 return old;
end$$;

-- Add QA permission to current super administrators implicitly through platform_has_permission.
-- Non-super administrators require explicit {"qa.manage":true}.

create or replace function public.control_qa_summary() returns jsonb language plpgsql stable security definer set search_path=public as $$declare result jsonb;begin
 if not public.platform_has_permission('qa.manage') then raise exception 'QA permission required';end if;
 select jsonb_build_object('environments',(select count(*) from qa_environments where status<>'deleted'),'ready',(select count(*) from qa_environments where status='ready'),'runs',(select count(*) from qa_test_runs),'passed_runs',(select count(*) from qa_test_runs where status='passed'),'failed_runs',(select count(*) from qa_test_runs where status in('failed','partial')),'latest_run',(select max(completed_at) from qa_test_runs)) into result;return result;end$$;
grant execute on function public.control_qa_summary() to authenticated;

-- Manual check result recording with administrator identity.
create or replace function public.control_update_manual_check(p_check_id uuid,p_status text,p_notes text default null) returns void language plpgsql security definer set search_path=public as $$begin
 if not public.platform_has_permission('qa.manage') then raise exception 'QA permission required';end if;if p_status not in('pending','passed','failed','not_available') then raise exception 'Invalid status';end if;update qa_manual_checks set status=p_status,result_notes=p_notes,tested_by=auth.uid(),tested_at=case when p_status='pending' then null else now() end where id=p_check_id;end$$;
grant execute on function public.control_update_manual_check(uuid,text,text) to authenticated;
