-- PlantMaster Platform Control Center v1.0
-- Requires PlantMaster schemas through Phase 10. Additive/idempotent.

create extension if not exists pgcrypto;

alter table public.platform_admins add column if not exists admin_role text not null default 'super_admin';
alter table public.platform_admins add column if not exists permissions jsonb not null default '{}'::jsonb;
alter table public.platform_admins add column if not exists display_name text;
alter table public.platform_admins add column if not exists last_login_at timestamptz;
alter table public.platform_admins add column if not exists updated_at timestamptz not null default now();
do $$ begin
 if not exists(select 1 from pg_constraint where conname='platform_admin_role_check') then alter table public.platform_admins add constraint platform_admin_role_check check(admin_role in('super_admin','operations','support','billing','auditor'));end if;
end $$;

create or replace function public.platform_has_permission(p_permission text)
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.platform_admins a where a.user_id=auth.uid() and a.active and (a.admin_role='super_admin' or coalesce((a.permissions->>p_permission)::boolean,false)))
$$;
grant execute on function public.platform_has_permission(text) to authenticated;

create table if not exists public.complimentary_access(
 organization_id uuid primary key references public.organizations(id) on delete cascade,
 access_type text not null default 'complimentary' check(access_type in('complimentary','internal','manual')),
 starts_at timestamptz not null default now(),
 ends_at timestamptz,
 reason text not null,
 never_auto_suspend boolean not null default true,
 granted_by uuid not null references auth.users(id),
 revoked_at timestamptz,
 revoked_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.quota_overrides(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,
 metric text not null,override_type text not null check(override_type in('absolute','bonus','block')),
 value bigint,starts_at timestamptz not null default now(),ends_at timestamptz,reason text not null,
 active boolean not null default true,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create index if not exists quota_overrides_org_metric_idx on public.quota_overrides(organization_id,metric,active);

create table if not exists public.usage_adjustments(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.organizations(id) on delete cascade,
 metric text not null,period_start date not null,quantity bigint not null,reason text not null,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now()
);

create sequence if not exists public.platform_ticket_number_seq start 1000;
create table if not exists public.platform_support_tickets(
 id uuid primary key default gen_random_uuid(),ticket_number bigint not null unique default nextval('public.platform_ticket_number_seq'),
 organization_id uuid references public.organizations(id) on delete set null,opened_by uuid not null references auth.users(id),
 owner_email text,category text not null,priority text not null default 'medium' check(priority in('low','medium','high','critical')),
 status text not null default 'new' check(status in('new','acknowledged','investigating','waiting_customer','resolved','closed')),
 subject text not null,description text not null,app_version text,device_info jsonb not null default '{}'::jsonb,
 assigned_to uuid references auth.users(id),related_incident_id uuid references public.system_incidents(id) on delete set null,
 resolution text,resolved_at timestamptz,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create index if not exists platform_tickets_status_priority_idx on public.platform_support_tickets(status,priority,updated_at desc);
create table if not exists public.platform_support_messages(
 id uuid primary key default gen_random_uuid(),ticket_id uuid not null references public.platform_support_tickets(id) on delete cascade,
 user_id uuid not null references auth.users(id),message text not null,internal boolean not null default false,
 attachment_path text,created_at timestamptz not null default now()
);

create table if not exists public.admin_action_logs(
 id bigint generated always as identity primary key,admin_user_id uuid references auth.users(id) on delete set null,
 action text not null,target_type text not null,target_id text,organization_id uuid references public.organizations(id) on delete set null,
 reason text,details jsonb not null default '{}'::jsonb,correlation_id uuid not null default gen_random_uuid(),created_at timestamptz not null default now()
);
create index if not exists admin_action_time_idx on public.admin_action_logs(created_at desc);

create table if not exists public.backup_jobs(
 id uuid primary key default gen_random_uuid(),job_type text not null check(job_type in('managed_snapshot','pitr_checkpoint','storage_inventory','logical_export')),
 status text not null default 'requested' check(status in('requested','running','completed','failed','cancelled')),
 provider text not null default 'supabase_managed',requested_by uuid not null references auth.users(id),started_at timestamptz,completed_at timestamptz,
 backup_reference text,size_bytes bigint,checksum text,error text,metadata jsonb not null default '{}'::jsonb,created_at timestamptz not null default now()
);
create table if not exists public.restore_drills(
 id uuid primary key default gen_random_uuid(),backup_job_id uuid references public.backup_jobs(id) on delete set null,
 status text not null default 'planned' check(status in('planned','running','passed','failed','cancelled')),
 environment text not null default 'non_production',rpo_minutes integer,rto_minutes integer,database_verified boolean,storage_verified boolean,
 notes text,performed_by uuid references auth.users(id),scheduled_at timestamptz,started_at timestamptz,completed_at timestamptz,created_at timestamptz not null default now()
);

create table if not exists public.platform_notifications(
 id uuid primary key default gen_random_uuid(),severity text not null check(severity in('info','warning','error','critical')),
 title text not null,body text,component text,organization_id uuid references public.organizations(id) on delete cascade,
 read_at timestamptz,created_at timestamptz not null default now()
);

create table if not exists public.company_feature_blocks(
 organization_id uuid not null references public.organizations(id) on delete cascade,feature text not null,blocked boolean not null default true,
 reason text not null,blocked_by uuid not null references auth.users(id),expires_at timestamptz,updated_at timestamptz not null default now(),primary key(organization_id,feature)
);

-- Append-only protection for commercial evidence.
create or replace function public.deny_admin_log_mutation() returns trigger language plpgsql as $$begin raise exception 'Administrator audit records are append-only';end$$;
do $$ begin
 if not exists(select 1 from pg_trigger where tgname='admin_logs_append_only' and not tgisinternal) then create trigger admin_logs_append_only before update or delete on public.admin_action_logs for each row execute function public.deny_admin_log_mutation();end if;
 if not exists(select 1 from pg_trigger where tgname='usage_adjustments_append_only' and not tgisinternal) then create trigger usage_adjustments_append_only before update or delete on public.usage_adjustments for each row execute function public.deny_admin_log_mutation();end if;
end $$;

-- RLS: platform tables are visible only to authorized platform administrators, with ticket access for customer owners.
alter table public.complimentary_access enable row level security;alter table public.quota_overrides enable row level security;alter table public.usage_adjustments enable row level security;alter table public.platform_support_tickets enable row level security;alter table public.platform_support_messages enable row level security;alter table public.admin_action_logs enable row level security;alter table public.backup_jobs enable row level security;alter table public.restore_drills enable row level security;alter table public.platform_notifications enable row level security;alter table public.company_feature_blocks enable row level security;
do $$ begin
 if not exists(select 1 from pg_policies where tablename='complimentary_access' and policyname='platform manage complimentary') then create policy "platform manage complimentary" on public.complimentary_access for all to authenticated using(public.platform_has_permission('companies.manage')) with check(public.platform_has_permission('companies.manage'));end if;
 if not exists(select 1 from pg_policies where tablename='quota_overrides' and policyname='platform manage quota') then create policy "platform manage quota" on public.quota_overrides for all to authenticated using(public.platform_has_permission('usage.manage')) with check(public.platform_has_permission('usage.manage'));end if;
 if not exists(select 1 from pg_policies where tablename='usage_adjustments' and policyname='platform create adjustment') then create policy "platform create adjustment" on public.usage_adjustments for select to authenticated using(public.platform_has_permission('usage.view'));create policy "platform insert adjustment" on public.usage_adjustments for insert to authenticated with check(public.platform_has_permission('usage.manage'));end if;
 if not exists(select 1 from pg_policies where tablename='platform_support_tickets' and policyname='platform manages tickets') then create policy "platform manages tickets" on public.platform_support_tickets for all to authenticated using(public.platform_has_permission('support.manage')) with check(public.platform_has_permission('support.manage'));create policy "owner reads tickets" on public.platform_support_tickets for select to authenticated using(organization_id is not null and public.org_role(organization_id)='owner');create policy "owner creates tickets" on public.platform_support_tickets for insert to authenticated with check(organization_id is not null and public.org_role(organization_id)='owner' and opened_by=auth.uid());end if;
 if not exists(select 1 from pg_policies where tablename='platform_support_messages' and policyname='platform manages ticket messages') then create policy "platform manages ticket messages" on public.platform_support_messages for all to authenticated using(public.platform_has_permission('support.manage')) with check(public.platform_has_permission('support.manage'));create policy "owner reads public ticket messages" on public.platform_support_messages for select to authenticated using(not internal and exists(select 1 from public.platform_support_tickets t where t.id=ticket_id and public.org_role(t.organization_id)='owner'));create policy "owner creates public ticket messages" on public.platform_support_messages for insert to authenticated with check(not internal and user_id=auth.uid() and exists(select 1 from public.platform_support_tickets t where t.id=ticket_id and public.org_role(t.organization_id)='owner'));end if;
 if not exists(select 1 from pg_policies where tablename='admin_action_logs' and policyname='platform read admin logs') then create policy "platform read admin logs" on public.admin_action_logs for select to authenticated using(public.platform_has_permission('audit.view'));create policy "platform insert admin logs" on public.admin_action_logs for insert to authenticated with check(public.is_platform_admin());end if;
 if not exists(select 1 from pg_policies where tablename='backup_jobs' and policyname='platform backup access') then create policy "platform backup access" on public.backup_jobs for all to authenticated using(public.platform_has_permission('backups.manage')) with check(public.platform_has_permission('backups.manage'));end if;
 if not exists(select 1 from pg_policies where tablename='restore_drills' and policyname='platform restore access') then create policy "platform restore access" on public.restore_drills for all to authenticated using(public.platform_has_permission('backups.manage')) with check(public.platform_has_permission('backups.manage'));end if;
 if not exists(select 1 from pg_policies where tablename='platform_notifications' and policyname='platform notification access') then create policy "platform notification access" on public.platform_notifications for all to authenticated using(public.is_platform_admin()) with check(public.is_platform_admin());end if;
 if not exists(select 1 from pg_policies where tablename='company_feature_blocks' and policyname='platform feature block access') then create policy "platform feature block access" on public.company_feature_blocks for all to authenticated using(public.platform_has_permission('companies.manage')) with check(public.platform_has_permission('companies.manage'));end if;
end $$;

grant select,insert,update,delete on public.complimentary_access,public.quota_overrides,public.platform_support_tickets,public.platform_support_messages,public.backup_jobs,public.restore_drills,public.platform_notifications,public.company_feature_blocks to authenticated;
grant select,insert on public.usage_adjustments,public.admin_action_logs to authenticated;grant usage,select on all sequences in schema public to authenticated;grant usage,select on sequence public.platform_ticket_number_seq to authenticated;

-- Dashboard aggregates.
create or replace function public.control_dashboard() returns jsonb language plpgsql stable security definer set search_path=public as $$declare r jsonb;begin
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
 ) into r;return r;end$$;
grant execute on function public.control_dashboard() to authenticated;

create or replace function public.control_companies(p_search text default null,p_status text default null) returns table(organization_id uuid,name text,status text,status_reason text,created_at timestamptz,plan_code text,plan_name text,subscription_status text,period_end timestamptz,workers bigint,owners bigint,plants bigint,files bigint,storage_bytes numeric,bandwidth_month bigint,ai_requests_month bigint,open_tickets bigint,open_incidents bigint,access_type text,complimentary_ends_at timestamptz) language plpgsql stable security definer set search_path=public as $$begin
 if not public.is_platform_admin() then raise exception 'Platform administrator required';end if;
 return query select o.id,o.name,o.commercial_status,o.status_reason,o.created_at,p.code,p.name,s.status,s.current_period_end,
 (select count(*) from organization_members m where m.organization_id=o.id and m.active),(select count(*) from organization_members m where m.organization_id=o.id and m.active and m.role='owner'),(select count(*) from plants pl where pl.organization_id=o.id),(select count(*) from file_metadata f where f.organization_id=o.id and f.removed_at is null),(select coalesce(sum(f.size_bytes),0) from file_metadata f where f.organization_id=o.id and f.removed_at is null),
 coalesce((select quantity from usage_counters u where u.organization_id=o.id and u.metric='bandwidth_bytes' and u.period_start=date_trunc('month',current_date)::date),0),coalesce((select quantity from usage_counters u where u.organization_id=o.id and u.metric='ai_requests' and u.period_start=date_trunc('month',current_date)::date),0),
 (select count(*) from platform_support_tickets t where t.organization_id=o.id and t.status not in('resolved','closed')),(select count(*) from system_incidents i where i.organization_id=o.id and i.status<>'resolved'),coalesce(c.access_type,'paid'),c.ends_at
 from organizations o left join organization_subscriptions s on s.organization_id=o.id left join subscription_plans p on p.id=s.plan_id left join complimentary_access c on c.organization_id=o.id and c.revoked_at is null
 where (p_search is null or o.name ilike '%'||p_search||'%') and (p_status is null or o.commercial_status=p_status) order by o.created_at desc;end$$;
grant execute on function public.control_companies(text,text) to authenticated;

create or replace function public.control_accounts(p_search text default null) returns table(user_id uuid,email text,full_name text,created_at timestamptz,last_sign_in_at timestamptz,banned_until timestamptz,memberships bigint,companies jsonb,owner_count bigint) language plpgsql stable security definer set search_path=public as $$begin
 if not public.platform_has_permission('accounts.view') then raise exception 'Permission required';end if;
 return query select u.id,u.email,p.full_name,u.created_at,u.last_sign_in_at,u.banned_until,(select count(*) from organization_members m where m.user_id=u.id),coalesce((select jsonb_agg(jsonb_build_object('organization_id',o.id,'company',o.name,'role',m.role,'active',m.active)) from organization_members m join organizations o on o.id=m.organization_id where m.user_id=u.id),'[]'::jsonb),(select count(*) from organization_members m where m.user_id=u.id and m.role='owner' and m.active)
 from auth.users u left join profiles p on p.id=u.id where p_search is null or u.email ilike '%'||p_search||'%' or p.full_name ilike '%'||p_search||'%' order by u.created_at desc limit 500;end$$;
grant execute on function public.control_accounts(text) to authenticated;

create or replace function public.control_usage(p_organization_id uuid default null) returns table(organization_id uuid,company text,metric text,period_start date,quantity bigint,plan_limit bigint,percent_used numeric) language plpgsql stable security definer set search_path=public as $$begin
 if not public.platform_has_permission('usage.view') then raise exception 'Permission required';end if;
 return query select u.organization_id,o.name,u.metric,u.period_start,u.quantity,
 case u.metric when 'ai_requests' then p.ai_requests_month::bigint when 'ai_input_tokens' then p.ai_input_tokens_month when 'ai_output_tokens' then p.ai_output_tokens_month when 'bandwidth_bytes' then p.max_bandwidth_bytes_month else null end,
 case when (case u.metric when 'ai_requests' then p.ai_requests_month::bigint when 'ai_input_tokens' then p.ai_input_tokens_month when 'ai_output_tokens' then p.ai_output_tokens_month when 'bandwidth_bytes' then p.max_bandwidth_bytes_month else null end)>0 then round(u.quantity::numeric/(case u.metric when 'ai_requests' then p.ai_requests_month::bigint when 'ai_input_tokens' then p.ai_input_tokens_month when 'ai_output_tokens' then p.ai_output_tokens_month when 'bandwidth_bytes' then p.max_bandwidth_bytes_month else null end)*100,1) else 0 end
 from usage_counters u join organizations o on o.id=u.organization_id join organization_subscriptions s on s.organization_id=o.id join subscription_plans p on p.id=s.plan_id where (p_organization_id is null or u.organization_id=p_organization_id) and u.period_start>=date_trunc('month',current_date)::date order by o.name,u.metric;end$$;
grant execute on function public.control_usage(uuid) to authenticated;

create or replace function public.control_storage(p_organization_id uuid default null) returns table(file_id uuid,organization_id uuid,company text,file_name text,category text,mime_type text,size_bytes bigint,object_path text,uploaded_by uuid,uploader text,created_at timestamptz) language plpgsql stable security definer set search_path=public as $$begin
 if not public.platform_has_permission('storage.view') then raise exception 'Permission required';end if;
 return query select f.id,f.organization_id,o.name,f.file_name,f.category,f.mime_type,f.size_bytes,f.object_path,f.uploaded_by,p.full_name,f.created_at from file_metadata f join organizations o on o.id=f.organization_id left join profiles p on p.id=f.uploaded_by where f.removed_at is null and (p_organization_id is null or f.organization_id=p_organization_id) order by f.created_at desc limit 1000;end$$;
grant execute on function public.control_storage(uuid) to authenticated;

create or replace function public.control_admins() returns table(user_id uuid,email text,full_name text,admin_role text,active boolean,permissions jsonb,created_at timestamptz,last_login_at timestamptz) language plpgsql stable security definer set search_path=public as $$begin if not public.platform_has_permission('admins.manage') then raise exception 'Permission required';end if;return query select a.user_id,u.email,coalesce(a.display_name,p.full_name),a.admin_role,a.active,a.permissions,a.created_at,a.last_login_at from platform_admins a join auth.users u on u.id=a.user_id left join profiles p on p.id=a.user_id order by a.created_at;end$$;grant execute on function public.control_admins() to authenticated;
create or replace function public.control_save_admin(p_user_id uuid,p_role text,p_active boolean,p_permissions jsonb,p_display_name text default null) returns void language plpgsql security definer set search_path=public as $$declare active_supers bigint;begin if not public.platform_has_permission('admins.manage') then raise exception 'Permission required';end if;if p_role not in('super_admin','operations','support','billing','auditor') then raise exception 'Invalid administrator role';end if;if not exists(select 1 from auth.users where id=p_user_id) then raise exception 'Auth user not found';end if;select count(*) into active_supers from platform_admins where active and admin_role='super_admin' and user_id<>p_user_id;if exists(select 1 from platform_admins where user_id=p_user_id and active and admin_role='super_admin') and (not p_active or p_role<>'super_admin') and active_supers=0 then raise exception 'At least one active super administrator is required';end if;insert into platform_admins(user_id,admin_role,active,permissions,display_name,created_by) values(p_user_id,p_role,p_active,coalesce(p_permissions,'{}'),p_display_name,auth.uid()) on conflict(user_id) do update set admin_role=excluded.admin_role,active=excluded.active,permissions=excluded.permissions,display_name=excluded.display_name,updated_at=now();insert into admin_action_logs(admin_user_id,action,target_type,target_id,details) values(auth.uid(),'platform_admin_saved','platform_admin',p_user_id::text,jsonb_build_object('role',p_role,'active',p_active));end$$;grant execute on function public.control_save_admin(uuid,text,boolean,jsonb,text) to authenticated;

create or replace function public.control_ai_usage(p_organization_id uuid default null) returns table(organization_id uuid,company text,user_id uuid,user_name text,provider text,model text,mode text,status text,input_tokens int,output_tokens int,latency_ms int,error_code text,created_at timestamptz) language plpgsql stable security definer set search_path=public as $$begin
 if not public.platform_has_permission('ai.view') then raise exception 'Permission required';end if;
 return query select a.organization_id,o.name,a.user_id,p.full_name,a.provider,a.model,a.mode,a.status,a.input_tokens,a.output_tokens,a.latency_ms,a.error_code,a.created_at from ai_usage a join organizations o on o.id=a.organization_id left join profiles p on p.id=a.user_id where (p_organization_id is null or a.organization_id=p_organization_id) order by a.created_at desc limit 2000;end$$;
grant execute on function public.control_ai_usage(uuid) to authenticated;

-- Manual commercial controls and audit.
create or replace function public.control_set_complimentary(p_organization_id uuid,p_access_type text,p_ends_at timestamptz,p_reason text,p_never_suspend boolean default true) returns void language plpgsql security definer set search_path=public as $$begin
 if not public.platform_has_permission('companies.manage') then raise exception 'Permission required';end if;
 if p_access_type not in('complimentary','internal','manual') then raise exception 'Invalid access type';end if;
 insert into complimentary_access(organization_id,access_type,ends_at,reason,never_auto_suspend,granted_by,revoked_at,revoked_by) values(p_organization_id,p_access_type,p_ends_at,p_reason,p_never_suspend,auth.uid(),null,null) on conflict(organization_id) do update set access_type=excluded.access_type,starts_at=now(),ends_at=excluded.ends_at,reason=excluded.reason,never_auto_suspend=excluded.never_auto_suspend,granted_by=auth.uid(),revoked_at=null,revoked_by=null,updated_at=now();
 update organizations set commercial_status='active',status_reason=p_reason,commercial_updated_at=now() where id=p_organization_id;update organization_subscriptions set status='active',updated_at=now() where organization_id=p_organization_id;
 insert into admin_action_logs(admin_user_id,action,target_type,target_id,organization_id,reason,details) values(auth.uid(),'complimentary_access_granted','organization',p_organization_id::text,p_organization_id,p_reason,jsonb_build_object('access_type',p_access_type,'ends_at',p_ends_at,'never_auto_suspend',p_never_suspend));end$$;
grant execute on function public.control_set_complimentary(uuid,text,timestamptz,text,boolean) to authenticated;

create or replace function public.control_revoke_complimentary(p_organization_id uuid,p_reason text) returns void language plpgsql security definer set search_path=public as $$begin
 if not public.platform_has_permission('companies.manage') then raise exception 'Permission required';end if;
 update complimentary_access set revoked_at=now(),revoked_by=auth.uid(),updated_at=now() where organization_id=p_organization_id and revoked_at is null;
 insert into admin_action_logs(admin_user_id,action,target_type,target_id,organization_id,reason) values(auth.uid(),'complimentary_access_revoked','organization',p_organization_id::text,p_organization_id,p_reason);end$$;
grant execute on function public.control_revoke_complimentary(uuid,text) to authenticated;

create or replace function public.control_adjust_usage(p_organization_id uuid,p_metric text,p_quantity bigint,p_reason text) returns void language plpgsql security definer set search_path=public as $$declare ps date:=date_trunc('month',current_date)::date;pe date:=(date_trunc('month',current_date)+interval '1 month'-interval '1 day')::date;begin
 if not public.platform_has_permission('usage.manage') then raise exception 'Permission required';end if;
 insert into usage_adjustments(organization_id,metric,period_start,quantity,reason,created_by) values(p_organization_id,p_metric,ps,p_quantity,p_reason,auth.uid());insert into usage_counters(organization_id,metric,period_start,period_end,quantity) values(p_organization_id,p_metric,ps,pe,greatest(0,p_quantity)) on conflict(organization_id,metric,period_start) do update set quantity=greatest(0,usage_counters.quantity+p_quantity),updated_at=now();
 insert into admin_action_logs(admin_user_id,action,target_type,target_id,organization_id,reason,details) values(auth.uid(),'usage_adjusted','usage',p_metric,p_organization_id,p_reason,jsonb_build_object('quantity',p_quantity,'period_start',ps));end$$;
grant execute on function public.control_adjust_usage(uuid,text,bigint,text) to authenticated;

create or replace function public.control_save_plan(p_code text,p_name text,p_description text,p_price_monthly numeric,p_price_yearly numeric,p_max_workers int,p_max_plants int,p_storage bigint,p_bandwidth bigint,p_max_files int,p_max_file bigint,p_ai_month int,p_ai_day int,p_ai_minute int,p_input_tokens bigint,p_output_tokens bigint,p_retention int,p_features jsonb,p_active boolean default true) returns uuid language plpgsql security definer set search_path=public as $$declare pid uuid;begin
 if not public.platform_has_permission('plans.manage') then raise exception 'Permission required';end if;
 insert into subscription_plans(code,name,description,price_monthly,price_yearly,max_workers,max_plants,max_storage_bytes,max_bandwidth_bytes_month,max_files,max_file_bytes,ai_requests_month,ai_requests_day,ai_requests_minute_user,ai_input_tokens_month,ai_output_tokens_month,retention_days,features,active,updated_at) values(p_code,p_name,p_description,p_price_monthly,p_price_yearly,p_max_workers,p_max_plants,p_storage,p_bandwidth,p_max_files,p_max_file,p_ai_month,p_ai_day,p_ai_minute,p_input_tokens,p_output_tokens,p_retention,p_features,p_active,now()) on conflict(code) do update set name=excluded.name,description=excluded.description,price_monthly=excluded.price_monthly,price_yearly=excluded.price_yearly,max_workers=excluded.max_workers,max_plants=excluded.max_plants,max_storage_bytes=excluded.max_storage_bytes,max_bandwidth_bytes_month=excluded.max_bandwidth_bytes_month,max_files=excluded.max_files,max_file_bytes=excluded.max_file_bytes,ai_requests_month=excluded.ai_requests_month,ai_requests_day=excluded.ai_requests_day,ai_requests_minute_user=excluded.ai_requests_minute_user,ai_input_tokens_month=excluded.ai_input_tokens_month,ai_output_tokens_month=excluded.ai_output_tokens_month,retention_days=excluded.retention_days,features=excluded.features,active=excluded.active,updated_at=now() returning id into pid;
 insert into admin_action_logs(admin_user_id,action,target_type,target_id,details) values(auth.uid(),'plan_saved','subscription_plan',pid::text,jsonb_build_object('code',p_code,'active',p_active));return pid;end$$;
grant execute on function public.control_save_plan(text,text,text,numeric,numeric,int,int,bigint,bigint,int,bigint,int,int,int,bigint,bigint,int,jsonb,boolean) to authenticated;

-- Effective per-company limits: plan base + active overrides.
create or replace function public.effective_company_limit(p_organization_id uuid,p_metric text,p_base bigint)
returns bigint language plpgsql stable security definer set search_path=public as $$declare absolute_value bigint;bonus_value bigint;blocked boolean;begin
 select exists(select 1 from quota_overrides where organization_id=p_organization_id and metric=p_metric and override_type='block' and active and (ends_at is null or ends_at>now())) into blocked;if blocked then return 0;end if;
 select value into absolute_value from quota_overrides where organization_id=p_organization_id and metric=p_metric and override_type='absolute' and active and (ends_at is null or ends_at>now()) order by created_at desc limit 1;
 select coalesce(sum(value),0) into bonus_value from quota_overrides where organization_id=p_organization_id and metric=p_metric and override_type='bonus' and active and (ends_at is null or ends_at>now());
 return greatest(0,coalesce(absolute_value,p_base)+coalesce(bonus_value,0));end$$;
grant execute on function public.effective_company_limit(uuid,text,bigint) to authenticated,service_role;

create or replace function public.company_feature_allowed(p_organization_id uuid,p_feature text,p_plan_default boolean)
returns boolean language sql stable security definer set search_path=public as $$select case when exists(select 1 from company_feature_blocks where organization_id=p_organization_id and feature=p_feature and blocked and (expires_at is null or expires_at>now())) then false else p_plan_default end$$;
grant execute on function public.company_feature_allowed(uuid,text,boolean) to authenticated,service_role;

-- Override-aware worker and plant enforcement.
create or replace function public.enforce_worker_plan_limit() returns trigger language plpgsql security definer set search_path=public as $$declare oid uuid;limit_value bigint;active_workers bigint;pending_invites bigint;base_limit bigint;begin
 oid:=new.organization_id;if tg_table_name='invitations' and new.role='owner' then raise exception 'Owner cannot be granted by invitation';end if;
 select p.max_workers into base_limit from organization_subscriptions s join subscription_plans p on p.id=s.plan_id where s.organization_id=oid and s.status in('active','trial');if base_limit is null then raise exception 'Active subscription required';end if;limit_value:=effective_company_limit(oid,'workers',base_limit);
 select count(*) into active_workers from organization_members where organization_id=oid and active and (tg_table_name<>'organization_members' or user_id<>new.user_id);select count(*) into pending_invites from invitations where organization_id=oid and accepted_at is null and expires_at>now() and (tg_table_name<>'invitations' or id<>new.id);
 if tg_table_name='organization_members' and coalesce(new.active,false) then active_workers:=active_workers+1;end if;if tg_table_name='invitations' and new.accepted_at is null and new.expires_at>now() then pending_invites:=pending_invites+1;end if;if active_workers+pending_invites>limit_value then raise exception 'Worker limit of % reached',limit_value;end if;return new;end$$;
create or replace function public.enforce_plant_plan_limit() returns trigger language plpgsql security definer set search_path=public as $$declare base_limit bigint;limit_value bigint;used bigint;begin select p.max_plants into base_limit from organization_subscriptions s join subscription_plans p on p.id=s.plan_id where s.organization_id=new.organization_id and s.status in('active','trial');if base_limit is null then raise exception 'Active subscription required';end if;limit_value:=effective_company_limit(new.organization_id,'plants',base_limit);select count(*) into used from plants where organization_id=new.organization_id and id<>new.id;if used+1>limit_value then raise exception 'Plant limit of % reached',limit_value;end if;return new;end$$;

-- Additional platform policies.
do $$ begin
 if not exists(select 1 from pg_policies where tablename='legal_documents' and policyname='platform manages legal documents') then create policy "platform manages legal documents" on public.legal_documents for all to authenticated using(public.platform_has_permission('legal.manage')) with check(public.platform_has_permission('legal.manage'));end if;
 if not exists(select 1 from pg_policies where tablename='platform_admins' and policyname='platform admin updates self') then create policy "platform admin updates self" on public.platform_admins for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());end if;
 if not exists(select 1 from pg_policies where tablename='platform_admins' and policyname='super admin manages administrators') then create policy "super admin manages administrators" on public.platform_admins for all to authenticated using(public.platform_has_permission('admins.manage')) with check(public.platform_has_permission('admins.manage'));end if;
end $$;
grant insert,update,delete on public.legal_documents to authenticated;grant select,insert,update,delete on public.platform_admins to authenticated;

-- Override-aware AI reservation used by all Gemini Edge Functions.
create or replace function public.reserve_ai_request(p_organization_id uuid,p_user_id uuid,p_mode text,p_estimated_input_tokens integer default 0)
returns uuid language plpgsql security definer set search_path=public as $$declare o organizations%rowtype;p subscription_plans%rowtype;rid uuid:=gen_random_uuid();ms date:=date_trunc('month',current_date)::date;me date:=(date_trunc('month',current_date)+interval '1 month'-interval '1 day')::date;month_used bigint;token_used bigint;day_used bigint;minute_used bigint;month_limit bigint;day_limit bigint;minute_limit bigint;token_limit bigint;begin
 select * into o from organizations where id=p_organization_id for update;if not found then raise exception 'Organization not found';end if;if o.commercial_status not in('active','trial') then raise exception 'Company access is %',o.commercial_status;end if;if not exists(select 1 from organization_members where organization_id=o.id and user_id=p_user_id and active) then raise exception 'Membership required';end if;
 select pl.* into p from organization_subscriptions s join subscription_plans pl on pl.id=s.plan_id where s.organization_id=o.id and s.status in('active','trial');if not found then raise exception 'Active subscription required';end if;if not company_feature_allowed(o.id,'gemini',coalesce((p.features->>'gemini')::boolean,false)) then raise exception 'Gemini is disabled for this company';end if;if p_mode like 'vision_%' and not company_feature_allowed(o.id,'vision_scanner',true) then raise exception 'Vision Scanner AI is disabled for this company';end if;if p_mode like 'condition_%' and not company_feature_allowed(o.id,'condition_analysis',true) then raise exception 'Condition Analysis AI is disabled for this company';end if;if p_mode='deep' and not company_feature_allowed(o.id,'deep_search',coalesce((p.features->>'deep_search')::boolean,false)) then raise exception 'Deep Search is not included';end if;
 month_limit:=effective_company_limit(o.id,'ai_requests',p.ai_requests_month);day_limit:=effective_company_limit(o.id,'ai_requests_day',p.ai_requests_day);minute_limit:=effective_company_limit(o.id,'ai_requests_minute_user',p.ai_requests_minute_user);token_limit:=effective_company_limit(o.id,'ai_input_tokens',p.ai_input_tokens_month);
 select count(*) into minute_used from usage_events where organization_id=o.id and user_id=p_user_id and metric='ai_request_reserved' and created_at>now()-interval '1 minute';if minute_used>=minute_limit then raise exception 'Per-minute Gemini limit reached';end if;select count(*) into day_used from usage_events where organization_id=o.id and metric='ai_request_reserved' and created_at>=current_date;if day_used>=day_limit then raise exception 'Daily Gemini limit reached';end if;
 insert into usage_counters values(o.id,'ai_requests',ms,me,0,now()) on conflict do nothing;select quantity into month_used from usage_counters where organization_id=o.id and metric='ai_requests' and period_start=ms for update;if month_used>=month_limit then raise exception 'Monthly Gemini request limit reached';end if;insert into usage_counters values(o.id,'ai_input_tokens',ms,me,0,now()) on conflict do nothing;select quantity into token_used from usage_counters where organization_id=o.id and metric='ai_input_tokens' and period_start=ms for update;if token_used+greatest(p_estimated_input_tokens,0)>token_limit then raise exception 'Monthly Gemini input-token limit reached';end if;
 update usage_counters set quantity=quantity+1,updated_at=now() where organization_id=o.id and metric='ai_requests' and period_start=ms;update usage_counters set quantity=quantity+greatest(p_estimated_input_tokens,0),updated_at=now() where organization_id=o.id and metric='ai_input_tokens' and period_start=ms;insert into usage_events(id,organization_id,user_id,metric,quantity,source,reference_id,status,metadata) values(rid,o.id,p_user_id,'ai_request_reserved',1,'gemini_edge',rid::text,'reserved',jsonb_build_object('mode',p_mode,'estimated_input_tokens',p_estimated_input_tokens));return rid;end$$;
revoke all on function public.reserve_ai_request(uuid,uuid,text,integer) from public,anon,authenticated;grant execute on function public.reserve_ai_request(uuid,uuid,text,integer) to service_role;

-- Override-aware Storage reservation and bandwidth enforcement.
create or replace function public.reserve_storage_upload(p_organization_id uuid,p_bytes bigint,p_file_name text,p_mime_type text)
returns uuid language plpgsql security definer set search_path=public as $$declare o organizations%rowtype;p subscription_plans%rowtype;used bigint;reserved bigint;files bigint;rid uuid:=gen_random_uuid();storage_limit bigint;file_limit bigint;file_size_limit bigint;begin
 if auth.uid() is null or not is_org_member(p_organization_id) then raise exception 'Membership required';end if;if not company_feature_allowed(p_organization_id,'uploads',true) then raise exception 'Uploads are disabled for this company';end if;if p_bytes<=0 then raise exception 'File is empty';end if;select * into o from organizations where id=p_organization_id for update;if o.commercial_status not in('active','trial') then raise exception 'Company access is %',o.commercial_status;end if;select pl.* into p from organization_subscriptions s join subscription_plans pl on pl.id=s.plan_id where s.organization_id=o.id and s.status in('active','trial');if not found then raise exception 'Active subscription required';end if;
 storage_limit:=effective_company_limit(o.id,'storage_bytes',p.max_storage_bytes);file_limit:=effective_company_limit(o.id,'files',p.max_files);file_size_limit:=effective_company_limit(o.id,'file_size_bytes',p.max_file_bytes);if p_bytes>file_size_limit then raise exception 'File exceeds company limit';end if;select coalesce(sum(size_bytes),0),count(*) into used,files from file_metadata where organization_id=o.id and removed_at is null;select coalesce(sum(bytes),0) into reserved from storage_reservations where organization_id=o.id and status='reserved' and expires_at>now();if files>=file_limit then raise exception 'File-count limit reached';end if;if used+reserved+p_bytes>storage_limit then raise exception 'Storage limit reached';end if;update storage_reservations set status='expired' where organization_id=o.id and status='reserved' and expires_at<=now();insert into storage_reservations(id,organization_id,user_id,bytes,file_name,mime_type) values(rid,o.id,auth.uid(),p_bytes,p_file_name,p_mime_type);return rid;end$$;
grant execute on function public.reserve_storage_upload(uuid,bigint,text,text) to authenticated;

create or replace function public.record_storage_download(p_organization_id uuid,p_object_path text,p_bytes bigint)
returns void language plpgsql security definer set search_path=public as $$declare ms date:=date_trunc('month',current_date)::date;me date:=(date_trunc('month',current_date)+interval '1 month'-interval '1 day')::date;p subscription_plans%rowtype;used bigint;lim bigint;begin
 if auth.uid() is null or not is_org_member(p_organization_id) then raise exception 'Membership required';end if;select pl.* into p from organization_subscriptions s join subscription_plans pl on pl.id=s.plan_id where s.organization_id=p_organization_id and s.status in('active','trial');if not found then raise exception 'Active subscription required';end if;lim:=effective_company_limit(p_organization_id,'bandwidth_bytes',p.max_bandwidth_bytes_month);insert into usage_counters values(p_organization_id,'bandwidth_bytes',ms,me,0,now()) on conflict do nothing;select quantity into used from usage_counters where organization_id=p_organization_id and metric='bandwidth_bytes' and period_start=ms for update;if used+greatest(p_bytes,0)>lim then raise exception 'Monthly download bandwidth limit reached';end if;update usage_counters set quantity=quantity+greatest(p_bytes,0),updated_at=now() where organization_id=p_organization_id and metric='bandwidth_bytes' and period_start=ms;insert into storage_usage_events(organization_id,user_id,event_type,object_path,bytes) values(p_organization_id,auth.uid(),'download',p_object_path,greatest(p_bytes,0));end$$;
grant execute on function public.record_storage_download(uuid,text,bigint) to authenticated;

-- Dashboard-only alert creation and periodic commercial maintenance.
create or replace function public.create_platform_alert() returns trigger language plpgsql security definer set search_path=public as $$begin
 if tg_table_name='system_incidents' and new.severity in('error','critical') then insert into platform_notifications(severity,title,body,component,organization_id) values(new.severity,'System incident: '||new.component,new.message,new.component,new.organization_id);end if;
 if tg_table_name='platform_support_tickets' and new.priority in('high','critical') then insert into platform_notifications(severity,title,body,component,organization_id) values(case when new.priority='critical' then 'critical' else 'warning' end,'Complaint #'||new.ticket_number||': '||new.subject,new.description,'platform_support',new.organization_id);end if;return new;end$$;
do $$ begin
 if not exists(select 1 from pg_trigger where tgname='incident_platform_alert' and not tgisinternal) then create trigger incident_platform_alert after insert on public.system_incidents for each row execute function public.create_platform_alert();end if;
 if not exists(select 1 from pg_trigger where tgname='ticket_platform_alert' and not tgisinternal) then create trigger ticket_platform_alert after insert on public.platform_support_tickets for each row execute function public.create_platform_alert();end if;
end $$;
create or replace function public.control_maintenance_tick() returns jsonb language plpgsql security definer set search_path=public as $$declare expired_comp int;expired_overrides int;begin
 if coalesce(current_setting('request.jwt.claim.role',true),'')<>'service_role' and not public.is_platform_admin() then raise exception 'Platform authority required';end if;
 with u as(update complimentary_access set revoked_at=now(),updated_at=now() where revoked_at is null and ends_at is not null and ends_at<=now() returning 1) select count(*) into expired_comp from u;
 with u as(update quota_overrides set active=false,updated_at=now() where active and ends_at is not null and ends_at<=now() returning 1) select count(*) into expired_overrides from u;
 insert into platform_notifications(severity,title,body,component,organization_id) select 'warning','Trial expires soon',o.name||' trial ends at '||o.trial_ends_at,'commercial',o.id from organizations o where o.commercial_status='trial' and o.trial_ends_at between now() and now()+interval '3 days' and not exists(select 1 from platform_notifications n where n.organization_id=o.id and n.title='Trial expires soon' and n.created_at>now()-interval '2 days');
 return jsonb_build_object('expired_complimentary',expired_comp,'expired_overrides',expired_overrides,'checked_at',now());end$$;
revoke all on function public.control_maintenance_tick() from public,anon;grant execute on function public.control_maintenance_tick() to authenticated,service_role;

-- Permission-aware replacements for Phase 8 platform actions.
create or replace function public.platform_set_company(p_organization_id uuid,p_status text,p_plan_code text default null,p_reason text default null) returns void language plpgsql security definer set search_path=public as $$declare plan_uuid uuid;subscription_state text;begin if not public.platform_has_permission('companies.manage') then raise exception 'Permission required';end if;if p_status not in('trial','active','past_due','suspended','cancelled','deletion_pending') then raise exception 'Invalid company status';end if;if p_plan_code is not null then select id into plan_uuid from subscription_plans where code=p_plan_code and active;if plan_uuid is null then raise exception 'Plan not found';end if;end if;update organizations set commercial_status=p_status,status_reason=p_reason,suspended_at=case when p_status='suspended' then now() else null end,deletion_scheduled_at=case when p_status='deletion_pending' then coalesce(deletion_scheduled_at,now()+interval '30 days') else null end,commercial_updated_at=now() where id=p_organization_id;subscription_state:=case when p_status in('active','trial','past_due','suspended','cancelled') then p_status else 'cancelled' end;update organization_subscriptions set plan_id=coalesce(plan_uuid,plan_id),status=subscription_state,updated_at=now() where organization_id=p_organization_id;insert into admin_action_logs(admin_user_id,action,target_type,target_id,organization_id,reason,details) values(auth.uid(),'company_commercial_updated','organization',p_organization_id::text,p_organization_id,p_reason,jsonb_build_object('status',p_status,'plan_code',p_plan_code));end$$;grant execute on function public.platform_set_company(uuid,text,text,text) to authenticated;
create or replace function public.platform_update_incident(p_incident_id uuid,p_status text) returns void language plpgsql security definer set search_path=public as $$begin if not public.platform_has_permission('incidents.manage') then raise exception 'Permission required';end if;if p_status not in('open','acknowledged','resolved') then raise exception 'Invalid incident status';end if;update system_incidents set status=p_status,resolved_at=case when p_status='resolved' then now() else null end,last_seen_at=now() where id=p_incident_id;insert into admin_action_logs(admin_user_id,action,target_type,target_id,reason) values(auth.uid(),'incident_status_changed','system_incident',p_incident_id::text,p_status);end$$;grant execute on function public.platform_update_incident(uuid,text) to authenticated;



