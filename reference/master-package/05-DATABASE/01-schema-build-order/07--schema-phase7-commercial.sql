-- PlantMaster Pro v4.6 Commercial Foundation
-- Additive/idempotent migration. Preserves all existing tenant and operational data.

create extension if not exists pgcrypto;

-- Company lifecycle. Existing companies are backfilled as active so this migration
-- cannot unexpectedly lock current customers out.
alter table public.organizations add column if not exists commercial_status text not null default 'active';
alter table public.organizations add column if not exists status_reason text;
alter table public.organizations add column if not exists trial_ends_at timestamptz;
alter table public.organizations add column if not exists suspended_at timestamptz;
alter table public.organizations add column if not exists deletion_scheduled_at timestamptz;
alter table public.organizations add column if not exists commercial_updated_at timestamptz not null default now();

do $$ begin
  if not exists(select 1 from pg_constraint where conname='organizations_commercial_status_check') then
    alter table public.organizations add constraint organizations_commercial_status_check
      check(commercial_status in ('trial','active','past_due','suspended','cancelled','deletion_pending'));
  end if;
end $$;

-- Platform administrators are created only through trusted SQL/service operations.
create table if not exists public.platform_admins(
  user_id uuid primary key references auth.users(id) on delete cascade,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id)
);

create or replace function public.is_platform_admin()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.platform_admins a where a.user_id=auth.uid() and a.active)
$$;
grant execute on function public.is_platform_admin() to authenticated;

create table if not exists public.subscription_plans(
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  active boolean not null default true,
  currency text not null default 'USD',
  price_monthly numeric(12,2) not null default 0,
  price_yearly numeric(12,2) not null default 0,
  max_workers integer not null default 5,
  max_plants integer not null default 1,
  max_storage_bytes bigint not null default 524288000,
  max_bandwidth_bytes_month bigint not null default 2147483648,
  max_files integer not null default 500,
  max_file_bytes bigint not null default 52428800,
  ai_requests_month integer not null default 50,
  ai_requests_day integer not null default 10,
  ai_requests_minute_user integer not null default 3,
  ai_input_tokens_month bigint not null default 250000,
  ai_output_tokens_month bigint not null default 100000,
  retention_days integer not null default 365,
  features jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.subscription_plans(code,name,description,price_monthly,price_yearly,max_workers,max_plants,max_storage_bytes,max_bandwidth_bytes_month,max_files,max_file_bytes,ai_requests_month,ai_requests_day,ai_requests_minute_user,ai_input_tokens_month,ai_output_tokens_month,retention_days,features)
values
('trial','Trial','Evaluation plan',0,0,5,1,524288000,2147483648,500,26214400,50,10,3,250000,100000,90,'{"gemini":true,"deep_search":false,"exports":true}'::jsonb),
('basic','Basic','Single-plant operations',29,290,15,1,5368709120,26843545600,2000,52428800,500,50,5,2500000,1000000,365,'{"gemini":true,"deep_search":false,"exports":true}'::jsonb),
('professional','Professional','Multi-plant maintenance operations',79,790,50,5,26843545600,107374182400,10000,104857600,5000,300,10,25000000,10000000,1095,'{"gemini":true,"deep_search":true,"exports":true,"daily_email":true}'::jsonb),
('enterprise','Enterprise','Custom limits and support',0,0,500,100,1073741824000,2199023255552,1000000,1073741824,1000000,100000,60,5000000000,2000000000,3650,'{"gemini":true,"deep_search":true,"exports":true,"daily_email":true,"custom_limits":true}'::jsonb)
on conflict(code) do update set name=excluded.name,description=excluded.description,features=excluded.features,updated_at=now();

create table if not exists public.organization_subscriptions(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plan_id uuid not null references public.subscription_plans(id),
  status text not null default 'trial',
  provider text,
  provider_customer_id text,
  provider_subscription_id text,
  current_period_start timestamptz not null default now(),
  current_period_end timestamptz,
  trial_ends_at timestamptz,
  cancel_at_period_end boolean not null default false,
  grace_ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_id)
);
do $$ begin
  if not exists(select 1 from pg_constraint where conname='organization_subscription_status_check') then
    alter table public.organization_subscriptions add constraint organization_subscription_status_check
      check(status in ('trial','active','past_due','suspended','cancelled'));
  end if;
