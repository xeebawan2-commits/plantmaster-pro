-- PlantMaster v1.3.2 — AI usage finalization and stale reservation repair
-- Safe: preserves AI history; replaces a partial unique index with an equivalent
-- full unique index (PostgreSQL still allows multiple NULL request IDs).

drop index if exists public.ai_usage_request_id_idx;
create unique index if not exists ai_usage_request_id_idx on public.ai_usage(request_id);

create or replace function public.finalize_ai_request(
 p_request_id uuid,p_status text,p_provider text,p_model text,p_input_tokens integer,p_output_tokens integer,
 p_latency_ms integer,p_error_code text default null,p_source_count integer default 0
) returns void language plpgsql security definer set search_path=public as $$
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
end $$;
revoke all on function public.finalize_ai_request(uuid,text,text,text,integer,integer,integer,text,integer) from public,anon,authenticated;
grant execute on function public.finalize_ai_request(uuid,text,text,text,integer,integer,integer,text,integer) to service_role;

create or replace function public.release_stale_ai_reservations(p_older_than interval default interval '5 minutes')
returns integer language plpgsql security definer set search_path=public as $$
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
end $$;
revoke all on function public.release_stale_ai_reservations(interval) from public,anon,authenticated;
grant execute on function public.release_stale_ai_reservations(interval) to service_role;

-- Reconcile reservations left behind by the old finalizer during this deployment.
-- SQL Editor executes with platform authority.
select public.release_stale_ai_reservations(interval '5 minutes') as released_stale_reservations;
notify pgrst,'reload schema';
