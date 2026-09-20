-- PlantMaster Control Center v1.2.2 — consolidated permission repair
-- Idempotent. Restores platform super-admin access without granting customer access.

create or replace function public.is_platform_admin()
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.platform_admins a where a.user_id=auth.uid() and a.active)
$$;
create or replace function public.is_super_platform_admin()
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.platform_admins a where a.user_id=auth.uid() and a.active and a.admin_role='super_admin')
$$;
create or replace function public.platform_has_permission(p_permission text)
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.platform_admins a where a.user_id=auth.uid() and a.active and (a.admin_role='super_admin' or coalesce((a.permissions->>p_permission)::boolean,false)))
$$;
grant execute on function public.is_platform_admin() to authenticated;
grant execute on function public.is_super_platform_admin() to authenticated;
grant execute on function public.platform_has_permission(text) to authenticated;

-- Restore SQL privileges. RLS policies below still decide which authenticated
-- accounts can access rows.
grant select,insert,update,delete on public.platform_admins to authenticated;
grant select,insert,update,delete on public.complimentary_access,public.quota_overrides,public.platform_support_tickets,public.platform_support_messages,public.backup_jobs,public.restore_drills,public.platform_notifications,public.company_feature_blocks to authenticated;
grant select,insert on public.usage_adjustments,public.admin_action_logs to authenticated;
grant select on public.system_incidents,public.usage_counters,public.usage_events,public.storage_usage_events,public.ai_usage,public.organization_subscriptions,public.subscription_plans to authenticated;
grant select,insert,update,delete on public.legal_documents,public.legal_acceptances,public.data_retention_policies,public.deletion_requests to authenticated;
grant select,insert,update,delete on public.qa_environments,public.qa_test_runs,public.qa_test_results,public.qa_manual_checks to authenticated;
grant usage,select on all sequences in schema public to authenticated;

-- A super administrator receives a second permissive RLS policy. PostgreSQL
-- combines permissive policies with OR. Normal owners/workers fail
-- is_super_platform_admin() and receive no platform access from these policies.
do $$
declare t text;policy_name text;
begin
 foreach t in array array[
  'platform_admins','complimentary_access','quota_overrides','platform_support_tickets','platform_support_messages',
  'backup_jobs','restore_drills','platform_notifications','company_feature_blocks','legal_documents','legal_acceptances',
  'data_retention_policies','deletion_requests','qa_environments','qa_test_runs','qa_test_results','qa_manual_checks'
 ] loop
  if to_regclass('public.'||t) is not null then
   policy_name:='super admin full access '||t;
   if not exists(select 1 from pg_policies where schemaname='public' and tablename=t and policyname=policy_name) then
    execute format('create policy %I on public.%I for all to authenticated using(public.is_super_platform_admin()) with check(public.is_super_platform_admin())',policy_name,t);
   end if;
  end if;
 end loop;
 foreach t in array array['admin_action_logs','usage_adjustments','usage_counters','usage_events','storage_usage_events','ai_usage','organization_subscriptions','subscription_plans','system_incidents'] loop
  if to_regclass('public.'||t) is not null then
   policy_name:='super admin read access '||t;
   if not exists(select 1 from pg_policies where schemaname='public' and tablename=t and policyname=policy_name) then
    execute format('create policy %I on public.%I for select to authenticated using(public.is_super_platform_admin())',policy_name,t);
   end if;
  end if;
 end loop;
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='admin_action_logs' and policyname='super admin inserts audit') then
  create policy "super admin inserts audit" on public.admin_action_logs for insert to authenticated with check(public.is_super_platform_admin());
 end if;
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='usage_adjustments' and policyname='super admin inserts usage adjustments') then
  create policy "super admin inserts usage adjustments" on public.usage_adjustments for insert to authenticated with check(public.is_super_platform_admin());
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