end $$;

create table if not exists public.organization_entitlements(
  organization_id uuid not null references public.organizations(id) on delete cascade,
  entitlement text not null,
  enabled boolean not null,
  numeric_limit bigint,
  expires_at timestamptz,
  reason text,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id),
  primary key(organization_id,entitlement)
);

-- One row per organization, metric and billing period. Updates use row locks.
create table if not exists public.usage_counters(
  organization_id uuid not null references public.organizations(id) on delete cascade,
  metric text not null,
  period_start date not null,
  period_end date not null,
  quantity bigint not null default 0,
  updated_at timestamptz not null default now(),
  primary key(organization_id,metric,period_start)
);
create index if not exists usage_counters_org_period_idx on public.usage_counters(organization_id,period_start desc);

create table if not exists public.usage_events(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  metric text not null,
  quantity bigint not null default 1,
  source text,
  reference_id text,
  status text not null default 'recorded',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists usage_events_org_metric_time_idx on public.usage_events(organization_id,metric,created_at desc);
create index if not exists usage_events_user_metric_time_idx on public.usage_events(user_id,metric,created_at desc);

create table if not exists public.storage_usage_events(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  event_type text not null check(event_type in ('upload','download','delete','reconcile','restore')),
  object_path text,
  bytes bigint not null default 0,
  file_metadata_id uuid references public.file_metadata(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists storage_usage_org_time_idx on public.storage_usage_events(organization_id,created_at desc);
create table if not exists public.storage_reservations(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  bytes bigint not null,
  file_name text,
  mime_type text,
  status text not null default 'reserved' check(status in ('reserved','completed','cancelled','expired')),
  expires_at timestamptz not null default(now()+interval '15 minutes'),
  created_at timestamptz not null default now()
);
create index if not exists storage_reservations_org_status_idx on public.storage_reservations(organization_id,status,expires_at);

create table if not exists public.billing_events(
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  provider_event_id text not null unique,
  organization_id uuid references public.organizations(id) on delete set null,
  event_type text not null,
  status text not null default 'received',
  payload_hash text,
  error text,
  received_at timestamptz not null default now(),
  processed_at timestamptz
);

create table if not exists public.system_incidents(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  severity text not null check(severity in ('info','warning','error','critical')),
  component text not null,
  event_type text not null,
  message text not null,
  correlation_id text,
  details jsonb not null default '{}'::jsonb,
  status text not null default 'open' check(status in ('open','acknowledged','resolved')),
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  resolved_at timestamptz
);
create index if not exists incidents_status_severity_idx on public.system_incidents(status,severity,last_seen_at desc);

create table if not exists public.legal_documents(
  id uuid primary key default gen_random_uuid(),
  document_type text not null,
  version text not null,
  title text not null,
  content text not null,
  effective_at timestamptz not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(document_type,version)
);
create table if not exists public.legal_acceptances(
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.legal_documents(id),
  organization_id uuid references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  accepted_at timestamptz not null default now(),
  locale text,
  user_agent_hash text,
  unique(document_id,user_id)
);

create table if not exists public.data_retention_policies(
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  operational_days integer not null default 1095,
  audit_days integer not null default 2190,
  ai_prompt_days integer not null default 0,
  soft_delete_grace_days integer not null default 30,
  legal_hold boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);
create table if not exists public.deletion_requests(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  requested_by uuid not null references auth.users(id),
  request_type text not null check(request_type in ('user','organization','export_and_delete')),
  target_user_id uuid references auth.users(id),
  status text not null default 'requested' check(status in ('requested','verified','scheduled','cancelled','completed','failed')),
  reason text,
  scheduled_for timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now()
);

-- AI usage table additions for auditable provider requests.
alter table public.ai_usage add column if not exists request_id uuid;
alter table public.ai_usage add column if not exists model text;
alter table public.ai_usage add column if not exists status text default 'completed';
alter table public.ai_usage add column if not exists latency_ms integer;
alter table public.ai_usage add column if not exists error_code text;
alter table public.ai_usage add column if not exists source_count integer default 0;
create unique index if not exists ai_usage_request_id_idx on public.ai_usage(request_id) where request_id is not null;
create index if not exists ai_usage_org_time_idx on public.ai_usage(organization_id,created_at desc);

-- Backfill each existing organization onto Basic without altering its active status.
insert into public.organization_subscriptions(organization_id,plan_id,status,current_period_start,current_period_end)
select o.id,p.id,'active',now(),now()+interval '100 years'
from public.organizations o cross join public.subscription_plans p
where p.code='basic'
on conflict(organization_id) do nothing;
insert into public.data_retention_policies(organization_id)
select id from public.organizations on conflict(organization_id) do nothing;

-- New organizations start a 30-day trial automatically.
create or replace function public.create_default_commercial_records()
returns trigger language plpgsql security definer set search_path=public as $$
declare p uuid;
begin
  select id into p from public.subscription_plans where code='trial';
  update public.organizations set commercial_status='trial',trial_ends_at=now()+interval '30 days' where id=new.id;
  insert into public.organization_subscriptions(organization_id,plan_id,status,current_period_start,current_period_end,trial_ends_at)
    values(new.id,p,'trial',now(),now()+interval '30 days',now()+interval '30 days') on conflict(organization_id) do nothing;
  insert into public.data_retention_policies(organization_id) values(new.id) on conflict do nothing;
  return new;
end $$;
do $$ begin
  if not exists(select 1 from pg_trigger where tgname='organization_commercial_defaults' and not tgisinternal) then
    create trigger organization_commercial_defaults after insert on public.organizations for each row execute function public.create_default_commercial_records();
  end if;
end $$;

-- Owner-safe plan/usage summary. Commercial IDs from the browser are never
-- accepted unless the signed-in user is a member of that organization.
create or replace function public.organization_plan_summary(p_organization_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
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
end $$;
grant execute on function public.organization_plan_summary(uuid) to authenticated;

-- Atomic server-only AI reservation. Grant only to service_role. The Edge Function
-- calls this after independently verifying the JWT and organization membership.
create or replace function public.reserve_ai_request(p_organization_id uuid,p_user_id uuid,p_mode text,p_estimated_input_tokens integer default 0)
returns uuid language plpgsql security definer set search_path=public as $$
declare o public.organizations%rowtype; p public.subscription_plans%rowtype; request_uuid uuid:=gen_random_uuid(); token_used bigint; month_start date:=date_trunc('month',current_date)::date; month_end date:=(date_trunc('month',current_date)+interval '1 month'-interval '1 day')::date; used_month bigint; used_day bigint; used_minute bigint;
begin
  select * into o from public.organizations where id=p_organization_id for update;
  if not found then raise exception 'Organization not found'; end if;
  if o.commercial_status not in ('active','trial') then raise exception 'Company access is %',o.commercial_status; end if;
  if not exists(select 1 from public.organization_members m where m.organization_id=o.id and m.user_id=p_user_id and m.active) then raise exception 'Membership required'; end if;
  select pl.* into p from public.organization_subscriptions s join public.subscription_plans pl on pl.id=s.plan_id where s.organization_id=o.id and s.status in ('active','trial');
  if not found then raise exception 'Active subscription required'; end if;
  if coalesce((p.features->>'gemini')::boolean,false)=false then raise exception 'Gemini is not included in this plan'; end if;
  if p_mode='deep' and coalesce((p.features->>'deep_search')::boolean,false)=false then raise exception 'Deep Search is not included in this plan'; end if;
  select count(*) into used_minute from public.usage_events where organization_id=o.id and user_id=p_user_id and metric='ai_request_reserved' and created_at>now()-interval '1 minute';
  if used_minute>=p.ai_requests_minute_user then raise exception 'Per-minute Gemini limit reached'; end if;
  select count(*) into used_day from public.usage_events where organization_id=o.id and metric='ai_request_reserved' and created_at>=current_date;
  if used_day>=p.ai_requests_day then raise exception 'Daily Gemini limit reached'; end if;
  insert into public.usage_counters values(o.id,'ai_requests',month_start,month_end,0,now()) on conflict do nothing;
  select quantity into used_month from public.usage_counters where organization_id=o.id and metric='ai_requests' and period_start=month_start for update;
  if used_month>=p.ai_requests_month then raise exception 'Monthly Gemini request limit reached'; end if;
  insert into public.usage_counters values(o.id,'ai_input_tokens',month_start,month_end,0,now()) on conflict do nothing;
  select quantity into token_used from public.usage_counters where organization_id=o.id and metric='ai_input_tokens' and period_start=month_start for update;
  if token_used+greatest(p_estimated_input_tokens,0)>p.ai_input_tokens_month then raise exception 'Monthly Gemini input-token limit reached'; end if;
  update public.usage_counters set quantity=quantity+1,updated_at=now() where organization_id=o.id and metric='ai_requests' and period_start=month_start;
  update public.usage_counters set quantity=quantity+greatest(p_estimated_input_tokens,0),updated_at=now() where organization_id=o.id and metric='ai_input_tokens' and period_start=month_start;
  insert into public.usage_events(id,organization_id,user_id,metric,quantity,source,reference_id,status,metadata)
    values(request_uuid,o.id,p_user_id,'ai_request_reserved',1,'gemini_edge',request_uuid::text,'reserved',jsonb_build_object('mode',p_mode,'estimated_input_tokens',p_estimated_input_tokens));
  return request_uuid;
end $$;
revoke all on function public.reserve_ai_request(uuid,uuid,text,integer) from public,anon,authenticated;
grant execute on function public.reserve_ai_request(uuid,uuid,text,integer) to service_role;

create or replace function public.finalize_ai_request(p_request_id uuid,p_status text,p_provider text,p_model text,p_input_tokens integer,p_output_tokens integer,p_latency_ms integer,p_error_code text default null,p_source_count integer default 0)
returns void language plpgsql security definer set search_path=public as $$
declare e public.usage_events%rowtype; metric_name text; month_start date:=date_trunc('month',current_date)::date; month_end date:=(date_trunc('month',current_date)+interval '1 month'-interval '1 day')::date;
begin
  select * into e from public.usage_events where id=p_request_id for update;
  if not found then raise exception 'Usage reservation not found'; end if;
  if e.status<>'reserved' then return; end if;
  update public.usage_events set status=p_status,metadata=metadata||jsonb_build_object('provider',p_provider,'model',p_model,'input_tokens',p_input_tokens,'output_tokens',p_output_tokens,'latency_ms',p_latency_ms,'error_code',p_error_code,'source_count',p_source_count) where id=e.id;
  foreach metric_name in array array['ai_input_tokens','ai_output_tokens'] loop
    insert into public.usage_counters(organization_id,metric,period_start,period_end,quantity) values(e.organization_id,metric_name,month_start,month_end,0) on conflict do nothing;
  end loop;
  update public.usage_counters set quantity=greatest(0,quantity+coalesce(p_input_tokens,0)-coalesce((e.metadata->>'estimated_input_tokens')::integer,0)),updated_at=now() where organization_id=e.organization_id and metric='ai_input_tokens' and period_start=month_start;
  update public.usage_counters set quantity=quantity+greatest(coalesce(p_output_tokens,0),0),updated_at=now() where organization_id=e.organization_id and metric='ai_output_tokens' and period_start=month_start;
  insert into public.ai_usage(organization_id,user_id,provider,mode,input_tokens,output_tokens,created_at,request_id,model,status,latency_ms,error_code,source_count)
    values(e.organization_id,e.user_id,p_provider,e.metadata->>'mode',p_input_tokens,p_output_tokens,now(),e.id,p_model,p_status,p_latency_ms,p_error_code,p_source_count)
    on conflict(request_id) do nothing;
end $$;
revoke all on function public.finalize_ai_request(uuid,text,text,text,integer,integer,integer,text,integer) from public,anon,authenticated;
grant execute on function public.finalize_ai_request(uuid,text,text,text,integer,integer,integer,text,integer) to service_role;

-- Storage reservation used by the current web app. A future signed-upload Edge
-- Function will make this impossible to bypass outside the official client.
create or replace function public.reserve_storage_upload(p_organization_id uuid,p_bytes bigint,p_file_name text,p_mime_type text)
returns uuid language plpgsql security definer set search_path=public as $$
declare o public.organizations%rowtype; p public.subscription_plans%rowtype; used_bytes bigint; reserved_bytes bigint; file_count bigint; reservation uuid:=gen_random_uuid();
begin
  if auth.uid() is null or not public.is_org_member(p_organization_id) then raise exception 'Membership required'; end if;
  if p_bytes<=0 then raise exception 'File is empty'; end if;
  select * into o from public.organizations where id=p_organization_id for update;
  if o.commercial_status not in ('active','trial') then raise exception 'Company access is %',o.commercial_status; end if;
  select pl.* into p from public.organization_subscriptions s join public.subscription_plans pl on pl.id=s.plan_id where s.organization_id=o.id and s.status in ('active','trial');
  if not found then raise exception 'Active subscription required'; end if;
  if p_bytes>p.max_file_bytes then raise exception 'File exceeds plan limit of % bytes',p.max_file_bytes; end if;
  select coalesce(sum(size_bytes),0),count(*) into used_bytes,file_count from public.file_metadata where organization_id=o.id and removed_at is null;
  select coalesce(sum(bytes),0) into reserved_bytes from public.storage_reservations where organization_id=o.id and status='reserved' and expires_at>now();
  if file_count>=p.max_files then raise exception 'File-count limit reached'; end if;
  if used_bytes+reserved_bytes+p_bytes>p.max_storage_bytes then raise exception 'Storage limit reached'; end if;
  update public.storage_reservations set status='expired' where organization_id=o.id and status='reserved' and expires_at<=now();
  insert into public.storage_reservations(id,organization_id,user_id,bytes,file_name,mime_type) values(reservation,o.id,auth.uid(),p_bytes,p_file_name,p_mime_type);
  return reservation;
end $$;
grant execute on function public.reserve_storage_upload(uuid,bigint,text,text) to authenticated;

create or replace function public.finalize_storage_upload(p_reservation_id uuid,p_object_path text,p_file_metadata_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare r public.storage_reservations%rowtype;
begin
  select * into r from public.storage_reservations where id=p_reservation_id for update;
  if not found or r.user_id<>auth.uid() then raise exception 'Storage reservation not found'; end if;
  if r.status<>'reserved' or r.expires_at<=now() then raise exception 'Storage reservation expired'; end if;
  update public.storage_reservations set status='completed' where id=r.id;
  insert into public.storage_usage_events(organization_id,user_id,event_type,object_path,bytes,file_metadata_id) values(r.organization_id,r.user_id,'upload',p_object_path,r.bytes,p_file_metadata_id);
end $$;
grant execute on function public.finalize_storage_upload(uuid,text,uuid) to authenticated;

create or replace function public.cancel_storage_reservation(p_reservation_id uuid)
returns void language sql security definer set search_path=public as $$
  update public.storage_reservations set status='cancelled' where id=p_reservation_id and user_id=auth.uid() and status='reserved'
$$;
grant execute on function public.cancel_storage_reservation(uuid) to authenticated;

create or replace function public.record_storage_download(p_organization_id uuid,p_object_path text,p_bytes bigint)
returns void language plpgsql security definer set search_path=public as $$
declare month_start date:=date_trunc('month',current_date)::date;month_end date:=(date_trunc('month',current_date)+interval '1 month'-interval '1 day')::date;p public.subscription_plans%rowtype;used bigint;
begin
  if auth.uid() is null or not public.is_org_member(p_organization_id) then raise exception 'Membership required';end if;
  select pl.* into p from public.organization_subscriptions s join public.subscription_plans pl on pl.id=s.plan_id where s.organization_id=p_organization_id and s.status in ('active','trial');
  if not found then raise exception 'Active subscription required';end if;
  insert into public.usage_counters values(p_organization_id,'bandwidth_bytes',month_start,month_end,0,now()) on conflict do nothing;
  select quantity into used from public.usage_counters where organization_id=p_organization_id and metric='bandwidth_bytes' and period_start=month_start for update;
  if used+greatest(p_bytes,0)>p.max_bandwidth_bytes_month then raise exception 'Monthly download bandwidth limit reached';end if;
  update public.usage_counters set quantity=quantity+greatest(p_bytes,0),updated_at=now() where organization_id=p_organization_id and metric='bandwidth_bytes' and period_start=month_start;
  insert into public.storage_usage_events(organization_id,user_id,event_type,object_path,bytes) values(p_organization_id,auth.uid(),'download',p_object_path,greatest(p_bytes,0));
end $$;
grant execute on function public.record_storage_download(uuid,text,bigint) to authenticated;

-- Lifecycle write guard. Suspension preserves readable data but blocks normal
-- operational writes. Service-role billing/administration remains available.
create or replace function public.require_commercial_write_access()
returns trigger language plpgsql security definer set search_path=public as $$
declare oid uuid;state text;claim_role text;
begin
  if tg_op='DELETE' then oid:=old.organization_id;else oid:=new.organization_id;end if;
  claim_role:=coalesce(current_setting('request.jwt.claim.role',true),'');
  if claim_role='service_role' then if tg_op='DELETE' then return old;else return new;end if;end if;
  select commercial_status into state from public.organizations where id=oid;
  if state not in ('active','trial') then raise exception 'Company is %. Operational changes are disabled.',coalesce(state,'unavailable');end if;
  if tg_op='DELETE' then return old;else return new;end if;
end $$;
do $$ declare t text;n text;begin
  foreach t in array array['assets','work_orders','file_metadata','shift_assignments','attendance','checklist_templates','checklist_runs','maintenance_plans','spares','tools','notifications','support_threads','technical_experiences','manuals','problem_cases','organization_settings','invitations','report_dispatches','maintenance_completions','shift_handovers','daily_logs','tool_transactions','action_attachments'] loop
    if to_regclass('public.'||t) is not null then
      n:='commercial_write_guard_'||t;
      if not exists(select 1 from pg_trigger where tgname=n and not tgisinternal) then execute format('create trigger %I before insert or update or delete on public.%I for each row execute function public.require_commercial_write_access()',n,t);end if;
    end if;
  end loop;
end $$;

-- RLS
alter table public.platform_admins enable row level security;
alter table public.subscription_plans enable row level security;
alter table public.organization_subscriptions enable row level security;
alter table public.organization_entitlements enable row level security;
alter table public.usage_counters enable row level security;
alter table public.usage_events enable row level security;
alter table public.storage_usage_events enable row level security;
alter table public.storage_reservations enable row level security;
alter table public.billing_events enable row level security;
alter table public.system_incidents enable row level security;
alter table public.legal_documents enable row level security;
alter table public.legal_acceptances enable row level security;
alter table public.data_retention_policies enable row level security;
alter table public.deletion_requests enable row level security;

do $$ begin
  if not exists(select 1 from pg_policies where tablename='subscription_plans' and policyname='authenticated read active plans') then create policy "authenticated read active plans" on public.subscription_plans for select to authenticated using(active or public.is_platform_admin()); end if;
  if not exists(select 1 from pg_policies where tablename='organization_subscriptions' and policyname='owner reads subscription') then create policy "owner reads subscription" on public.organization_subscriptions for select to authenticated using(public.org_role(organization_id)='owner' or public.is_platform_admin()); end if;
  if not exists(select 1 from pg_policies where tablename='organization_entitlements' and policyname='owner reads entitlements') then create policy "owner reads entitlements" on public.organization_entitlements for select to authenticated using(public.org_role(organization_id)='owner' or public.is_platform_admin()); end if;
  if not exists(select 1 from pg_policies where tablename='usage_counters' and policyname='owner reads usage counters') then create policy "owner reads usage counters" on public.usage_counters for select to authenticated using(public.org_role(organization_id)='owner' or public.is_platform_admin()); end if;
  if not exists(select 1 from pg_policies where tablename='usage_events' and policyname='owner reads usage events') then create policy "owner reads usage events" on public.usage_events for select to authenticated using(public.org_role(organization_id)='owner' or public.is_platform_admin()); end if;
  if not exists(select 1 from pg_policies where tablename='storage_usage_events' and policyname='owner reads storage usage') then create policy "owner reads storage usage" on public.storage_usage_events for select to authenticated using(public.org_role(organization_id)='owner' or public.is_platform_admin()); end if;
  if not exists(select 1 from pg_policies where tablename='storage_reservations' and policyname='user reads own storage reservations') then create policy "user reads own storage reservations" on public.storage_reservations for select to authenticated using(user_id=auth.uid() or public.org_role(organization_id)='owner' or public.is_platform_admin()); end if;
  if not exists(select 1 from pg_policies where tablename='system_incidents' and policyname='members read own incidents') then create policy "members read own incidents" on public.system_incidents for select to authenticated using((organization_id is not null and public.is_org_member(organization_id)) or public.is_platform_admin()); end if;
  if not exists(select 1 from pg_policies where tablename='legal_documents' and policyname='authenticated read active legal docs') then create policy "authenticated read active legal docs" on public.legal_documents for select to authenticated using(active or public.is_platform_admin()); end if;
  if not exists(select 1 from pg_policies where tablename='legal_acceptances' and policyname='user manages own acceptance') then create policy "user manages own acceptance" on public.legal_acceptances for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid() and (organization_id is null or public.is_org_member(organization_id))); end if;
  if not exists(select 1 from pg_policies where tablename='data_retention_policies' and policyname='owner manages retention') then create policy "owner manages retention" on public.data_retention_policies for all to authenticated using(public.org_role(organization_id)='owner' or public.is_platform_admin()) with check(public.org_role(organization_id)='owner' or public.is_platform_admin()); end if;
  if not exists(select 1 from pg_policies where tablename='deletion_requests' and policyname='owner manages deletion requests') then create policy "owner manages deletion requests" on public.deletion_requests for all to authenticated using(public.org_role(organization_id)='owner' or requested_by=auth.uid() or public.is_platform_admin()) with check(public.org_role(organization_id)='owner' or requested_by=auth.uid() or public.is_platform_admin()); end if;
  if not exists(select 1 from pg_policies where tablename='platform_admins' and policyname='platform admins read self') then create policy "platform admins read self" on public.platform_admins for select to authenticated using(user_id=auth.uid()); end if;
end $$;

grant select on public.subscription_plans,public.organization_subscriptions,public.organization_entitlements,public.usage_counters,public.usage_events,public.storage_usage_events,public.storage_reservations,public.system_incidents,public.legal_documents to authenticated;
grant select,insert,update on public.legal_acceptances,public.data_retention_policies,public.deletion_requests to authenticated;
grant usage,select on all sequences in schema public to authenticated;
