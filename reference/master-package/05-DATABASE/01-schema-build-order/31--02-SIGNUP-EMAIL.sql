-- ============================================================
--  PLANTMASTER PRO — SIGNUP ACKNOWLEDGEMENT EMAIL
--
--  Run this AFTER 01-GATEKEEPER.sql.
--
--  1. Adds ack_sent_at to signup_requests.
--  2. Adds a trigger that calls the signup-notify edge function
--     the moment an enquiry arrives, so the applicant gets
--     "thank you for applying" automatically.
--  3. Adds a 'free' plan so you can approve someone at no cost.
--
--  Safe to re-run.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Track that we acknowledged the enquiry
-- ------------------------------------------------------------
alter table public.signup_requests
  add column if not exists ack_sent_at timestamptz;


-- ------------------------------------------------------------
-- 2. A free plan you can grant from the Control Center
--    Same caps as Essential but zero price and no trial clock.
--    Use it for the founding customers and for Pakistan Synthetic.
-- ------------------------------------------------------------
insert into public.subscription_plans
  (code,name,description,currency,price_monthly,price_yearly,
   max_workers,max_plants,max_storage_bytes,max_files,max_file_bytes,
   ai_requests_month,ai_requests_day,ai_requests_minute_user,
   ai_input_tokens_month,ai_output_tokens_month,retention_days,active)
values
  ('free','Free','Complimentary access. 10 users, 1 plant, 10 GB.','PKR',0,0,
   10,1,10737418240,5000,52428800,
   500,50,3,2000000,800000,1095,true)
on conflict (code) do update set
  name=excluded.name, description=excluded.description,
  price_monthly=0, price_yearly=0,
  max_workers=excluded.max_workers, max_plants=excluded.max_plants,
  max_storage_bytes=excluded.max_storage_bytes,
  ai_requests_month=excluded.ai_requests_month,
  active=true, updated_at=now();


-- ------------------------------------------------------------
-- 3. OPTIONAL: fire the edge function from the database too
--
--    The website already calls signup-notify directly after it
--    inserts the row, and that path is tested. This trigger is a
--    BELT-AND-BRACES backup for enquiries created any other way
--    (by you in the SQL editor, or a future integration).
--
--    It needs the pg_net extension. I could NOT verify pg_net is
--    enabled on your project, so this section is commented out.
--    The edge function is idempotent -- it refuses to send twice
--    for the same row -- so enabling this cannot double-email.
--
--    To enable: Database -> Extensions -> search "pg_net" -> enable,
--    then uncomment everything between the BEGIN and END markers.
-- ------------------------------------------------------------

-- ===== BEGIN OPTIONAL pg_net TRIGGER =====
-- create extension if not exists pg_net with schema extensions;
--
-- create or replace function public.notify_signup_request()
-- returns trigger
-- language plpgsql
-- security definer
-- set search_path to 'public','extensions'
-- as $fn$
-- begin
--   perform extensions.net.http_post(
--     url     := 'https://dpmmenwziplixrgylapy.supabase.co/functions/v1/signup-notify',
--     headers := jsonb_build_object('Content-Type','application/json'),
--     body    := jsonb_build_object('request_id', new.id)
--   );
--   return new;
-- exception when others then
--   -- never let an email problem block the enquiry being saved
--   return new;
-- end $fn$;
--
-- drop trigger if exists trg_signup_request_notify on public.signup_requests;
-- create trigger trg_signup_request_notify
--   after insert on public.signup_requests
--   for each row execute function public.notify_signup_request();
-- ===== END OPTIONAL pg_net TRIGGER =====


-- ------------------------------------------------------------
-- 4. Re-sending an acknowledgement by hand
--
--    The Control Center's Resend button calls the edge function
--    over HTTP (not from SQL), so no pg_net is needed. Clearing
--    ack_sent_at lets the function send again for that row.
-- ------------------------------------------------------------
create or replace function public.control_clear_ack(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Platform administrator required';
  end if;
  update public.signup_requests set ack_sent_at = null where id = p_id;
  return found;
end $$;

grant execute on function public.control_clear_ack(uuid) to authenticated;


-- ============================================================
--  VERIFY
-- ============================================================
select 'ack_sent_at column' as check,
       case when exists(select 1 from information_schema.columns
                         where table_schema='public' and table_name='signup_requests'
                           and column_name='ack_sent_at') then 'yes' else 'NO' end as value
union all
select 'free plan',
       case when exists(select 1 from public.subscription_plans where code='free')
            then 'yes' else 'NO' end
union all
select 'pg_net (optional)',
       case when exists(select 1 from pg_extension where extname='pg_net')
            then 'enabled' else 'not enabled - fine, website calls directly' end
union all
select 'plans available',
       (select string_agg(code,', ' order by price_monthly)
          from public.subscription_plans where active);
