-- ============================================================
--  R2 — CONTROL CENTER: GATEKEEPER + THE SIX MISSING RPCs
--
--  PlantMaster Pro · project dpmmenwziplixrgylapy
--  Run AFTER R1. Safe to re-run.
--
--  WHY
--  ---
--  admin.hsbfix.org calls 15 RPCs. Six of them do not exist in the
--  live database, which is why Invite Owner, Approve, Delete company
--  and the signup queue do nothing:
--
--      control_invite_owner
--      control_revoke_owner_invitation
--      control_delete_company
--      control_delete_owner_invitation
--      control_delete_signup_request
--      control_purge_signup_requests
--
--  They were written in your master package
--  (01-schema-build-order/30--01-GATEKEEPER.sql and
--   32--03-DELETE-AND-FIXES.sql) but never applied: neither
--  owner_invitations nor signup_requests exists in the live schema.
--
--  This file consolidates both, with two corrections described
--  in section 5.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1. Website enquiries. A row here grants nothing; it is a lead.
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

drop policy if exists "signup_requests insert public" on public.signup_requests;
create policy "signup_requests insert public"
  on public.signup_requests for insert to anon, authenticated with check (true);

drop policy if exists "signup_requests admin read" on public.signup_requests;
create policy "signup_requests admin read"
  on public.signup_requests for select using (public.is_platform_admin());

drop policy if exists "signup_requests admin write" on public.signup_requests;
create policy "signup_requests admin write"
  on public.signup_requests for update
  using (public.is_platform_admin()) with check (public.is_platform_admin());

drop policy if exists "signup_requests admin delete" on public.signup_requests;
create policy "signup_requests admin delete"
  on public.signup_requests for delete using (public.is_platform_admin());

grant insert on public.signup_requests to anon, authenticated;
grant select, update, delete on public.signup_requests to authenticated;


-- ------------------------------------------------------------
-- 2. Owner invitations — the only route to a new workspace
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
  -- on delete set null: deleting a company must not be blocked by the
  -- invitation that created it, but the invitation is kept as history.
  created_org_id    uuid references public.organizations(id) on delete set null,
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

-- If the table already exists from an earlier partial run, its
-- created_org_id FK may lack "on delete set null", which would block
-- control_delete_company. Rebuild just that constraint, idempotently.
do $fk$
begin
  if exists (
    select 1 from pg_constraint c
      join pg_class t on t.oid = c.conrelid
      join pg_namespace n on n.oid = t.relnamespace
     where n.nspname = 'public'
       and t.relname = 'owner_invitations'
       and c.conname = 'owner_invitations_created_org_id_fkey'
       and c.confdeltype <> 'n'          -- 'n' = SET NULL
  ) then
    alter table public.owner_invitations
      drop constraint owner_invitations_created_org_id_fkey;
    alter table public.owner_invitations
      add  constraint owner_invitations_created_org_id_fkey
      foreign key (created_org_id) references public.organizations(id)
      on delete set null;
  end if;
end $fk$;

alter table public.owner_invitations enable row level security;

drop policy if exists "owner_invitations admin all" on public.owner_invitations;
create policy "owner_invitations admin all"
  on public.owner_invitations for all
  using (public.is_platform_admin()) with check (public.is_platform_admin());

drop policy if exists "owner_invitations admin delete" on public.owner_invitations;
create policy "owner_invitations admin delete"
  on public.owner_invitations for delete using (public.is_platform_admin());

grant select, insert, update, delete on public.owner_invitations to authenticated;


