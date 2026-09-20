-- PlantMaster QA Lab v1.2.1 — active platform-admin compatibility fix
-- Additive/idempotent. Does not change customer or QA data.

-- Add a permissive QA policy for any active registered platform administrator.
-- PostgreSQL combines policies with OR, while ordinary owners/workers still fail
-- is_platform_admin() and remain blocked.
do $$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='qa_environments' and policyname='active platform admin qa environments') then
   create policy "active platform admin qa environments" on public.qa_environments for all to authenticated using(public.is_platform_admin()) with check(public.is_platform_admin());
 end if;
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='qa_test_runs' and policyname='active platform admin qa runs') then
   create policy "active platform admin qa runs" on public.qa_test_runs for all to authenticated using(public.is_platform_admin()) with check(public.is_platform_admin());
 end if;
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='qa_test_results' and policyname='active platform admin qa results') then
   create policy "active platform admin qa results" on public.qa_test_results for all to authenticated using(public.is_platform_admin()) with check(public.is_platform_admin());
 end if;
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='qa_manual_checks' and policyname='active platform admin qa manual checks') then
   create policy "active platform admin qa manual checks" on public.qa_manual_checks for all to authenticated using(public.is_platform_admin()) with check(public.is_platform_admin());
 end if;
end $$;

create or replace function public.control_qa_summary()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
 if not public.is_platform_admin() then raise exception 'Active platform administrator required';end if;
 select jsonb_build_object(
   'environments',(select count(*) from qa_environments where status<>'deleted'),
   'ready',(select count(*) from qa_environments where status='ready'),
   'runs',(select count(*) from qa_test_runs),
   'passed_runs',(select count(*) from qa_test_runs where status='passed'),
   'failed_runs',(select count(*) from qa_test_runs where status in('failed','partial')),
   'latest_run',(select max(completed_at) from qa_test_runs)
 ) into result;
 return result;
end $$;
grant execute on function public.control_qa_summary() to authenticated;

create or replace function public.control_update_manual_check(p_check_id uuid,p_status text,p_notes text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_platform_admin() then raise exception 'Active platform administrator required';end if;
 if p_status not in('pending','passed','failed','not_available') then raise exception 'Invalid status';end if;
 update qa_manual_checks set status=p_status,result_notes=p_notes,tested_by=auth.uid(),tested_at=case when p_status='pending' then null else now() end where id=p_check_id;
end $$;
grant execute on function public.control_update_manual_check(uuid,text,text) to authenticated;
