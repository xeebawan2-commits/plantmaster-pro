-- ============================================================
-- Schema for this section (auto-extracted from the repo / live snapshot)
-- ============================================================


-- ---------- TABLES ----------


-- [signup_requests]  source: R2-control-center.sql
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



-- ---------- FUNCTIONS / RPCs ----------


-- [control_delete_signup_request()]  source: R2-control-center.sql
create or replace function public.control_delete_signup_request(p_id uuid)
returns boolean language plpgsql security definer set search_path to 'public'
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Platform administrator required';
  end if;
  delete from public.signup_requests where id = p_id;
  return found;
end $$;


-- [control_purge_signup_requests()]  source: R2-control-center.sql
create or replace function public.control_purge_signup_requests(p_status text default 'rejected')
returns integer language plpgsql security definer set search_path to 'public'
as $$
declare n integer;
begin
  if not public.is_platform_admin() then
    raise exception 'Platform administrator required';
  end if;
  delete from public.signup_requests where status = p_status;
  get diagnostics n = row_count;
  return n;
end $$;


-- [control_invite_owner()]  source: R2-control-center.sql
create or replace function public.control_invite_owner(
  p_email text, p_company_name text,
  p_plant_name text default 'Main Plant',
  p_plan_code  text default 'trial',
  p_trial_days integer default 7,
  p_request_id uuid default null,
  p_notes      text default null
) returns public.owner_invitations
language plpgsql security definer set search_path to 'public'
as $$
declare inv public.owner_invitations%rowtype;
begin
  if not public.is_platform_admin() then
    raise exception 'Platform administrator required';
  end if;
  if coalesce(trim(p_email),'') = '' then raise exception 'Email is required'; end if;
  if coalesce(trim(p_company_name),'') = '' then raise exception 'Company name is required'; end if;
  if not exists (select 1 from public.subscription_plans where code = p_plan_code) then
    raise exception 'Unknown plan %', p_plan_code;
  end if;

  update public.owner_invitations
     set revoked_at = now()
   where lower(email) = lower(trim(p_email))
     and used_at is null and revoked_at is null;

  insert into public.owner_invitations
    (email, company_name, plant_name, plan_code, trial_days,
     signup_request_id, notes, created_by)
  values
    (lower(trim(p_email)), trim(p_company_name),
     coalesce(nullif(trim(p_plant_name),''),'Main Plant'),
     p_plan_code, greatest(coalesce(p_trial_days,0),0),
     p_request_id, p_notes, auth.uid())
  returning * into inv;

  if p_request_id is not null then
    update public.signup_requests
       set status='contacted', reviewed_by=auth.uid(), reviewed_at=now()
     where id = p_request_id;
  end if;

  return inv;
end $$;
