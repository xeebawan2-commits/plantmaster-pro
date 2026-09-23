-- ============================================================
-- Schema for this section (auto-extracted from the repo / live snapshot)
-- ============================================================


-- ---------- TABLES ----------


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


-- [control_save_plan()]  source: 02-function-source.sql (LIVE snapshot)
CREATE OR REPLACE FUNCTION public.control_save_plan(p_code text, p_name text, p_description text, p_price_monthly numeric, p_price_yearly numeric, p_max_workers integer, p_max_plants integer, p_storage bigint, p_bandwidth bigint, p_max_files integer, p_max_file bigint, p_ai_month integer, p_ai_day integer, p_ai_minute integer, p_input_tokens bigint, p_output_tokens bigint, p_retention integer, p_features jsonb, p_active boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$declare pid uuid;begin
 if not public.platform_has_permission('plans.manage') then raise exception 'Permission required';end if;
 insert into subscription_plans(code,name,description,price_monthly,price_yearly,max_workers,max_plants,max_storage_bytes,max_bandwidth_bytes_month,max_files,max_file_bytes,ai_requests_month,ai_requests_day,ai_requests_minute_user,ai_input_tokens_month,ai_output_tokens_month,retention_days,features,active,updated_at) values(p_code,p_name,p_description,p_price_monthly,p_price_yearly,p_max_workers,p_max_plants,p_storage,p_bandwidth,p_max_files,p_max_file,p_ai_month,p_ai_day,p_ai_minute,p_input_tokens,p_output_tokens,p_retention,p_features,p_active,now()) on conflict(code) do update set name=excluded.name,description=excluded.description,price_monthly=excluded.price_monthly,price_yearly=excluded.price_yearly,max_workers=excluded.max_workers,max_plants=excluded.max_plants,max_storage_bytes=excluded.max_storage_bytes,max_bandwidth_bytes_month=excluded.max_bandwidth_bytes_month,max_files=excluded.max_files,max_file_bytes=excluded.max_file_bytes,ai_requests_month=excluded.ai_requests_month,ai_requests_day=excluded.ai_requests_day,ai_requests_minute_user=excluded.ai_requests_minute_user,ai_input_tokens_month=excluded.ai_input_tokens_month,ai_output_tokens_month=excluded.ai_output_tokens_month,retention_days=excluded.retention_days,features=excluded.features,active=excluded.active,updated_at=now() returning id into pid;
 insert into admin_action_logs(admin_user_id,action,target_type,target_id,details) values(auth.uid(),'plan_saved','subscription_plan',pid::text,jsonb_build_object('code',p_code,'active',p_active));return pid;end$function$;
