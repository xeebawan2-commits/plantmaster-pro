-- PlantMaster Pro — all database functions
-- Reconstructed from pg_get_functiondef on 2026-09-13
-- 73 functions (excluding 114 C/internal extension functions)

-- ============================================================
-- accept_invitation
-- ============================================================
CREATE OR REPLACE FUNCTION public.accept_invitation(invite_token uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

-- ============================================================
-- accept_legal_document
-- ============================================================
CREATE OR REPLACE FUNCTION public.accept_legal_document(p_document_id uuid, p_organization_id uuid, p_locale text DEFAULT NULL::text, p_user_agent_hash text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null or (not public.is_org_member(p_organization_id) and not public.is_platform_admin()) then raise exception 'Access denied';end if;
  if not exists(select 1 from public.legal_documents where id=p_document_id and active and effective_at<=now()) then raise exception 'Legal document not available';end if;
  insert into public.legal_acceptances(document_id,organization_id,user_id,locale,user_agent_hash) values(p_document_id,p_organization_id,auth.uid(),p_locale,p_user_agent_hash) on conflict(document_id,user_id) do nothing;
end $function$;

-- ============================================================
-- bump_row_version
-- ============================================================
CREATE OR REPLACE FUNCTION public.bump_row_version()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$ begin new.row_version=coalesce(old.row_version,0)+1;return new;end $function$;

-- ============================================================
-- cancel_storage_reservation
-- ============================================================
CREATE OR REPLACE FUNCTION public.cancel_storage_reservation(p_reservation_id uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  update public.storage_reservations set status='cancelled' where id=p_reservation_id and user_id=auth.uid() and status='reserved'
$function$;

-- ============================================================
-- company_feature_allowed
-- ============================================================
CREATE OR REPLACE FUNCTION public.company_feature_allowed(p_organization_id uuid, p_feature text, p_plan_default boolean)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$select case when exists(select 1 from company_feature_blocks where organization_id=p_organization_id and feature=p_feature and blocked and (expires_at is null or expires_at>now())) then false else p_plan_default end$function$;

-- ============================================================
-- control_accounts
-- ============================================================
CREATE OR REPLACE FUNCTION public.control_accounts(p_search text DEFAULT NULL::text)
 RETURNS TABLE(user_id uuid, email text, full_name text, created_at timestamp with time zone, last_sign_in_at timestamp with time zone, banned_until timestamp with time zone, memberships bigint, companies jsonb, owner_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 if not public.platform_has_permission('accounts.view') then
  raise exception 'Permission required';
 end if;

 return query
 select
  u.id::uuid as user_id,
  coalesce(u.email,'')::text as email,
  coalesce(p.full_name,'')::text as full_name,
  u.created_at::timestamptz as created_at,
  u.last_sign_in_at::timestamptz as last_sign_in_at,
  u.banned_until::timestamptz as banned_until,
  (select count(*)::bigint from public.organization_members m where m.user_id=u.id) as memberships,
  coalesce((
   select jsonb_agg(jsonb_build_object(
    'organization_id',o.id,
    'company',o.name,
    'role',m.role,
    'active',m.active
   ) order by o.name)
   from public.organization_members m
   join public.organizations o on o.id=m.organization_id
   where m.user_id=u.id
  ),'[]'::jsonb) as companies,
  (select count(*)::bigint from public.organization_members m where m.user_id=u.id and m.role='owner' and m.active) as owner_count
 from auth.users u
 left join public.profiles p on p.id=u.id
 where p_search is null
    or coalesce(u.email,'')::text ilike '%'||p_search||'%'
    or coalesce(p.full_name,'')::text ilike '%'||p_search||'%'
 order by u.created_at desc
 limit 500;
end $function$;

-- ============================================================
-- control_adjust_usage
-- ============================================================
CREATE OR REPLACE FUNCTION public.control_adjust_usage(p_organization_id uuid, p_metric text, p_quantity bigint, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$declare ps date:=date_trunc('month',current_date)::date;pe date:=(date_trunc('month',current_date)+interval '1 month'-interval '1 day')::date;begin
 if not public.platform_has_permission('usage.manage') then raise exception 'Permission required';end if;
 insert into usage_adjustments(organization_id,metric,period_start,quantity,reason,created_by) values(p_organization_id,p_metric,ps,p_quantity,p_reason,auth.uid());insert into usage_counters(organization_id,metric,period_start,period_end,quantity) values(p_organization_id,p_metric,ps,pe,greatest(0,p_quantity)) on conflict(organization_id,metric,period_start) do update set quantity=greatest(0,usage_counters.quantity+p_quantity),updated_at=now();
 insert into admin_action_logs(admin_user_id,action,target_type,target_id,organization_id,reason,details) values(auth.uid(),'usage_adjusted','usage',p_metric,p_organization_id,p_reason,jsonb_build_object('quantity',p_quantity,'period_start',ps));end$function$;

-- ============================================================
-- control_admins
-- ============================================================
CREATE OR REPLACE FUNCTION public.control_admins()
 RETURNS TABLE(user_id uuid, email text, full_name text, admin_role text, active boolean, permissions jsonb, created_at timestamp with time zone, last_login_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$begin if not public.platform_has_permission('admins.manage') then raise exception 'Permission required';end if;return query select a.user_id,u.email,coalesce(a.display_name,p.full_name),a.admin_role,a.active,a.permissions,a.created_at,a.last_login_at from platform_admins a join auth.users u on u.id=a.user_id left join profiles p on p.id=a.user_id order by a.created_at;end$function$;

-- ============================================================
-- control_ai_usage
-- ============================================================
CREATE OR REPLACE FUNCTION public.control_ai_usage(p_organization_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(organization_id uuid, company text, user_id uuid, user_name text, provider text, model text, mode text, status text, input_tokens integer, output_tokens integer, latency_ms integer, error_code text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$begin
 if not public.platform_has_permission('ai.view') then raise exception 'Permission required';end if;
 return query select a.organization_id,o.name,a.user_id,p.full_name,a.provider,a.model,a.mode,a.status,a.input_tokens,a.output_tokens,a.latency_ms,a.error_code,a.created_at from ai_usage a join organizations o on o.id=a.organization_id left join profiles p on p.id=a.user_id where (p_organization_id is null or a.organization_id=p_organization_id) order by a.created_at desc limit 2000;end$function$;

-- ============================================================
-- control_companies
-- ============================================================
CREATE OR REPLACE FUNCTION public.control_companies(p_search text DEFAULT NULL::text, p_status text DEFAULT NULL::text)
 RETURNS TABLE(organization_id uuid, name text, status text, status_reason text, created_at timestamp with time zone, plan_code text, plan_name text, subscription_status text, period_end timestamp with time zone, workers bigint, owners bigint, plants bigint, files bigint, storage_bytes numeric, bandwidth_month bigint, ai_requests_month bigint, open_tickets bigint, open_incidents bigint, access_type text, complimentary_ends_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$begin
 if not public.is_platform_admin() then raise exception 'Platform administrator required';end if;
 return query select o.id,o.name,o.commercial_status,o.status_reason,o.created_at,p.code,p.name,s.status,s.current_period_end,
 (select count(*) from organization_members m where m.organization_id=o.id and m.active),(select count(*) from organization_members m where m.organization_id=o.id and m.active and m.role='owner'),(select count(*) from plants pl where pl.organization_id=o.id),(select count(*) from file_metadata f where f.organization_id=o.id and f.removed_at is null),(select coalesce(sum(f.size_bytes),0) from file_metadata f where f.organization_id=o.id and f.removed_at is null),
 coalesce((select quantity from usage_counters u where u.organization_id=o.id and u.metric='bandwidth_bytes' and u.period_start=date_trunc('month',current_date)::date),0),coalesce((select quantity from usage_counters u where u.organization_id=o.id and u.metric='ai_requests' and u.period_start=date_trunc('month',current_date)::date),0),
 (select count(*) from platform_support_tickets t where t.organization_id=o.id and t.status not in('resolved','closed')),(select count(*) from system_incidents i where i.organization_id=o.id and i.status<>'resolved'),coalesce(c.access_type,'paid'),c.ends_at
 from organizations o left join organization_subscriptions s on s.organization_id=o.id left join subscription_plans p on p.id=s.plan_id left join complimentary_access c on c.organization_id=o.id and c.revoked_at is null
 where (p_search is null or o.name ilike '%'||p_search||'%') and (p_status is null or o.commercial_status=p_status) order by o.created_at desc;end$function$;

-- ============================================================
-- control_dashboard
-- ============================================================
CREATE OR REPLACE FUNCTION public.control_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$declare r jsonb;begin
 if not public.is_platform_admin() then raise exception 'Platform administrator required';end if;
 select jsonb_build_object(
 'companies_total',(select count(*) from organizations),'companies_active',(select count(*) from organizations where commercial_status='active'),
 'companies_trial',(select count(*) from organizations where commercial_status='trial'),'companies_suspended',(select count(*) from organizations where commercial_status='suspended'),
 'companies_past_due',(select count(*) from organizations where commercial_status='past_due'),'complimentary',(select count(*) from complimentary_access where revoked_at is null and (ends_at is null or ends_at>now())),
 'owners',(select count(*) from organization_members where role='owner' and active),'workers',(select count(*) from organization_members where active),
 'plants',(select count(*) from plants),'files',(select count(*) from file_metadata where removed_at is null),'storage_bytes',(select coalesce(sum(size_bytes),0) from file_metadata where removed_at is null),
 'ai_requests_month',(select coalesce(sum(quantity),0) from usage_counters where metric='ai_requests' and period_start=date_trunc('month',current_date)::date),
 'ai_input_tokens_month',(select coalesce(sum(quantity),0) from usage_counters where metric='ai_input_tokens' and period_start=date_trunc('month',current_date)::date),
 'ai_output_tokens_month',(select coalesce(sum(quantity),0) from usage_counters where metric='ai_output_tokens' and period_start=date_trunc('month',current_date)::date),
 'open_tickets',(select count(*) from platform_support_tickets where status not in('resolved','closed')),'critical_tickets',(select count(*) from platform_support_tickets where priority='critical' and status not in('resolved','closed')),
 'open_incidents',(select count(*) from system_incidents where status<>'resolved'),'critical_incidents',(select count(*) from system_incidents where severity='critical' and status<>'resolved'),
 'failed_ai_24h',(select count(*) from ai_usage where status='failed' and created_at>now()-interval '24 hours'),'latest_backup',(select max(completed_at) from backup_jobs where status='completed')
 ) into r;return r;end$function$;

-- ============================================================
-- control_maintenance_tick
-- ============================================================
CREATE OR REPLACE FUNCTION public.control_maintenance_tick()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$declare expired_comp int;expired_overrides int;begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' and not public.is_platform_admin() then raise exception 'Platform authority required';end if;
 with u as(update complimentary_access set revoked_at=now(),updated_at=now() where revoked_at is null and ends_at is not null and ends_at<=now() returning 1) select count(*) into expired_comp from u;
 with u as(update quota_overrides set active=false,updated_at=now() where active and ends_at is not null and ends_at<=now() returning 1) select count(*) into expired_overrides from u;
 insert into platform_notifications(severity,title,body,component,organization_id) select 'warning','Trial expires soon',o.name||' trial ends at '||o.trial_ends_at,'commercial',o.id from organizations o where o.commercial_status='trial' and o.trial_ends_at between now() and now()+interval '3 days' and not exists(select 1 from platform_notifications n where n.organization_id=o.id and n.title='Trial expires soon' and n.created_at>now()-interval '2 days');
 return jsonb_build_object('expired_complimentary',expired_comp,'expired_overrides',expired_overrides,'checked_at',now());end$function$;

-- ============================================================
-- control_qa_environment_runs
-- ============================================================
CREATE OR REPLACE FUNCTION public.control_qa_environment_runs(p_environment_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb;
begin
 if not public.is_platform_admin() then raise exception 'Active platform administrator required';end if;
 if not exists(select 1 from qa_environments where id=p_environment_id) then raise exception 'QA environment not found';end if;
 select coalesce(jsonb_agg(to_jsonb(r) order by r.started_at desc),'[]'::jsonb) into result from qa_test_runs r where r.environment_id=p_environment_id;
 return result;
end $function$;

-- ============================================================
-- control_qa_overview
-- ============================================================
CREATE OR REPLACE FUNCTION public.control_qa_overview()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

-- ============================================================
-- control_qa_run_detail
-- ============================================================
CREATE OR REPLACE FUNCTION public.control_qa_run_detail(p_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

-- ============================================================
-- control_qa_summary
-- ============================================================
CREATE OR REPLACE FUNCTION public.control_qa_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

-- ============================================================
-- control_revoke_complimentary
-- ============================================================
CREATE OR REPLACE FUNCTION public.control_revoke_complimentary(p_organization_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$begin
 if not public.platform_has_permission('companies.manage') then raise exception 'Permission required';end if;
 update complimentary_access set revoked_at=now(),revoked_by=auth.uid(),updated_at=now() where organization_id=p_organization_id and revoked_at is null;
 insert into admin_action_logs(admin_user_id,action,target_type,target_id,organization_id,reason) values(auth.uid(),'complimentary_access_revoked','organization',p_organization_id::text,p_organization_id,p_reason);end$function$;

-- ============================================================
-- control_save_admin
-- ============================================================
CREATE OR REPLACE FUNCTION public.control_save_admin(p_user_id uuid, p_role text, p_active boolean, p_permissions jsonb, p_display_name text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$declare active_supers bigint;begin if not public.platform_has_permission('admins.manage') then raise exception 'Permission required';end if;if p_role not in('super_admin','operations','support','billing','auditor') then raise exception 'Invalid administrator role';end if;if not exists(select 1 from auth.users where id=p_user_id) then raise exception 'Auth user not found';end if;select count(*) into active_supers from platform_admins where active and admin_role='super_admin' and user_id<>p_user_id;if exists(select 1 from platform_admins where user_id=p_user_id and active and admin_role='super_admin') and (not p_active or p_role<>'super_admin') and active_supers=0 then raise exception 'At least one active super administrator is required';end if;insert into platform_admins(user_id,admin_role,active,permissions,display_name,created_by) values(p_user_id,p_role,p_active,coalesce(p_permissions,'{}'),p_display_name,auth.uid()) on conflict(user_id) do update set admin_role=excluded.admin_role,active=excluded.active,permissions=excluded.permissions,display_name=excluded.display_name,updated_at=now();insert into admin_action_logs(admin_user_id,action,target_type,target_id,details) values(auth.uid(),'platform_admin_saved','platform_admin',p_user_id::text,jsonb_build_object('role',p_role,'active',p_active));end$function$;

-- ============================================================
-- control_save_plan
-- ============================================================
CREATE OR REPLACE FUNCTION public.control_save_plan(p_code text, p_name text, p_description text, p_price_monthly numeric, p_price_yearly numeric, p_max_workers integer, p_max_plants integer, p_storage bigint, p_bandwidth bigint, p_max_files integer, p_max_file bigint, p_ai_month integer, p_ai_day integer, p_ai_minute integer, p_input_tokens bigint, p_output_tokens bigint, p_retention integer, p_features jsonb, p_active boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$declare pid uuid;begin
 if not public.platform_has_permission('plans.manage') then raise exception 'Permission required';end if;
 insert into subscription_plans(code,name,description,price_monthly,price_yearly,max_workers,max_plants,max_storage_bytes,max_bandwidth_bytes_month,max_files,max_file_bytes,ai_requests_month,ai_requests_day,ai_requests_minute_user,ai_input_tokens_month,ai_output_tokens_month,retention_days,features,active,updated_at) values(p_code,p_name,p_description,p_price_monthly,p_price_yearly,p_max_workers,p_max_plants,p_storage,p_bandwidth,p_max_files,p_max_file,p_ai_month,p_ai_day,p_ai_minute,p_input_tokens,p_output_tokens,p_retention,p_features,p_active,now()) on conflict(code) do update set name=excluded.name,description=excluded.description,price_monthly=excluded.price_monthly,price_yearly=excluded.price_yearly,max_workers=excluded.max_workers,max_plants=excluded.max_plants,max_storage_bytes=excluded.max_storage_bytes,max_bandwidth_bytes_month=excluded.max_bandwidth_bytes_month,max_files=excluded.max_files,max_file_bytes=excluded.max_file_bytes,ai_requests_month=excluded.ai_requests_month,ai_requests_day=excluded.ai_requests_day,ai_requests_minute_user=excluded.ai_requests_minute_user,ai_input_tokens_month=excluded.ai_input_tokens_month,ai_output_tokens_month=excluded.ai_output_tokens_month,retention_days=excluded.retention_days,features=excluded.features,active=excluded.active,updated_at=now() returning id into pid;
 insert into admin_action_logs(admin_user_id,action,target_type,target_id,details) values(auth.uid(),'plan_saved','subscription_plan',pid::text,jsonb_build_object('code',p_code,'active',p_active));return pid;end$function$;

-- ============================================================
-- control_set_complimentary
-- ============================================================
CREATE OR REPLACE FUNCTION public.control_set_complimentary(p_organization_id uuid, p_access_type text, p_ends_at timestamp with time zone, p_reason text, p_never_suspend boolean DEFAULT true)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$begin
 if not public.platform_has_permission('companies.manage') then raise exception 'Permission required';end if;
 if p_access_type not in('complimentary','internal','manual') then raise exception 'Invalid access type';end if;
 insert into complimentary_access(organization_id,access_type,ends_at,reason,never_auto_suspend,granted_by,revoked_at,revoked_by) values(p_organization_id,p_access_type,p_ends_at,p_reason,p_never_suspend,auth.uid(),null,null) on conflict(organization_id) do update set access_type=excluded.access_type,starts_at=now(),ends_at=excluded.ends_at,reason=excluded.reason,never_auto_suspend=excluded.never_auto_suspend,granted_by=auth.uid(),revoked_at=null,revoked_by=null,updated_at=now();
 update organizations set commercial_status='active',status_reason=p_reason,commercial_updated_at=now() where id=p_organization_id;update organization_subscriptions set status='active',updated_at=now() where organization_id=p_organization_id;
 insert into admin_action_logs(admin_user_id,action,target_type,target_id,organization_id,reason,details) values(auth.uid(),'complimentary_access_granted','organization',p_organization_id::text,p_organization_id,p_reason,jsonb_build_object('access_type',p_access_type,'ends_at',p_ends_at,'never_auto_suspend',p_never_suspend));end$function$;

-- ============================================================
-- control_storage
-- ============================================================
CREATE OR REPLACE FUNCTION public.control_storage(p_organization_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(file_id uuid, organization_id uuid, company text, file_name text, category text, mime_type text, size_bytes bigint, object_path text, uploaded_by uuid, uploader text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$begin
 if not public.platform_has_permission('storage.view') then raise exception 'Permission required';end if;
 return query select f.id,f.organization_id,o.name,f.file_name,f.category,f.mime_type,f.size_bytes,f.object_path,f.uploaded_by,p.full_name,f.created_at from file_metadata f join organizations o on o.id=f.organization_id left join profiles p on p.id=f.uploaded_by where f.removed_at is null and (p_organization_id is null or f.organization_id=p_organization_id) order by f.created_at desc limit 1000;end$function$;

-- ============================================================
-- control_update_manual_check
-- ============================================================
CREATE OR REPLACE FUNCTION public.control_update_manual_check(p_check_id uuid, p_status text, p_notes text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 if not public.is_platform_admin() then raise exception 'Active platform administrator required';end if;
 if p_status not in('pending','passed','failed','not_available') then raise exception 'Invalid status';end if;
 update qa_manual_checks set status=p_status,result_notes=p_notes,tested_by=auth.uid(),tested_at=case when p_status='pending' then null else now() end where id=p_check_id;
end $function$;

-- ============================================================
-- control_usage
-- ============================================================
CREATE OR REPLACE FUNCTION public.control_usage(p_organization_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(organization_id uuid, company text, metric text, period_start date, quantity bigint, plan_limit bigint, percent_used numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$begin
 if not public.platform_has_permission('usage.view') then raise exception 'Permission required';end if;
 return query select u.organization_id,o.name,u.metric,u.period_start,u.quantity,
 case u.metric when 'ai_requests' then p.ai_requests_month::bigint when 'ai_input_tokens' then p.ai_input_tokens_month when 'ai_output_tokens' then p.ai_output_tokens_month when 'bandwidth_bytes' then p.max_bandwidth_bytes_month else null end,
 case when (case u.metric when 'ai_requests' then p.ai_requests_month::bigint when 'ai_input_tokens' then p.ai_input_tokens_month when 'ai_output_tokens' then p.ai_output_tokens_month when 'bandwidth_bytes' then p.max_bandwidth_bytes_month else null end)>0 then round(u.quantity::numeric/(case u.metric when 'ai_requests' then p.ai_requests_month::bigint when 'ai_input_tokens' then p.ai_input_tokens_month when 'ai_output_tokens' then p.ai_output_tokens_month when 'bandwidth_bytes' then p.max_bandwidth_bytes_month else null end)*100,1) else 0 end
 from usage_counters u join organizations o on o.id=u.organization_id join organization_subscriptions s on s.organization_id=o.id join subscription_plans p on p.id=s.plan_id where (p_organization_id is null or u.organization_id=p_organization_id) and u.period_start>=date_trunc('month',current_date)::date order by o.name,u.metric;end$function$;

-- ============================================================
-- create_default_commercial_records
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_default_commercial_records()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare p uuid;
begin
  select id into p from public.subscription_plans where code='trial';
  update public.organizations set commercial_status='trial',trial_ends_at=now()+interval '30 days' where id=new.id;
  insert into public.organization_subscriptions(organization_id,plan_id,status,current_period_start,current_period_end,trial_ends_at)
    values(new.id,p,'trial',now(),now()+interval '30 days',now()+interval '30 days') on conflict(organization_id) do nothing;
  insert into public.data_retention_policies(organization_id) values(new.id) on conflict do nothing;
  return new;
end $function$;

-- ============================================================
-- create_organization
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_organization(org_name text, plant_name text)
 RETURNS TABLE(organization_id uuid, plant_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o uuid; p uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  insert into organizations(name,slug,created_by) values(org_name,lower(regexp_replace(org_name,'[^a-zA-Z0-9]+','-','g'))||'-'||substr(gen_random_uuid()::text,1,6),auth.uid()) returning id into o;
  insert into organization_members values(o,auth.uid(),'owner',true,now());
  insert into plants(organization_id,name) values(o,plant_name) returning id into p;
  insert into plant_members values(p,auth.uid(),now());
  return query select o,p;
end $function$;

-- ============================================================
-- create_platform_alert
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_platform_alert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  row_data jsonb:=to_jsonb(new);
  sev text;
  org_id uuid;
  ticket_no text;
  title_text text;
  body_text text;
begin
  org_id:=nullif(row_data->>'organization_id','')::uuid;

  if tg_table_name='system_incidents' then
    sev:=row_data->>'severity';
    if sev in('error','critical') then
      insert into public.platform_notifications(severity,title,body,component,organization_id)
      values(
        sev,
        'System incident: '||coalesce(row_data->>'component','unknown'),
        coalesce(row_data->>'message','No incident message'),
        coalesce(row_data->>'component','system'),
        org_id
      );
    end if;
  elsif tg_table_name='platform_support_tickets' then
    sev:=row_data->>'priority';
    if sev in('high','critical') then
      ticket_no:=coalesce(row_data->>'ticket_number','');
      title_text:='Complaint #'||ticket_no||': '||coalesce(row_data->>'subject','Untitled complaint');
      body_text:=coalesce(row_data->>'description','No complaint description');
      insert into public.platform_notifications(severity,title,body,component,organization_id)
      values(
        case when sev='critical' then 'critical' else 'warning' end,
        title_text,
        body_text,
        'platform_support',
        org_id
      );
    end if;
  end if;

  return new;
end $function$;

-- ============================================================
-- deny_admin_log_mutation
-- ============================================================
CREATE OR REPLACE FUNCTION public.deny_admin_log_mutation()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$begin raise exception 'Administrator audit records are append-only';end$function$;

-- ============================================================
-- effective_company_limit
-- ============================================================
CREATE OR REPLACE FUNCTION public.effective_company_limit(p_organization_id uuid, p_metric text, p_base bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$declare absolute_value bigint;bonus_value bigint;blocked boolean;begin
 select exists(select 1 from quota_overrides where organization_id=p_organization_id and metric=p_metric and override_type='block' and active and (ends_at is null or ends_at>now())) into blocked;if blocked then return 0;end if;
 select value into absolute_value from quota_overrides where organization_id=p_organization_id and metric=p_metric and override_type='absolute' and active and (ends_at is null or ends_at>now()) order by created_at desc limit 1;
 select coalesce(sum(value),0) into bonus_value from quota_overrides where organization_id=p_organization_id and metric=p_metric and override_type='bonus' and active and (ends_at is null or ends_at>now());
 return greatest(0,coalesce(absolute_value,p_base)+coalesce(bonus_value,0));end$function$;

-- ============================================================
-- enforce_plant_plan_limit
-- ============================================================
CREATE OR REPLACE FUNCTION public.enforce_plant_plan_limit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$declare base_limit bigint;limit_value bigint;used bigint;begin select p.max_plants into base_limit from organization_subscriptions s join subscription_plans p on p.id=s.plan_id where s.organization_id=new.organization_id and s.status in('active','trial');if base_limit is null then raise exception 'Active subscription required';end if;limit_value:=effective_company_limit(new.organization_id,'plants',base_limit);select count(*) into used from plants where organization_id=new.organization_id and id<>new.id;if used+1>limit_value then raise exception 'Plant limit of % reached',limit_value;end if;return new;end$function$;

-- ============================================================
-- enforce_worker_plan_limit
-- ============================================================
CREATE OR REPLACE FUNCTION public.enforce_worker_plan_limit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
 row_data jsonb:=to_jsonb(new);
 oid uuid;
 new_user_id uuid;
 new_invitation_id uuid;
 new_role text;
 new_active boolean;
 new_accepted_at timestamptz;
 new_expires_at timestamptz;
 base_limit bigint;
 limit_value bigint;
 active_workers bigint;
 pending_invites bigint;
begin
 oid:=nullif(row_data->>'organization_id','')::uuid;
 new_user_id:=nullif(row_data->>'user_id','')::uuid;
 new_invitation_id:=nullif(row_data->>'id','')::uuid;
 new_role:=row_data->>'role';
 new_active:=coalesce((row_data->>'active')::boolean,false);
 new_accepted_at:=nullif(row_data->>'accepted_at','')::timestamptz;
 new_expires_at:=nullif(row_data->>'expires_at','')::timestamptz;

 if oid is null then raise exception 'Organization is required for worker-limit validation';end if;
 if tg_table_name='invitations' and new_role='owner' then raise exception 'Owner cannot be granted by invitation';end if;

 select p.max_workers into base_limit
 from public.organization_subscriptions s
 join public.subscription_plans p on p.id=s.plan_id
 where s.organization_id=oid and s.status in('active','trial');
 if base_limit is null then raise exception 'Active subscription required';end if;

 limit_value:=public.effective_company_limit(oid,'workers',base_limit);

 if tg_table_name='organization_members' then
  select count(*) into active_workers
  from public.organization_members m
  where m.organization_id=oid and m.active and m.user_id is distinct from new_user_id;
 else
  select count(*) into active_workers
  from public.organization_members m
  where m.organization_id=oid and m.active;
 end if;

 if tg_table_name='invitations' then
  select count(*) into pending_invites
  from public.invitations i
  where i.organization_id=oid and i.accepted_at is null and i.expires_at>now() and i.id is distinct from new_invitation_id;
 else
  select count(*) into pending_invites
  from public.invitations i
  where i.organization_id=oid and i.accepted_at is null and i.expires_at>now();
 end if;

 if tg_table_name='organization_members' and new_active then
  active_workers:=active_workers+1;
 end if;
 if tg_table_name='invitations' and new_accepted_at is null and coalesce(new_expires_at,now()-interval '1 second')>now() then
  pending_invites:=pending_invites+1;
 end if;

 if active_workers+pending_invites>limit_value then
  raise exception 'Worker limit of % reached (active %, pending %)',limit_value,active_workers,pending_invites;
 end if;
 return new;
end $function$;

-- ============================================================
-- finalize_ai_request
-- ============================================================
CREATE OR REPLACE FUNCTION public.finalize_ai_request(p_request_id uuid, p_status text, p_provider text, p_model text, p_input_tokens integer, p_output_tokens integer, p_latency_ms integer, p_error_code text DEFAULT NULL::text, p_source_count integer DEFAULT 0)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
 e public.usage_events%rowtype;
 metric_name text;
 period_start_date date;
 period_end_date date;
 estimated_input integer;
begin
 select * into e from public.usage_events where id=p_request_id for update;
 if not found then raise exception 'Usage reservation not found';end if;
 if e.status<>'reserved' then return;end if;
 period_start_date:=date_trunc('month',e.created_at)::date;
 period_end_date:=(date_trunc('month',e.created_at)+interval '1 month'-interval '1 day')::date;
 estimated_input:=coalesce((e.metadata->>'estimated_input_tokens')::integer,0);

 foreach metric_name in array array['ai_requests','ai_input_tokens','ai_output_tokens'] loop
  insert into public.usage_counters(organization_id,metric,period_start,period_end,quantity)
  values(e.organization_id,metric_name,period_start_date,period_end_date,0)
  on conflict(organization_id,metric,period_start) do nothing;
 end loop;

 if p_status='completed' then
  update public.usage_counters set quantity=greatest(0,quantity+greatest(coalesce(p_input_tokens,0),0)-estimated_input),updated_at=now()
   where organization_id=e.organization_id and metric='ai_input_tokens' and period_start=period_start_date;
  update public.usage_counters set quantity=greatest(0,quantity+greatest(coalesce(p_output_tokens,0),0)),updated_at=now()
   where organization_id=e.organization_id and metric='ai_output_tokens' and period_start=period_start_date;
 else
  -- Provider/internal failures do not consume a company request or reserved input-token allowance.
  update public.usage_counters set quantity=greatest(0,quantity-1),updated_at=now()
   where organization_id=e.organization_id and metric='ai_requests' and period_start=period_start_date;
  update public.usage_counters set quantity=greatest(0,quantity-estimated_input),updated_at=now()
   where organization_id=e.organization_id and metric='ai_input_tokens' and period_start=period_start_date;
 end if;

 update public.usage_events set status=p_status,metadata=metadata||jsonb_build_object(
  'provider',p_provider,'model',p_model,'input_tokens',coalesce(p_input_tokens,0),'output_tokens',coalesce(p_output_tokens,0),
  'latency_ms',p_latency_ms,'error_code',p_error_code,'source_count',p_source_count,'finalized_at',now()
 ) where id=e.id;

 insert into public.ai_usage(organization_id,user_id,provider,mode,input_tokens,output_tokens,created_at,request_id,model,status,latency_ms,error_code,source_count)
 values(e.organization_id,e.user_id,p_provider,e.metadata->>'mode',coalesce(p_input_tokens,0),coalesce(p_output_tokens,0),now(),e.id,p_model,p_status,p_latency_ms,p_error_code,p_source_count)
 on conflict(request_id) do update set provider=excluded.provider,model=excluded.model,status=excluded.status,input_tokens=excluded.input_tokens,
 output_tokens=excluded.output_tokens,latency_ms=excluded.latency_ms,error_code=excluded.error_code,source_count=excluded.source_count;
end $function$;

-- ============================================================
-- finalize_storage_upload
-- ============================================================
CREATE OR REPLACE FUNCTION public.finalize_storage_upload(p_reservation_id uuid, p_object_path text, p_file_metadata_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.storage_reservations%rowtype;
begin
  select * into r from public.storage_reservations where id=p_reservation_id for update;
  if not found or r.user_id<>auth.uid() then raise exception 'Storage reservation not found'; end if;
  if r.status<>'reserved' or r.expires_at<=now() then raise exception 'Storage reservation expired'; end if;
  update public.storage_reservations set status='completed' where id=r.id;
  insert into public.storage_usage_events(organization_id,user_id,event_type,object_path,bytes,file_metadata_id) values(r.organization_id,r.user_id,'upload',p_object_path,r.bytes,p_file_metadata_id);
end $function$;

-- ============================================================
-- has_org_permission
-- ============================================================
CREATE OR REPLACE FUNCTION public.has_org_permission(p_org uuid, p_permission text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists(
    select 1 from public.organization_members m
    where m.organization_id=p_org and m.user_id=auth.uid() and m.active
      and (m.role in ('owner','manager') or coalesce((m.permissions->>p_permission)::boolean,false))
  )
$function$;

-- ============================================================
-- is_org_member
-- ============================================================
CREATE OR REPLACE FUNCTION public.is_org_member(org uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists(select 1 from organization_members m where m.organization_id=org and m.user_id=auth.uid() and m.active)
$function$;

-- ============================================================
-- is_platform_admin
-- ============================================================
CREATE OR REPLACE FUNCTION public.is_platform_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select exists(select 1 from public.platform_admins a where a.user_id=auth.uid() and a.active)
$function$;

-- ============================================================
-- is_super_platform_admin
-- ============================================================
CREATE OR REPLACE FUNCTION public.is_super_platform_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select exists(select 1 from public.platform_admins a where a.user_id=auth.uid() and a.active and a.admin_role='super_admin')
$function$;

-- ============================================================
-- new_push_cursor
-- ============================================================
CREATE OR REPLACE FUNCTION public.new_push_cursor()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  insert into public.push_cursors (organization_id) values (new.id)
  on conflict (organization_id) do nothing;
  return new;
end $function$;

-- ============================================================
-- next_po_number
-- ============================================================
CREATE OR REPLACE FUNCTION public.next_po_number(p_org uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  yr text := to_char(now(),'YYYY');
  n  int;
begin
  select coalesce(max(
           nullif(regexp_replace(split_part(po_number,'-',3), '\D','','g'),'')::int
         ), 0) + 1
    into n
    from public.purchase_orders
   where organization_id = p_org
     and po_number like 'PO-'||yr||'-%';
  return 'PO-'||yr||'-'||lpad(n::text, 4, '0');
end $function$;

-- ============================================================
-- org_role
-- ============================================================
CREATE OR REPLACE FUNCTION public.org_role(org uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select role from organization_members where organization_id=org and user_id=auth.uid() and active limit 1
$function$;

-- ============================================================
-- organization_plan_summary
-- ============================================================
CREATE OR REPLACE FUNCTION public.organization_plan_summary(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb;
begin
  if not public.is_org_member(p_organization_id) and not public.is_platform_admin() then raise exception 'Access denied'; end if;
  select jsonb_build_object(
    'organization_status',o.commercial_status,'status_reason',o.status_reason,'trial_ends_at',o.trial_ends_at,
    'subscription_status',s.status,'period_start',s.current_period_start,'period_end',s.current_period_end,
    'plan',to_jsonb(p),
    'workers',(select count(*) from public.organization_members m where m.organization_id=o.id and m.active),
    'plants',(select count(*) from public.plants pl where pl.organization_id=o.id),
    'files',(select count(*) from public.file_metadata f where f.organization_id=o.id and f.removed_at is null),
    'storage_bytes',(select coalesce(sum(f.size_bytes),0) from public.file_metadata f where f.organization_id=o.id and f.removed_at is null),
    'bandwidth_bytes_month',coalesce((select quantity from public.usage_counters u where u.organization_id=o.id and u.metric='bandwidth_bytes' and u.period_start=date_trunc('month',current_date)::date),0),
    'ai_requests_month',coalesce((select quantity from public.usage_counters u where u.organization_id=o.id and u.metric='ai_requests' and u.period_start=date_trunc('month',current_date)::date),0),
    'ai_input_tokens_month',coalesce((select quantity from public.usage_counters u where u.organization_id=o.id and u.metric='ai_input_tokens' and u.period_start=date_trunc('month',current_date)::date),0),
    'ai_output_tokens_month',coalesce((select quantity from public.usage_counters u where u.organization_id=o.id and u.metric='ai_output_tokens' and u.period_start=date_trunc('month',current_date)::date),0)
  ) into result
  from public.organizations o join public.organization_subscriptions s on s.organization_id=o.id join public.subscription_plans p on p.id=s.plan_id
  where o.id=p_organization_id;
  return result;
end $function$;

-- ============================================================
-- owner_app_complaint_messages
-- ============================================================
CREATE OR REPLACE FUNCTION public.owner_app_complaint_messages(p_ticket_id uuid)
 RETURNS TABLE(id uuid, user_id uuid, message text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare oid uuid;
begin
 select organization_id into oid from public.platform_support_tickets where platform_support_tickets.id=p_ticket_id;
 if oid is null or public.org_role(oid)<>'owner' then raise exception 'Company owner access required';end if;
 return query select m.id,m.user_id,m.message,m.created_at from public.platform_support_messages m where m.ticket_id=p_ticket_id and not m.internal order by m.created_at;
end $function$;

-- ============================================================
-- owner_app_complaints
-- ============================================================
CREATE OR REPLACE FUNCTION public.owner_app_complaints(p_organization_id uuid)
 RETURNS SETOF platform_support_tickets
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 if auth.uid() is null or public.org_role(p_organization_id)<>'owner' then raise exception 'Company owner access required';end if;
 return query select * from public.platform_support_tickets where organization_id=p_organization_id order by updated_at desc;
end $function$;

-- ============================================================
-- pending_legal_documents
-- ============================================================
CREATE OR REPLACE FUNCTION public.pending_legal_documents(p_organization_id uuid)
 RETURNS TABLE(id uuid, document_type text, version text, title text, content text, effective_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select d.id,d.document_type,d.version,d.title,d.content,d.effective_at
  from public.legal_documents d
  where d.active and d.required and d.effective_at<=now()
    and (d.acceptance_scope='all_users' or (d.acceptance_scope='owners' and public.org_role(p_organization_id)='owner') or (d.acceptance_scope='platform_admins' and public.is_platform_admin()))
    and (public.is_org_member(p_organization_id) or public.is_platform_admin())
    and not exists(select 1 from public.legal_acceptances a where a.document_id=d.id and a.user_id=auth.uid())
  order by d.effective_at,d.document_type
$function$;

-- ============================================================
-- platform_ban_user
-- ============================================================
CREATE OR REPLACE FUNCTION public.platform_ban_user(p_user_id uuid, p_reason text, p_ban boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  -- 1. Ensure the caller is an active platform admin
  IF NOT EXISTS (SELECT 1 FROM platform_admins WHERE user_id = auth.uid() AND active = true) THEN
    RAISE EXCEPTION 'Unauthorized: Platform admin access required';
  END IF;

  -- 2. Log the action
  INSERT INTO admin_action_logs (admin_user_id, action, target_type, target_id, reason)
  VALUES (auth.uid(), CASE WHEN p_ban THEN 'ban_user' ELSE 'unban_user' END, 'user', p_user_id, p_reason);

  -- 3. Update the banned_until field in auth.users
  IF p_ban THEN
    UPDATE auth.users SET banned_until = '2100-01-01 00:00:00+00' WHERE id = p_user_id;
  ELSE
    UPDATE auth.users SET banned_until = NULL WHERE id = p_user_id;
  END IF;
END;
$function$;

-- ============================================================
-- platform_delete_user
-- ============================================================
CREATE OR REPLACE FUNCTION public.platform_delete_user(p_user_id uuid, p_reason text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  -- 1. Ensure the caller is an active platform admin
  IF NOT EXISTS (SELECT 1 FROM platform_admins WHERE user_id = auth.uid() AND active = true) THEN
    RETURN 'Unauthorized: Platform admin access required';
  END IF;

  -- 2. Prevent self-deletion
  IF p_user_id = auth.uid() THEN
    RETURN 'Cannot delete your own admin account';
  END IF;

  -- 3. Log the action
  INSERT INTO admin_action_logs (admin_user_id, action, target_type, target_id, reason)
  VALUES (auth.uid(), 'delete_user', 'user', p_user_id, p_reason);

  -- 4. Manually delete dependent records to avoid Foreign Key constraint errors
  DELETE FROM organization_members WHERE user_id = p_user_id;
  DELETE FROM profiles WHERE id = p_user_id;
  
  -- Add any other tables if necessary (e.g. platform_admins)
  DELETE FROM platform_admins WHERE user_id = p_user_id;
  
  -- 5. Finally, delete from auth.users
  DELETE FROM auth.users WHERE id = p_user_id;

  RETURN 'Success';
EXCEPTION WHEN OTHERS THEN
  RETURN SQLERRM;
END;
$function$;

-- ============================================================
-- platform_has_permission
-- ============================================================
CREATE OR REPLACE FUNCTION public.platform_has_permission(p_permission text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select exists(select 1 from public.platform_admins a where a.user_id=auth.uid() and a.active and (a.admin_role='super_admin' or coalesce((a.permissions->>p_permission)::boolean,false)))
$function$;

-- ============================================================
-- platform_set_company
-- ============================================================
CREATE OR REPLACE FUNCTION public.platform_set_company(p_organization_id uuid, p_status text, p_plan_code text DEFAULT NULL::text, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$declare plan_uuid uuid;subscription_state text;begin if not public.platform_has_permission('companies.manage') then raise exception 'Permission required';end if;if p_status not in('trial','active','past_due','suspended','cancelled','deletion_pending') then raise exception 'Invalid company status';end if;if p_plan_code is not null then select id into plan_uuid from subscription_plans where code=p_plan_code and active;if plan_uuid is null then raise exception 'Plan not found';end if;end if;update organizations set commercial_status=p_status,status_reason=p_reason,suspended_at=case when p_status='suspended' then now() else null end,deletion_scheduled_at=case when p_status='deletion_pending' then coalesce(deletion_scheduled_at,now()+interval '30 days') else null end,commercial_updated_at=now() where id=p_organization_id;subscription_state:=case when p_status in('active','trial','past_due','suspended','cancelled') then p_status else 'cancelled' end;update organization_subscriptions set plan_id=coalesce(plan_uuid,plan_id),status=subscription_state,updated_at=now() where organization_id=p_organization_id;insert into admin_action_logs(admin_user_id,action,target_type,target_id,organization_id,reason,details) values(auth.uid(),'company_commercial_updated','organization',p_organization_id::text,p_organization_id,p_reason,jsonb_build_object('status',p_status,'plan_code',p_plan_code));end$function$;

-- ============================================================
-- platform_tenant_overview
-- ============================================================
CREATE OR REPLACE FUNCTION public.platform_tenant_overview()
 RETURNS TABLE(organization_id uuid, organization_name text, commercial_status text, status_reason text, created_at timestamp with time zone, plan_code text, plan_name text, subscription_status text, period_end timestamp with time zone, workers bigint, plants bigint, files bigint, storage_bytes numeric, ai_requests_month bigint, open_incidents bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_platform_admin() then raise exception 'Platform administrator required';end if;
  return query
  select o.id,o.name,o.commercial_status,o.status_reason,o.created_at,p.code,p.name,s.status,s.current_period_end,
    (select count(*) from public.organization_members m where m.organization_id=o.id and m.active),
    (select count(*) from public.plants pl where pl.organization_id=o.id),
    (select count(*) from public.file_metadata f where f.organization_id=o.id and f.removed_at is null),
    (select coalesce(sum(f.size_bytes),0) from public.file_metadata f where f.organization_id=o.id and f.removed_at is null),
    coalesce((select u.quantity from public.usage_counters u where u.organization_id=o.id and u.metric='ai_requests' and u.period_start=date_trunc('month',current_date)::date),0),
    (select count(*) from public.system_incidents i where i.organization_id=o.id and i.status<>'resolved')
  from public.organizations o left join public.organization_subscriptions s on s.organization_id=o.id left join public.subscription_plans p on p.id=s.plan_id order by o.created_at desc;
end $function$;

-- ============================================================
-- platform_update_incident
-- ============================================================
CREATE OR REPLACE FUNCTION public.platform_update_incident(p_incident_id uuid, p_status text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$begin if not public.platform_has_permission('incidents.manage') then raise exception 'Permission required';end if;if p_status not in('open','acknowledged','resolved') then raise exception 'Invalid incident status';end if;update system_incidents set status=p_status,resolved_at=case when p_status='resolved' then now() else null end,last_seen_at=now() where id=p_incident_id;insert into admin_action_logs(admin_user_id,action,target_type,target_id,reason) values(auth.uid(),'incident_status_changed','system_incident',p_incident_id::text,p_status);end$function$;

-- ============================================================
-- pm_create_api_key
-- ============================================================
CREATE OR REPLACE FUNCTION public.pm_create_api_key(p_org uuid, p_name text, p_plant uuid DEFAULT NULL::uuid, p_expires timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS TABLE(id uuid, api_key text, key_prefix text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_key    text;
  v_hash   text;
  v_prefix text;
  v_id     uuid;
begin
  if not public.pm_is_org_owner(p_org) then
    raise exception 'Only the organization owner can create API keys';
  end if;

  -- pm_live_<40 hex chars>
  v_key    := 'pm_live_' || encode(gen_random_bytes(20), 'hex');
  v_hash   := encode(digest(v_key, 'sha256'), 'hex');
  v_prefix := left(v_key, 16);
  v_id     := gen_random_uuid();

  insert into public.api_keys
    (id, organization_id, plant_id, name, key_hash, key_prefix, created_by, expires_at)
  values
    (v_id, p_org, p_plant, p_name, v_hash, v_prefix, auth.uid(), p_expires);

  return query select v_id, v_key, v_prefix;
end;
$function$;

-- ============================================================
-- pm_is_org_leader
-- ============================================================
CREATE OR REPLACE FUNCTION public.pm_is_org_leader(p_org uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.organization_members m
     where m.organization_id = p_org
       and m.user_id = auth.uid()
       and m.role in ('owner','manager')
  );
$function$;

-- ============================================================
-- pm_is_org_member
-- ============================================================
CREATE OR REPLACE FUNCTION public.pm_is_org_member(p_org uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.organization_members m
     where m.organization_id = p_org
       and m.user_id = auth.uid()
  );
$function$;

-- ============================================================
-- pm_is_org_owner
-- ============================================================
CREATE OR REPLACE FUNCTION public.pm_is_org_owner(p_org uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.organization_members m
     where m.organization_id = p_org
       and m.user_id = auth.uid()
       and m.role = 'owner'
  );
$function$;

-- ============================================================
-- pm_revoke_api_key
-- ============================================================
CREATE OR REPLACE FUNCTION public.pm_revoke_api_key(p_key uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_org uuid;
begin
  select organization_id into v_org from public.api_keys where id = p_key;
  if v_org is null then
    raise exception 'API key not found';
  end if;
  if not public.pm_is_org_owner(v_org) then
    raise exception 'Only the organization owner can revoke API keys';
  end if;

  update public.api_keys
     set revoked_at = now()
   where id = p_key;
end;
$function$;

-- ============================================================
-- po_line_after_change
-- ============================================================
CREATE OR REPLACE FUNCTION public.po_line_after_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if (tg_op in ('INSERT','UPDATE')) then
    new.line_total := round(new.quantity * new.unit_price, 2);
  end if;

  if tg_op = 'DELETE' then
    perform public.recalc_po_totals(old.purchase_order_id);
    return old;
  end if;

  perform public.recalc_po_totals(new.purchase_order_id);
  return new;
end $function$;

-- ============================================================
-- protect_condition_baseline
-- ============================================================
CREATE OR REPLACE FUNCTION public.protect_condition_baseline()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.is_baseline and (tg_op='INSERT' or not coalesce(old.is_baseline,false)) then
    if public.org_role(new.organization_id) not in ('owner','manager','engineer') then raise exception 'Owner, manager or engineer approval is required for a baseline';end if;
    new.approved_by:=auth.uid();new.approved_at:=coalesce(new.approved_at,now());new.status:='approved';
  end if;
  return new;
end $function$;

-- ============================================================
-- protect_owner_role
-- ============================================================
CREATE OR REPLACE FUNCTION public.protect_owner_role()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare old_owner boolean:=false;new_owner boolean:=false;transfer_flag text;
begin
  transfer_flag:=coalesce(current_setting('plantmaster.owner_transfer',true),'');
  if tg_table_name='invitations' then
    if new.role='owner' then raise exception 'Owner cannot be granted by invitation';end if;
    return new;
  end if;
  old_owner:=old.role='owner';new_owner:=new.role='owner';
  if old_owner<>new_owner and transfer_flag<>'allowed' and not public.is_platform_admin() then
    raise exception 'Use the audited ownership-transfer workflow';
  end if;
  if old_owner and old.active and not new.active and transfer_flag<>'allowed' and not public.is_platform_admin() then
    raise exception 'Transfer ownership before deactivating the owner';
  end if;
  return new;
end $function$;

-- ============================================================
-- qa_identity_context
-- ============================================================
CREATE OR REPLACE FUNCTION public.qa_identity_context(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select jsonb_build_object(
  'user_id',auth.uid(),
  'organization_id',p_organization_id,
  'is_member',public.is_org_member(p_organization_id),
  'role',public.org_role(p_organization_id),
  'active',exists(select 1 from public.organization_members m where m.organization_id=p_organization_id and m.user_id=auth.uid() and m.active)
 )
$function$;

-- ============================================================
-- recalc_po_totals
-- ============================================================
CREATE OR REPLACE FUNCTION public.recalc_po_totals(p_po uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  s numeric(14,2);
  t numeric(5,2);
begin
  select coalesce(sum(line_total),0) into s
    from public.purchase_order_lines where purchase_order_id = p_po;
  select coalesce(tax_percent,0) into t
    from public.purchase_orders where id = p_po;

  update public.purchase_orders
     set subtotal   = s,
         tax_amount = round(s * t / 100.0, 2),
         total      = s + round(s * t / 100.0, 2),
         updated_at = now()
   where id = p_po;
end $function$;

-- ============================================================
-- receive_po_line
-- ============================================================
CREATE OR REPLACE FUNCTION public.receive_po_line(p_line uuid, p_qty numeric, p_user uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_line record;
  v_po   record;
  v_open integer;
begin
  select * into v_line from public.purchase_order_lines where id = p_line;
  if v_line is null then
    raise exception 'Purchase order line not found';
  end if;

  select * into v_po from public.purchase_orders where id = v_line.purchase_order_id;
  if v_po is null then
    raise exception 'Purchase order not found';
  end if;

  if not public.pm_is_org_leader(v_po.organization_id) then
    raise exception 'Only an owner or manager can receive goods';
  end if;

  if p_qty is null or p_qty <= 0 then
    raise exception 'Received quantity must be greater than zero';
  end if;

  if v_line.received_qty + p_qty > v_line.quantity then
    raise exception 'Cannot receive % — only % outstanding',
      p_qty, (v_line.quantity - v_line.received_qty);
  end if;

  update public.purchase_order_lines
     set received_qty = received_qty + p_qty
   where id = p_line;

  -- ---------------- stock + movement log ----------------
  -- Only PO lines linked to a spare affect stock. A line typed in freehand
  -- (or pointing at a tool) updates the PO but moves no inventory.
  if v_line.spare_id is not null then

    update public.spares
       set stock = coalesce(stock,0) + p_qty,
           updated_at = now()
     where id = v_line.spare_id;

    insert into public.inventory_transactions
      (id, spare_id, quantity, transaction_type, reference, performed_by, created_at)
    values
      (gen_random_uuid(),
       v_line.spare_id,
       p_qty,
       'receive',
       'PO ' || v_po.po_number,
       coalesce(p_user, auth.uid()),
       now());

  end if;

  -- ---------------- roll up PO status ----------------
  select count(*) into v_open
    from public.purchase_order_lines
   where purchase_order_id = v_po.id
     and received_qty < quantity;

  update public.purchase_orders
     set status = case when v_open = 0 then 'received' else 'partially_received' end,
         received_date = case when v_open = 0 then current_date else received_date end,
         updated_at = now()
   where id = v_po.id;

  return jsonb_build_object(
    'ok', true,
    'lines_outstanding', v_open,
    'stock_moved', (v_line.spare_id is not null)
  );
end;
$function$;

-- ============================================================
-- record_storage_download
-- ============================================================
CREATE OR REPLACE FUNCTION public.record_storage_download(p_organization_id uuid, p_object_path text, p_bytes bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$declare ms date:=date_trunc('month',current_date)::date;me date:=(date_trunc('month',current_date)+interval '1 month'-interval '1 day')::date;p subscription_plans%rowtype;used bigint;lim bigint;begin
 if auth.uid() is null or not is_org_member(p_organization_id) then raise exception 'Membership required';end if;select pl.* into p from organization_subscriptions s join subscription_plans pl on pl.id=s.plan_id where s.organization_id=p_organization_id and s.status in('active','trial');if not found then raise exception 'Active subscription required';end if;lim:=effective_company_limit(p_organization_id,'bandwidth_bytes',p.max_bandwidth_bytes_month);insert into usage_counters values(p_organization_id,'bandwidth_bytes',ms,me,0,now()) on conflict do nothing;select quantity into used from usage_counters where organization_id=p_organization_id and metric='bandwidth_bytes' and period_start=ms for update;if used+greatest(p_bytes,0)>lim then raise exception 'Monthly download bandwidth limit reached';end if;update usage_counters set quantity=quantity+greatest(p_bytes,0),updated_at=now() where organization_id=p_organization_id and metric='bandwidth_bytes' and period_start=ms;insert into storage_usage_events(organization_id,user_id,event_type,object_path,bytes) values(p_organization_id,auth.uid(),'download',p_object_path,greatest(p_bytes,0));end$function$;

-- ============================================================
-- release_stale_ai_reservations
-- ============================================================
CREATE OR REPLACE FUNCTION public.release_stale_ai_reservations(p_older_than interval DEFAULT '00:05:00'::interval)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare e public.usage_events%rowtype;released integer:=0;period_start_date date;estimated_input integer;
begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' and session_user<>'postgres' and not public.is_platform_admin() then
  raise exception 'Platform authority required';
 end if;
 for e in select * from public.usage_events where status='reserved' and created_at<now()-p_older_than for update loop
  period_start_date:=date_trunc('month',e.created_at)::date;
  estimated_input:=coalesce((e.metadata->>'estimated_input_tokens')::integer,0);
  update public.usage_counters set quantity=greatest(0,quantity-1),updated_at=now()
   where organization_id=e.organization_id and metric='ai_requests' and period_start=period_start_date;
  update public.usage_counters set quantity=greatest(0,quantity-estimated_input),updated_at=now()
   where organization_id=e.organization_id and metric='ai_input_tokens' and period_start=period_start_date;
  update public.usage_events set status='failed',metadata=metadata||jsonb_build_object('error_code','STALE_RESERVATION_RELEASED','finalized_at',now()) where id=e.id;
  insert into public.ai_usage(organization_id,user_id,provider,mode,input_tokens,output_tokens,created_at,request_id,model,status,latency_ms,error_code,source_count)
  values(e.organization_id,e.user_id,'plantmaster_reconciliation',e.metadata->>'mode',0,0,now(),e.id,null,'failed',null,'STALE_RESERVATION_RELEASED',0)
  on conflict(request_id) do nothing;
  released:=released+1;
 end loop;
 return released;
end $function$;

-- ============================================================
-- reply_app_complaint
-- ============================================================
CREATE OR REPLACE FUNCTION public.reply_app_complaint(p_ticket_id uuid, p_message text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t public.platform_support_tickets%rowtype;mid uuid:=gen_random_uuid();
begin
 if auth.uid() is null then raise exception 'Authentication required';end if;
 select * into t from public.platform_support_tickets where id=p_ticket_id;
 if not found then raise exception 'Complaint not found';end if;
 if public.org_role(t.organization_id)<>'owner' then raise exception 'Company owner access required';end if;
 if length(trim(coalesce(p_message,'')))<1 then raise exception 'Reply is required';end if;
 insert into public.platform_support_messages(id,ticket_id,user_id,message,internal) values(mid,t.id,auth.uid(),trim(p_message),false);
 update public.platform_support_tickets set updated_at=now(),status=case when status in('resolved','closed') then 'acknowledged' else status end where id=t.id;
 return mid;
end $function$;

-- ============================================================
-- require_commercial_write_access
-- ============================================================
CREATE OR REPLACE FUNCTION public.require_commercial_write_access()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare oid uuid;state text;claim_role text;
begin
  if tg_op='DELETE' then oid:=old.organization_id;else oid:=new.organization_id;end if;
  claim_role:=coalesce(current_setting('request.jwt.claim.role',true),'');
  if claim_role='service_role' then if tg_op='DELETE' then return old;else return new;end if;end if;
  select commercial_status into state from public.organizations where id=oid;
  if state not in ('active','trial') then raise exception 'Company is %. Operational changes are disabled.',coalesce(state,'unavailable');end if;
  if tg_op='DELETE' then return old;else return new;end if;
end $function$;

-- ============================================================
-- require_owner_for_hard_delete
-- ============================================================
CREATE OR REPLACE FUNCTION public.require_owner_for_hard_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')='service_role' then return old;end if;
 if public.org_role(old.organization_id)<>'owner' then raise exception 'Only the company owner can permanently erase records';end if;
 return old;
end$function$;

-- ============================================================
-- reserve_ai_request
-- ============================================================
CREATE OR REPLACE FUNCTION public.reserve_ai_request(p_organization_id uuid, p_user_id uuid, p_mode text, p_estimated_input_tokens integer DEFAULT 0)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$declare o organizations%rowtype;p subscription_plans%rowtype;rid uuid:=gen_random_uuid();ms date:=date_trunc('month',current_date)::date;me date:=(date_trunc('month',current_date)+interval '1 month'-interval '1 day')::date;month_used bigint;token_used bigint;day_used bigint;minute_used bigint;month_limit bigint;day_limit bigint;minute_limit bigint;token_limit bigint;begin
 select * into o from organizations where id=p_organization_id for update;if not found then raise exception 'Organization not found';end if;if o.commercial_status not in('active','trial') then raise exception 'Company access is %',o.commercial_status;end if;if not exists(select 1 from organization_members where organization_id=o.id and user_id=p_user_id and active) then raise exception 'Membership required';end if;
 select pl.* into p from organization_subscriptions s join subscription_plans pl on pl.id=s.plan_id where s.organization_id=o.id and s.status in('active','trial');if not found then raise exception 'Active subscription required';end if;if not company_feature_allowed(o.id,'gemini',coalesce((p.features->>'gemini')::boolean,false)) then raise exception 'Gemini is disabled for this company';end if;if p_mode like 'vision_%' and not company_feature_allowed(o.id,'vision_scanner',true) then raise exception 'Vision Scanner AI is disabled for this company';end if;if p_mode like 'condition_%' and not company_feature_allowed(o.id,'condition_analysis',true) then raise exception 'Condition Analysis AI is disabled for this company';end if;if p_mode='deep' and not company_feature_allowed(o.id,'deep_search',coalesce((p.features->>'deep_search')::boolean,false)) then raise exception 'Deep Search is not included';end if;
 month_limit:=effective_company_limit(o.id,'ai_requests',p.ai_requests_month);day_limit:=effective_company_limit(o.id,'ai_requests_day',p.ai_requests_day);minute_limit:=effective_company_limit(o.id,'ai_requests_minute_user',p.ai_requests_minute_user);token_limit:=effective_company_limit(o.id,'ai_input_tokens',p.ai_input_tokens_month);
 select count(*) into minute_used from usage_events where organization_id=o.id and user_id=p_user_id and metric='ai_request_reserved' and created_at>now()-interval '1 minute';if minute_used>=minute_limit then raise exception 'Per-minute Gemini limit reached';end if;select count(*) into day_used from usage_events where organization_id=o.id and metric='ai_request_reserved' and created_at>=current_date;if day_used>=day_limit then raise exception 'Daily Gemini limit reached';end if;
 insert into usage_counters values(o.id,'ai_requests',ms,me,0,now()) on conflict do nothing;select quantity into month_used from usage_counters where organization_id=o.id and metric='ai_requests' and period_start=ms for update;if month_used>=month_limit then raise exception 'Monthly Gemini request limit reached';end if;insert into usage_counters values(o.id,'ai_input_tokens',ms,me,0,now()) on conflict do nothing;select quantity into token_used from usage_counters where organization_id=o.id and metric='ai_input_tokens' and period_start=ms for update;if token_used+greatest(p_estimated_input_tokens,0)>token_limit then raise exception 'Monthly Gemini input-token limit reached';end if;
 update usage_counters set quantity=quantity+1,updated_at=now() where organization_id=o.id and metric='ai_requests' and period_start=ms;update usage_counters set quantity=quantity+greatest(p_estimated_input_tokens,0),updated_at=now() where organization_id=o.id and metric='ai_input_tokens' and period_start=ms;insert into usage_events(id,organization_id,user_id,metric,quantity,source,reference_id,status,metadata) values(rid,o.id,p_user_id,'ai_request_reserved',1,'gemini_edge',rid::text,'reserved',jsonb_build_object('mode',p_mode,'estimated_input_tokens',p_estimated_input_tokens));return rid;end$function$;

-- ============================================================
-- reserve_storage_upload
-- ============================================================
CREATE OR REPLACE FUNCTION public.reserve_storage_upload(p_organization_id uuid, p_bytes bigint, p_file_name text, p_mime_type text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$declare o organizations%rowtype;p subscription_plans%rowtype;used bigint;reserved bigint;files bigint;rid uuid:=gen_random_uuid();storage_limit bigint;file_limit bigint;file_size_limit bigint;begin
 if auth.uid() is null or not is_org_member(p_organization_id) then raise exception 'Membership required';end if;if not company_feature_allowed(p_organization_id,'uploads',true) then raise exception 'Uploads are disabled for this company';end if;if p_bytes<=0 then raise exception 'File is empty';end if;select * into o from organizations where id=p_organization_id for update;if o.commercial_status not in('active','trial') then raise exception 'Company access is %',o.commercial_status;end if;select pl.* into p from organization_subscriptions s join subscription_plans pl on pl.id=s.plan_id where s.organization_id=o.id and s.status in('active','trial');if not found then raise exception 'Active subscription required';end if;
 storage_limit:=effective_company_limit(o.id,'storage_bytes',p.max_storage_bytes);file_limit:=effective_company_limit(o.id,'files',p.max_files);file_size_limit:=effective_company_limit(o.id,'file_size_bytes',p.max_file_bytes);if p_bytes>file_size_limit then raise exception 'File exceeds company limit';end if;select coalesce(sum(size_bytes),0),count(*) into used,files from file_metadata where organization_id=o.id and removed_at is null;select coalesce(sum(bytes),0) into reserved from storage_reservations where organization_id=o.id and status='reserved' and expires_at>now();if files>=file_limit then raise exception 'File-count limit reached';end if;if used+reserved+p_bytes>storage_limit then raise exception 'Storage limit reached';end if;update storage_reservations set status='expired' where organization_id=o.id and status='reserved' and expires_at<=now();insert into storage_reservations(id,organization_id,user_id,bytes,file_name,mime_type) values(rid,o.id,auth.uid(),p_bytes,p_file_name,p_mime_type);return rid;end$function$;

-- ============================================================
-- rls_auto_enable
-- ============================================================
CREATE OR REPLACE FUNCTION public.rls_auto_enable()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;

-- ============================================================
-- set_plantmaster_updated_at
-- ============================================================
CREATE OR REPLACE FUNCTION public.set_plantmaster_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
                                        begin
                                          new.updated_at = now();
                                            return new;
                                            end;
                                            $function$;

-- ============================================================
-- submit_app_complaint
-- ============================================================
CREATE OR REPLACE FUNCTION public.submit_app_complaint(p_organization_id uuid, p_category text, p_priority text, p_subject text, p_description text, p_app_version text, p_device_info jsonb DEFAULT '{}'::jsonb)
 RETURNS TABLE(ticket_id uuid, ticket_number bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare tid uuid:=gen_random_uuid();tn bigint;
begin
 if auth.uid() is null then raise exception 'Authentication required';end if;
 if public.org_role(p_organization_id)<>'owner' then raise exception 'Company owner access required';end if;
 if p_priority not in('low','medium','high','critical') then raise exception 'Invalid priority';end if;
 if length(trim(coalesce(p_subject,'')))<3 then raise exception 'Subject is required';end if;
 if length(trim(coalesce(p_description,'')))<10 then raise exception 'Please provide a more detailed description';end if;
 insert into public.platform_support_tickets(id,organization_id,opened_by,owner_email,category,priority,subject,description,app_version,device_info,status)
 values(tid,p_organization_id,auth.uid(),coalesce(auth.jwt()->>'email',''),p_category,p_priority,trim(p_subject),trim(p_description),p_app_version,coalesce(p_device_info,'{}'::jsonb),'new') returning platform_support_tickets.ticket_number into tn;
 insert into public.audit_logs(organization_id,user_id,action,entity_type,entity_id,details)
 values(p_organization_id,auth.uid(),'platform_complaint_created','platform_support_ticket',tid::text,jsonb_build_object('ticket_number',tn,'priority',p_priority,'category',p_category,'timestamp',now()));
 return query select tid,tn;
end $function$;

-- ============================================================
-- transact_spare
-- ============================================================
CREATE OR REPLACE FUNCTION public.transact_spare(p_spare_id uuid, p_type text, p_quantity numeric, p_reference text DEFAULT NULL::text, p_worker_name text DEFAULT ''::text, p_designation text DEFAULT ''::text, p_shift_name text DEFAULT ''::text)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare s public.spares%rowtype; new_stock numeric; signed_quantity numeric;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_type not in ('receive','issue','adjustment') then raise exception 'Invalid transaction type'; end if;
  if p_quantity <= 0 then raise exception 'Quantity must be greater than zero'; end if;
  select * into s from public.spares where id=p_spare_id for update;
  if not found then raise exception 'Spare not found'; end if;
  if not public.has_org_permission(s.organization_id,'inventory.transact') and public.org_role(s.organization_id) not in ('engineer','supervisor','store','technician') then
    raise exception 'Inventory transaction permission required';
  end if;
  new_stock := case when p_type='issue' then s.stock-p_quantity when p_type='adjustment' then p_quantity else s.stock+p_quantity end;
  if new_stock < 0 then raise exception 'Issue quantity exceeds available stock'; end if;
  signed_quantity := case when p_type='issue' then -p_quantity else p_quantity end;
  insert into public.inventory_transactions(id,spare_id,quantity,transaction_type,reference,performed_by,created_at)
    values(gen_random_uuid(),s.id,signed_quantity,p_type,concat_ws(' | ',nullif(p_reference,''),nullif(p_worker_name,''),nullif(p_designation,''),nullif(p_shift_name,'')),auth.uid(),now());
  update public.spares set stock=new_stock,updated_at=now() where id=s.id;
  insert into public.audit_logs(organization_id,plant_id,user_id,action,entity_type,entity_id,details)
    values(s.organization_id,s.plant_id,auth.uid(),'inventory_transaction','spare',s.id::text,jsonb_build_object('type',p_type,'quantity',p_quantity,'new_stock',new_stock,'worker_name',p_worker_name,'designation',p_designation,'shift_name',p_shift_name,'timestamp',now()));
  return new_stock;
end $function$;

-- ============================================================
-- transact_tool
-- ============================================================
CREATE OR REPLACE FUNCTION public.transact_tool(p_tool_id uuid, p_type text, p_holder_id uuid DEFAULT NULL::uuid, p_condition text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_worker_name text DEFAULT ''::text, p_designation text DEFAULT ''::text, p_shift_name text DEFAULT ''::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t public.tools%rowtype; new_status text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_type not in ('checkout','return','calibration','inspection') then raise exception 'Invalid tool transaction type'; end if;
  select * into t from public.tools where id=p_tool_id for update;
  if not found then raise exception 'Tool not found'; end if;
  if not public.has_org_permission(t.organization_id,'inventory.transact') and public.org_role(t.organization_id) not in ('engineer','supervisor','store','technician') then
    raise exception 'Tool transaction permission required';
  end if;
  if p_type='checkout' and t.status='checked_out' then raise exception 'Tool is already checked out'; end if;
  new_status := case when p_type='checkout' then 'checked_out' else 'available' end;
  insert into public.tool_transactions(id,organization_id,plant_id,tool_id,transaction_type,holder_id,condition,notes,performed_by,worker_name,designation,shift_name,created_at)
    values(gen_random_uuid(),t.organization_id,t.plant_id,t.id,p_type,p_holder_id,p_condition,p_notes,auth.uid(),p_worker_name,p_designation,p_shift_name,now());
  update public.tools set status=new_status,holder_id=case when p_type='checkout' then p_holder_id else null end,condition=coalesce(p_condition,condition),calibration_due=case when p_type='calibration' then null else calibration_due end,updated_at=now() where id=t.id;
  insert into public.audit_logs(organization_id,plant_id,user_id,action,entity_type,entity_id,details)
    values(t.organization_id,t.plant_id,auth.uid(),'tool_'||p_type,'tool',t.id::text,jsonb_build_object('holder_id',p_holder_id,'condition',p_condition,'worker_name',p_worker_name,'designation',p_designation,'shift_name',p_shift_name,'timestamp',now()));
  return new_status;
end $function$;

-- ============================================================
-- transfer_organization_ownership
-- ============================================================
CREATE OR REPLACE FUNCTION public.transfer_organization_ownership(p_organization_id uuid, p_new_owner uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare current_owner uuid;
begin
  select user_id into current_owner from public.organization_members where organization_id=p_organization_id and role='owner' and active order by created_at limit 1 for update;
  if current_owner is null then raise exception 'Active owner not found';end if;
  if auth.uid()<>current_owner and not public.is_platform_admin() then raise exception 'Only the current owner or platform administrator can transfer ownership';end if;
  if not exists(select 1 from public.organization_members where organization_id=p_organization_id and user_id=p_new_owner and active) then raise exception 'New owner must be an active company member';end if;
  if p_new_owner=current_owner then return;end if;
  perform set_config('plantmaster.owner_transfer','allowed',true);
  update public.organization_members set role='manager',updated_at=now() where organization_id=p_organization_id and user_id=current_owner;
  update public.organization_members set role='owner',updated_at=now() where organization_id=p_organization_id and user_id=p_new_owner;
  insert into public.audit_logs(organization_id,user_id,action,entity_type,entity_id,details) values(p_organization_id,auth.uid(),'ownership_transferred','organization',p_organization_id::text,jsonb_build_object('old_owner',current_owner,'new_owner',p_new_owner,'timestamp',now()));
end $function$;
