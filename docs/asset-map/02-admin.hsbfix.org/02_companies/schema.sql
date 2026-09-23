-- ============================================================
-- Schema for this section (auto-extracted from the repo / live snapshot)
-- ============================================================


-- ---------- TABLES ----------


-- [company_feature_grants]  source: R4-company-features.sql
create table if not exists public.company_feature_grants (
  organization_id uuid not null
    references public.organizations(id) on delete cascade,
  feature         text not null,
  granted         boolean not null default true,
  reason          text,
  granted_by      uuid references auth.users(id) on delete set null,
  expires_at      timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  primary key (organization_id, feature)
);


-- [company_feature_blocks]  source: 05-tables-constraints-indexes.sql (LIVE snapshot)
create table if not exists public.company_feature_blocks (
  organization_id uuid not null,
  feature text not null,
  blocked boolean default true not null,
  reason text not null,
  blocked_by uuid not null,
  expires_at timestamptz,
  updated_at timestamptz default now() not null
);


-- [quota_overrides]  source: 05-tables-constraints-indexes.sql (LIVE snapshot)
create table if not exists public.quota_overrides (
  id uuid default gen_random_uuid() not null,
  organization_id uuid not null,
  metric text not null,
  override_type text not null,
  value bigint,
  starts_at timestamptz default now() not null,
  ends_at timestamptz,
  reason text not null,
  active boolean default true not null,
  created_by uuid not null,
  created_at timestamptz default now() not null,
  updated_at timestamptz default now() not null
);


-- [subscription_plans]  source: 0005_platform_commercial.sql
create table if not exists public.subscription_plans (
  code              text primary key,
  name              text not null,
  price_monthly     numeric not null default 0,
  currency          text not null default 'PKR',
  max_users         int,
  max_plants        int,
  max_assets        int,
  storage_gb        numeric not null default 1,
  ai_requests_month int not null default 0,
  features          jsonb not null default '{}'::jsonb,
  active            boolean not null default true,
  sort_order        int not null default 0,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);



-- ---------- FUNCTIONS / RPCs ----------


-- [control_companies()]  source: 02-function-source.sql (LIVE snapshot)
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


-- [platform_set_company()]  source: 0006_rpc.sql
create or replace function public.platform_set_company(
  p_organization_id uuid,
  p_status          text,
  p_plan_code       text default null,
  p_reason          text default null
) returns public.organizations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare o public.organizations;
begin
  if not public.is_platform_admin() then
    raise exception 'Platform administrator required' using errcode = '42501';
  end if;
  if p_plan_code is not null
     and not exists (select 1 from public.subscription_plans where code = p_plan_code) then
    raise exception 'Unknown plan %', p_plan_code using errcode = '22023';
  end if;

  update public.organizations
     set commercial_status = p_status::public.commercial_status,
         plan_code         = coalesce(p_plan_code, plan_code),
         status_reason     = p_reason,
         updated_at        = now()
   where id = p_organization_id
  returning * into o;

  insert into public.audit_logs
    (organization_id, user_id, action, entity_type, entity_id, details)
  values (p_organization_id, auth.uid(), 'platform_status_changed', 'organization',
          p_organization_id::text,
          jsonb_build_object('status', p_status, 'plan', p_plan_code, 'reason', p_reason));

  return o;
end $$;


-- [control_set_complimentary()]  source: 02-function-source.sql (LIVE snapshot)
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


-- [control_delete_company()]  source: R2-control-center.sql
create or replace function public.control_delete_company(
  p_org uuid, p_confirmation text
) returns jsonb
language plpgsql security definer set search_path to 'public'
as $$
declare org_name text; n integer;
begin
  if not public.is_platform_admin() then
    raise exception 'Platform administrator required';
  end if;

  select name into org_name from public.organizations where id = p_org;
  if org_name is null then raise exception 'Company not found'; end if;

  if p_confirmation is distinct from org_name then
    raise exception 'Type the company name exactly to confirm: %', org_name;
  end if;

  -- the only FKs that do not cascade and do not allow null
  delete from public.ai_usage where organization_id = p_org;

  -- these reference plants(id) with no on-delete rule
  delete from public.manuals           where organization_id = p_org;
  delete from public.notifications     where organization_id = p_org;
  delete from public.report_dispatches where organization_id = p_org;

  -- everything else cascades from organizations
  delete from public.organizations where id = p_org;
  get diagnostics n = row_count;

  return jsonb_build_object('deleted', n > 0, 'company', org_name);
end $$;
