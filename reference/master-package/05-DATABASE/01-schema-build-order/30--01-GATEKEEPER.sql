-- ============================================================
--  PLANTMASTER PRO — GATEKEEPER
--  Close the self-signup hole. Nobody gets a workspace unless
--  YOU approve it in the Control Center.
--
--  WHAT THIS DOES
--   1. Blocks public.create_organization for everyone except
--      an approved, unused invitation issued by you.
--   2. Adds an owner_invitations table the Control Center drives.
--   3. Adds a signup_requests table the website writes into.
--   4. Auto-attaches a subscription plan when YOU approve, so
--      the existing worker/plant/storage limits start working
--      immediately (today they fail with "Active subscription
--      required" because nothing ever creates a subscription).
--   5. Adds enforcement for the one limit that had none: AI usage.
--
--  RUN THIS in Supabase SQL Editor. Set the row-limit dropdown
--  beside Run to "No limit".
--
--  Safe to re-run.
-- ============================================================

-- ------------------------------------------------------------
-- 0. Make sure the plans you sell actually exist
-- ------------------------------------------------------------
insert into public.subscription_plans
  (code,name,description,currency,price_monthly,price_yearly,
   max_workers,max_plants,max_storage_bytes,max_files,max_file_bytes,
   ai_requests_month,ai_requests_day,ai_requests_minute_user,
   ai_input_tokens_month,ai_output_tokens_month,retention_days,active)
values
  ('essential','Essential','10 users, 1 plant, 10 GB','PKR',12000,120000,
   10,1,10737418240,5000,52428800,
   500,50,3,2000000,800000,1095,true),
  ('professional','Professional','25 users, 1 plant, 30 GB, full AI','PKR',24000,240000,
   25,1,32212254720,20000,104857600,
   3000,200,5,12000000,5000000,1095,true),
  ('enterprise','Enterprise','Quoted. Unlimited users.','PKR',0,0,
   999999,99,107374182400,999999,524288000,
   999999,99999,60,999999999,999999999,2190,true),
  ('trial','Trial (7 days)','Full Professional features for 7 days','PKR',0,0,
   25,1,5368709120,2000,52428800,
   300,60,5,2000000,800000,365,true)
on conflict (code) do update set
  name=excluded.name, description=excluded.description,
  currency=excluded.currency,
  price_monthly=excluded.price_monthly, price_yearly=excluded.price_yearly,
  max_workers=excluded.max_workers, max_plants=excluded.max_plants,
  max_storage_bytes=excluded.max_storage_bytes,
  max_files=excluded.max_files, max_file_bytes=excluded.max_file_bytes,
  ai_requests_month=excluded.ai_requests_month,
  ai_requests_day=excluded.ai_requests_day,
  ai_requests_minute_user=excluded.ai_requests_minute_user,
  ai_input_tokens_month=excluded.ai_input_tokens_month,
  ai_output_tokens_month=excluded.ai_output_tokens_month,
  retention_days=excluded.retention_days,
  active=true, updated_at=now();


-- ------------------------------------------------------------
-- 1. Enquiries captured from the website
--    The signup page posts here. Nothing is granted by writing
--    a row: it is a lead, not an account.
-- ------------------------------------------------------------
create table if not exists public.signup_requests (
  id             uuid primary key default gen_random_uuid(),
  company_name   text not null,
  contact_name   text not null,
  email          text not null,
  phone          text,
  city           text,
  plant_type     text,
  team_size      text,
  plan_interest  text,
  message        text,
  source         text default 'website',
  status         text not null default 'new'
                 check (status in ('new','contacted','approved','rejected','spam')),
  reviewed_by    uuid references auth.users(id),
  reviewed_at    timestamptz,
  review_notes   text,
  created_at     timestamptz not null default now()
);

create index if not exists signup_requests_status_idx
  on public.signup_requests(status, created_at desc);

alter table public.signup_requests enable row level security;

-- Anyone may submit an enquiry. Nobody may read them except platform admins.
drop policy if exists "signup_requests insert public" on public.signup_requests;
create policy "signup_requests insert public"
  on public.signup_requests for insert
  to anon, authenticated
  with check (true);

drop policy if exists "signup_requests admin read" on public.signup_requests;
create policy "signup_requests admin read"
  on public.signup_requests for select
  using (public.is_platform_admin());

drop policy if exists "signup_requests admin write" on public.signup_requests;
create policy "signup_requests admin write"
  on public.signup_requests for update
  using (public.is_platform_admin())
  with check (public.is_platform_admin());

grant insert on public.signup_requests to anon, authenticated;
grant select, update on public.signup_requests to authenticated;


-- ------------------------------------------------------------
-- 2. Owner invitations — the ONLY route to a new workspace
-- ------------------------------------------------------------
create table if not exists public.owner_invitations (
  id                uuid primary key default gen_random_uuid(),
  email             text not null,
  company_name      text not null,
  plant_name        text not null default 'Main Plant',
  plan_code         text not null default 'trial'
                    references public.subscription_plans(code),
  trial_days        integer not null default 7,
  signup_request_id uuid references public.signup_requests(id),
  token             uuid not null unique default gen_random_uuid(),
  expires_at        timestamptz not null default (now() + interval '14 days'),
  used_at           timestamptz,
  used_by           uuid references auth.users(id),
  created_org_id    uuid references public.organizations(id),
  revoked_at        timestamptz,
  notes             text,
  created_by        uuid not null references auth.users(id),
  created_at        timestamptz not null default now()
);

create unique index if not exists owner_invitations_email_live_idx
  on public.owner_invitations(lower(email))
  where used_at is null and revoked_at is null;

create index if not exists owner_invitations_token_idx
  on public.owner_invitations(token);

alter table public.owner_invitations enable row level security;

-- Only platform admins touch this table. The redemption path runs
-- SECURITY DEFINER so the invited user never needs read access.
drop policy if exists "owner_invitations admin all" on public.owner_invitations;
create policy "owner_invitations admin all"
  on public.owner_invitations for all
  using (public.is_platform_admin())
  with check (public.is_platform_admin());

grant select, insert, update on public.owner_invitations to authenticated;


-- ------------------------------------------------------------
-- 3. REPLACE create_organization — this is the actual fix
--
--    Before: any confirmed user could call it and self-provision
--            an unlimited workspace.
--    After:  it refuses unless the caller's own email matches a
--            live invitation that you issued.
-- ------------------------------------------------------------
create or replace function public.create_organization(org_name text, plant_name text)
returns table(organization_id uuid, plant_id uuid)
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  o uuid;
  p uuid;
  caller_email text;
  inv public.owner_invitations%rowtype;
  plan public.subscription_plans%rowtype;
  trial_end timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select lower(email) into caller_email from auth.users where id = auth.uid();

  -- The gate. No invitation, no workspace.
  select * into inv
    from public.owner_invitations
   where lower(email) = caller_email
     and used_at is null
     and revoked_at is null
     and expires_at > now()
   order by created_at desc
   limit 1;

  if inv.id is null then
    raise exception
      'Accounts are approved by HSB Fix Services. Please request access at https://hsbfix.org or contact support@hsbfix.org.'
      using errcode = 'check_violation';
  end if;

  select * into plan from public.subscription_plans where code = inv.plan_code;
  if plan.id is null then
    raise exception 'Configured plan % does not exist', inv.plan_code;
  end if;

  -- Use the names YOU approved, not whatever was typed in the form.
  insert into public.organizations(name, slug, created_by, commercial_status)
  values (
    coalesce(nullif(inv.company_name,''), org_name),
    lower(regexp_replace(coalesce(nullif(inv.company_name,''), org_name),
                         '[^a-zA-Z0-9]+','-','g'))
      || '-' || substr(gen_random_uuid()::text,1,6),
    auth.uid(),
    'trial'
  )
  returning id into o;

  insert into public.organization_members values (o, auth.uid(), 'owner', true, now());

  -- Subscription FIRST: enforce_plant_plan_limit refuses to create a
  -- plant when no active subscription exists.
  trial_end := case when inv.trial_days > 0
                    then now() + make_interval(days => inv.trial_days)
                    else null end;

  insert into public.organization_subscriptions
    (organization_id, plan_id, status, current_period_start,
     current_period_end, trial_ends_at)
  values
    (o, plan.id,
     case when inv.trial_days > 0 then 'trial' else 'active' end,
     now(),
     coalesce(trial_end, now() + interval '30 days'),
     trial_end);

  insert into public.plants(organization_id, name)
  values (o, coalesce(nullif(inv.plant_name,''), plant_name))
  returning id into p;

  insert into public.plant_members values (p, auth.uid(), now());

  update public.owner_invitations
     set used_at = now(), used_by = auth.uid(), created_org_id = o
   where id = inv.id;

  if inv.signup_request_id is not null then
    update public.signup_requests
       set status = 'approved', reviewed_at = now()
     where id = inv.signup_request_id;
  end if;

  return query select o, p;
end
$function$;


-- ------------------------------------------------------------
-- 4. Control Center helpers
-- ------------------------------------------------------------

-- Issue an invitation (this is what the Invite Owner button should call)
create or replace function public.control_invite_owner(
  p_email        text,
  p_company_name text,
  p_plant_name   text default 'Main Plant',
  p_plan_code    text default 'trial',
  p_trial_days   integer default 7,
  p_request_id   uuid default null,
  p_notes        text default null
) returns public.owner_invitations
language plpgsql
security definer
set search_path to 'public'
as $$
declare inv public.owner_invitations%rowtype;
begin
  if not public.is_platform_admin() then
    raise exception 'Platform administrator required';
  end if;
  if coalesce(trim(p_email),'') = '' then raise exception 'Email is required'; end if;
  if coalesce(trim(p_company_name),'') = '' then raise exception 'Company name is required'; end if;

  -- one live invitation per email
  update public.owner_invitations
     set revoked_at = now()
   where lower(email) = lower(trim(p_email))
     and used_at is null and revoked_at is null;

  insert into public.owner_invitations
    (email, company_name, plant_name, plan_code, trial_days,
     signup_request_id, notes, created_by)
  values
    (lower(trim(p_email)), trim(p_company_name), coalesce(nullif(trim(p_plant_name),''),'Main Plant'),
     p_plan_code, greatest(coalesce(p_trial_days,0),0), p_request_id, p_notes, auth.uid())
  returning * into inv;

  if p_request_id is not null then
    update public.signup_requests
       set status='contacted', reviewed_by=auth.uid(), reviewed_at=now()
     where id=p_request_id;
  end if;

  return inv;
end $$;

-- Revoke an unused invitation
create or replace function public.control_revoke_owner_invitation(p_id uuid)
returns boolean
language plpgsql security definer set search_path to 'public'
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Platform administrator required';
  end if;
  update public.owner_invitations
     set revoked_at = now()
   where id = p_id and used_at is null;
  return found;
end $$;

-- Change a company's plan, which immediately changes its user/plant/storage caps
create or replace function public.control_set_plan(
  p_org uuid, p_plan_code text, p_status text default 'active'
) returns boolean
language plpgsql security definer set search_path to 'public'
as $$
declare pid uuid;
begin
  if not public.is_platform_admin() then
    raise exception 'Platform administrator required';
  end if;
  select id into pid from public.subscription_plans where code=p_plan_code;
  if pid is null then raise exception 'Unknown plan %', p_plan_code; end if;

  if exists (select 1 from public.organization_subscriptions where organization_id=p_org) then
    update public.organization_subscriptions
       set plan_id=pid, status=p_status, updated_at=now()
     where organization_id=p_org;
  else
    insert into public.organization_subscriptions
      (organization_id, plan_id, status, current_period_start, current_period_end)
    values (p_org, pid, p_status, now(), now()+interval '30 days');
  end if;

  update public.organizations
     set commercial_status = case when p_status in ('active','trial')
                                  then p_status else 'suspended' end
   where id = p_org;
  return true;
end $$;

grant execute on function public.control_invite_owner(text,text,text,text,integer,uuid,text) to authenticated;
grant execute on function public.control_revoke_owner_invitation(uuid) to authenticated;
grant execute on function public.control_set_plan(uuid,text,text) to authenticated;


-- ------------------------------------------------------------
-- 5. AI usage enforcement — the one quota with no teeth
--
--    subscription_plans already carries ai_requests_month /
--    ai_requests_day / ai_requests_minute_user, but nothing
--    checked them. Call this before serving an AI request.
-- ------------------------------------------------------------
create or replace function public.check_ai_quota(p_org uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  p public.subscription_plans%rowtype;
  o public.organizations%rowtype;
  lim_month bigint; lim_day bigint; lim_min bigint;
  used_month bigint; used_day bigint; used_min bigint;
begin
  if auth.uid() is null or not public.is_org_member(p_org) then
    raise exception 'Membership required';
  end if;

  select * into o from public.organizations where id=p_org;
  if o.commercial_status not in ('active','trial') then
    raise exception 'Company access is %', o.commercial_status;
  end if;

  if not public.company_feature_allowed(p_org,'ai',true) then
    raise exception 'AI features are disabled for this company';
  end if;

  select pl.* into p
    from public.organization_subscriptions s
    join public.subscription_plans pl on pl.id = s.plan_id
   where s.organization_id = p_org and s.status in ('active','trial');
  if not found then raise exception 'Active subscription required'; end if;

  lim_month := public.effective_company_limit(p_org,'ai_requests_month', p.ai_requests_month);
  lim_day   := public.effective_company_limit(p_org,'ai_requests_day',   p.ai_requests_day);
  lim_min   := public.effective_company_limit(p_org,'ai_requests_minute_user', p.ai_requests_minute_user);

  select count(*) into used_month from public.ai_usage
   where organization_id=p_org and created_at >= date_trunc('month', now());
  select count(*) into used_day from public.ai_usage
   where organization_id=p_org and created_at >= date_trunc('day', now());
  select count(*) into used_min from public.ai_usage
   where organization_id=p_org and user_id=auth.uid()
     and created_at >= now() - interval '1 minute';

  if used_min >= lim_min then
    raise exception 'Too many AI requests. Wait a moment and try again.';
  end if;
  if used_day >= lim_day then
    raise exception 'Daily AI limit of % requests reached for your plan.', lim_day;
  end if;
  if used_month >= lim_month then
    raise exception 'Monthly AI limit of % requests reached. Contact HSB Fix Services to increase it.', lim_month;
  end if;

  return jsonb_build_object(
    'allowed', true,
    'month_used', used_month, 'month_limit', lim_month,
    'day_used', used_day,     'day_limit', lim_day
  );
end $$;

grant execute on function public.check_ai_quota(uuid) to authenticated;


-- ------------------------------------------------------------
-- 6. One view the Control Center can read for the whole picture
-- ------------------------------------------------------------
create or replace view public.control_company_overview as
select
  o.id                        as organization_id,
  o.name                      as company_name,
  o.commercial_status,
  pl.code                     as plan_code,
  pl.name                     as plan_name,
  s.status                    as subscription_status,
  s.trial_ends_at,
  s.current_period_end,
  public.effective_company_limit(o.id,'workers', pl.max_workers)       as worker_limit,
  (select count(*) from public.organization_members m
     where m.organization_id=o.id and m.active)                        as workers_used,
  public.effective_company_limit(o.id,'plants', pl.max_plants)         as plant_limit,
  (select count(*) from public.plants p where p.organization_id=o.id)  as plants_used,
  public.effective_company_limit(o.id,'storage_bytes', pl.max_storage_bytes) as storage_limit,
  (select coalesce(sum(f.size_bytes),0) from public.file_metadata f
     where f.organization_id=o.id and f.removed_at is null)            as storage_used,
  public.effective_company_limit(o.id,'ai_requests_month', pl.ai_requests_month) as ai_limit_month,
  (select count(*) from public.ai_usage a
     where a.organization_id=o.id
       and a.created_at >= date_trunc('month', now()))                 as ai_used_month,
  o.created_at
from public.organizations o
left join public.organization_subscriptions s
       on s.organization_id = o.id and s.status in ('active','trial')
left join public.subscription_plans pl on pl.id = s.plan_id;

grant select on public.control_company_overview to authenticated;


-- ============================================================
--  VERIFY
-- ============================================================
select 'plans seeded'            as check, count(*)::text as value from public.subscription_plans where active
union all
select 'signup_requests table',   case when to_regclass('public.signup_requests') is not null then 'yes' else 'NO' end
union all
select 'owner_invitations table', case when to_regclass('public.owner_invitations') is not null then 'yes' else 'NO' end
union all
select 'create_organization gated',
       case when exists (
         select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
          where n.nspname='public' and p.proname='create_organization'
            and pg_get_functiondef(p.oid) like '%owner_invitations%'
       ) then 'YES — locked' else 'NO — still open' end
union all
select 'orgs with no subscription',
       (select count(*)::text from public.organizations o
         where not exists (select 1 from public.organization_subscriptions s
                            where s.organization_id=o.id));