-- ------------------------------------------------------------
-- 3. Gate create_organization behind an invitation
--
--    This supersedes R1's ungated version. Keeps R1's ordering
--    fix (subscription before plant) and adds the gate.
-- ------------------------------------------------------------
create or replace function public.create_organization(org_name text, plant_name text)
returns table(organization_id uuid, plant_id uuid)
language plpgsql security definer set search_path to 'public'
as $function$
declare
  o uuid; p uuid;
  caller_email text;
  inv  public.owner_invitations%rowtype;
  plan public.subscription_plans%rowtype;
  trial_end timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select lower(email) into caller_email from auth.users where id = auth.uid();

  select * into inv
    from public.owner_invitations
   where lower(email) = caller_email
     and used_at is null and revoked_at is null and expires_at > now()
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

  insert into public.organizations (name, slug, created_by, commercial_status)
  values (
    coalesce(nullif(inv.company_name,''), org_name),
    lower(regexp_replace(coalesce(nullif(inv.company_name,''), org_name),
                         '[^a-zA-Z0-9]+','-','g'))
      || '-' || substr(gen_random_uuid()::text,1,6),
    auth.uid(),
    case when inv.trial_days > 0 then 'trial' else 'active' end
  )
  returning id into o;

  insert into public.organization_members (organization_id, user_id, role, active, created_at)
  values (o, auth.uid(), 'owner', true, now());

  trial_end := case when inv.trial_days > 0
                    then now() + make_interval(days => inv.trial_days) end;

  -- subscription BEFORE the plant (see R1)
  insert into public.organization_subscriptions
    (organization_id, plan_id, status,
     current_period_start, current_period_end, trial_ends_at)
  values
    (o, plan.id,
     case when inv.trial_days > 0 then 'trial' else 'active' end,
     now(), coalesce(trial_end, now() + interval '30 days'), trial_end);

  insert into public.plants (organization_id, name)
  values (o, coalesce(nullif(inv.plant_name,''), plant_name))
  returning id into p;

  insert into public.plant_members (plant_id, user_id, created_at)
  values (p, auth.uid(), now());

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

grant execute on function public.create_organization(text,text) to authenticated;


-- ------------------------------------------------------------
-- 4. The six missing Control Center RPCs
-- ------------------------------------------------------------
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

create or replace function public.control_revoke_owner_invitation(p_id uuid)
returns boolean language plpgsql security definer set search_path to 'public'
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Platform administrator required';
  end if;
  update public.owner_invitations set revoked_at = now()
   where id = p_id and used_at is null;
  return found;
end $$;

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

create or replace function public.control_delete_owner_invitation(p_id uuid)
returns boolean language plpgsql security definer set search_path to 'public'
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Platform administrator required';
  end if;
  delete from public.owner_invitations where id = p_id;
  return found;
end $$;

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


-- ------------------------------------------------------------
-- 5. control_delete_company — CORRECTED
--
--    The master-package version deleted from a hand-written list
--    of 20 tables. The live database has 61 tables carrying an
--    organization_id, so that version would either fail on a
--    foreign key or strand data in the other 41.
--
--    Checked against the live constraint export:
--      · 56 of 61 already have ON DELETE CASCADE on organization_id
--      · 4 more are ON DELETE SET NULL (admin_action_logs,
--        billing_events, platform_support_tickets, qa_environments)
--        and are deliberately kept as history
--      · ai_usage.organization_id has NO on-delete rule and is the
--        one table that actually blocks the delete
--      · ai_usage / manuals / notifications / report_dispatches
--        reference plants(id) with no rule, so plants must be
--        cleared after them
--
--    So: clear the blockers, then delete the organization and let
--    the 56 cascades do the rest. Simpler and complete.
-- ------------------------------------------------------------
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

grant execute on function public.control_invite_owner(text,text,text,text,integer,uuid,text) to authenticated;
grant execute on function public.control_revoke_owner_invitation(uuid)   to authenticated;
grant execute on function public.control_delete_signup_request(uuid)     to authenticated;
grant execute on function public.control_delete_owner_invitation(uuid)   to authenticated;
grant execute on function public.control_purge_signup_requests(text)     to authenticated;
grant execute on function public.control_delete_company(uuid,text)       to authenticated;

commit;


-- ============================================================
--  VERIFY — expect 'yes', 'yes', 6, and 'YES — locked'
-- ============================================================
select 'signup_requests table' as check,
       case when to_regclass('public.signup_requests')   is not null then 'yes' else 'NO' end as value
union all
select 'owner_invitations table',
       case when to_regclass('public.owner_invitations') is not null then 'yes' else 'NO' end
union all
select 'control RPCs present (want 6)',
       (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname='public' and p.proname in (
           'control_invite_owner','control_revoke_owner_invitation',
           'control_delete_company','control_delete_owner_invitation',
           'control_delete_signup_request','control_purge_signup_requests'))
union all
select 'create_organization gated',
       case when exists (
         select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
          where n.nspname='public' and p.proname='create_organization'
            and pg_get_functiondef(p.oid) like '%owner_invitations%'
       ) then 'YES — locked' else 'NO — still open' end;
