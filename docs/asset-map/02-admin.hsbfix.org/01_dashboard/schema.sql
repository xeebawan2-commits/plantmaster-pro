-- ============================================================
-- Schema for this section (auto-extracted from the repo / live snapshot)
-- ============================================================


-- ---------- TABLES ----------


-- [platform_admins]  source: 0001_foundation.sql
create table if not exists public.platform_admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  email      text,
  note       text,
  created_at timestamptz not null default now()
);



-- ---------- FUNCTIONS / RPCs ----------


-- [control_dashboard()]  source: 02-function-source.sql (LIVE snapshot)
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


-- [is_platform_admin()]  source: 0001_foundation.sql
create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.platform_admins pa
    where pa.user_id = auth.uid()
  );
$$;
