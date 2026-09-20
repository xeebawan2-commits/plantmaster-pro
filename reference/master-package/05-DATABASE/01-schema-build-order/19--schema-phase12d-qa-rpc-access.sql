-- PlantMaster QA Lab v1.2.3 — RPC-only browser access
-- Removes browser dependency on direct QA table privileges/RLS.

create or replace function public.control_qa_overview()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
 if not public.is_platform_admin() then raise exception 'Active platform administrator required';end if;
 select jsonb_build_object(
  'summary',jsonb_build_object(
   'environments',(select count(*) from qa_environments where status<>'deleted'),
   'ready',(select count(*) from qa_environments where status='ready'),
   'runs',(select count(*) from qa_test_runs),
   'passed_runs',(select count(*) from qa_test_runs where status='passed'),
   'failed_runs',(select count(*) from qa_test_runs where status in('failed','partial')),
   'latest_run',(select max(completed_at) from qa_test_runs)
  ),
  'environments',coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at desc) from qa_environments e),'[]'::jsonb),
  'runs',coalesce((select jsonb_agg(jsonb_build_object(
   'id',r.id,'environment_id',r.environment_id,'environment_name',e.name,'status',r.status,'include_ai',r.include_ai,
   'total_tests',r.total_tests,'passed',r.passed,'failed',r.failed,'blocked',r.blocked,
   'app_version',r.app_version,'runner_version',r.runner_version,'started_at',r.started_at,'completed_at',r.completed_at,'summary',r.summary
  ) order by r.started_at desc) from qa_test_runs r join qa_environments e on e.id=r.environment_id limit 30),'[]'::jsonb)
 ) into result;
 return result;
end $$;
grant execute on function public.control_qa_overview() to authenticated;

create or replace function public.control_qa_environment_runs(p_environment_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
 if not public.is_platform_admin() then raise exception 'Active platform administrator required';end if;
 if not exists(select 1 from qa_environments where id=p_environment_id) then raise exception 'QA environment not found';end if;
 select coalesce(jsonb_agg(to_jsonb(r) order by r.started_at desc),'[]'::jsonb) into result from qa_test_runs r where r.environment_id=p_environment_id;
 return result;
end $$;
grant execute on function public.control_qa_environment_runs(uuid) to authenticated;

create or replace function public.control_qa_run_detail(p_run_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
 if not public.is_platform_admin() then raise exception 'Active platform administrator required';end if;
 if not exists(select 1 from qa_test_runs where id=p_run_id) then raise exception 'QA run not found';end if;
 select jsonb_build_object(
  'run',to_jsonb(r)||jsonb_build_object('environment_name',e.name),
  'results',coalesce((select jsonb_agg(to_jsonb(x) order by x.category,x.id) from qa_test_results x where x.run_id=r.id),'[]'::jsonb),
  'manual',coalesce((select jsonb_agg(to_jsonb(m) order by m.category,m.check_name) from qa_manual_checks m where m.run_id=r.id),'[]'::jsonb)
 ) into result from qa_test_runs r join qa_environments e on e.id=r.environment_id where r.id=p_run_id;
 return result;
end $$;
grant execute on function public.control_qa_run_detail(uuid) to authenticated;
