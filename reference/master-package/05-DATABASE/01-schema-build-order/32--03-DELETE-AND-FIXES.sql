-- ============================================================
--  PLANTMASTER PRO — DELETE SUPPORT + CONTROL CENTER FIXES
--
--  Run AFTER 01-GATEKEEPER.sql and 02-SIGNUP-EMAIL.sql.
--
--  WHY DELETE DID NOT WORK
--  01-GATEKEEPER.sql granted select/insert/update on
--  signup_requests and owner_invitations, but never DELETE, and
--  created no DELETE policy. PostgREST then reports success while
--  affecting zero rows -- the button "works" and nothing happens.
--
--  Safe to re-run.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Let platform admins delete enquiries and invitations
-- ------------------------------------------------------------
grant delete on public.signup_requests   to authenticated;
grant delete on public.owner_invitations to authenticated;

drop policy if exists "signup_requests admin delete" on public.signup_requests;
create policy "signup_requests admin delete"
  on public.signup_requests for delete
  using (public.is_platform_admin());

drop policy if exists "owner_invitations admin delete" on public.owner_invitations;
create policy "owner_invitations admin delete"
  on public.owner_invitations for delete
  using (public.is_platform_admin());


-- ------------------------------------------------------------
-- 2. Bulk cleanup helpers for the Control Center
-- ------------------------------------------------------------
create or replace function public.control_delete_signup_request(p_id uuid)
returns boolean
language plpgsql security definer set search_path to 'public'
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Platform administrator required';
  end if;
  delete from public.signup_requests where id = p_id;
  return found;
end $$;

create or replace function public.control_delete_owner_invitation(p_id uuid)
returns boolean
language plpgsql security definer set search_path to 'public'
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Platform administrator required';
  end if;
  delete from public.owner_invitations where id = p_id;
  return found;
end $$;

-- Clear out rejected/spam enquiries in one go
create or replace function public.control_purge_signup_requests(p_status text default 'rejected')
returns integer
language plpgsql security definer set search_path to 'public'
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

grant execute on function public.control_delete_signup_request(uuid)   to authenticated;
grant execute on function public.control_delete_owner_invitation(uuid) to authenticated;
grant execute on function public.control_purge_signup_requests(text)   to authenticated;


-- ------------------------------------------------------------
-- 3. Delete an entire company and everything under it
--
--    There was no way to remove a company from the Control
--    Center at all. This removes the tenant rows in FK-safe
--    order. It does NOT delete auth.users -- use the existing
--    platform_delete_user for that, deliberately separate so
--    you cannot wipe a login by accident.
-- ------------------------------------------------------------
create or replace function public.control_delete_company(
  p_org uuid,
  p_confirmation text
) returns jsonb
language plpgsql security definer set search_path to 'public'
as $$
declare
  org_name text;
  deleted jsonb := '{}'::jsonb;
  n integer;
begin
  if not public.is_platform_admin() then
    raise exception 'Platform administrator required';
  end if;

  select name into org_name from public.organizations where id = p_org;
  if org_name is null then raise exception 'Company not found'; end if;

  if p_confirmation is distinct from org_name then
    raise exception 'Type the company name exactly to confirm: %', org_name;
  end if;

  -- children first, deepest dependencies before their parents
  delete from public.purchase_order_lines
    where purchase_order_id in (select id from public.purchase_orders where organization_id = p_org);
  delete from public.checklist_items
    where template_id in (select id from public.checklist_templates where organization_id = p_org);

  delete from public.purchase_orders      where organization_id = p_org;
  delete from public.checklist_templates  where organization_id = p_org;
  delete from public.work_orders          where organization_id = p_org;
  delete from public.maintenance_plans    where organization_id = p_org;
  delete from public.daily_logs           where organization_id = p_org;
  delete from public.attendance           where organization_id = p_org;
  delete from public.spares               where organization_id = p_org;
  delete from public.tools                where organization_id = p_org;
  delete from public.suppliers            where organization_id = p_org;
  delete from public.assets               where organization_id = p_org;
  delete from public.manuals              where organization_id = p_org;
  delete from public.file_metadata        where organization_id = p_org;
  delete from public.ai_usage             where organization_id = p_org;
  delete from public.invitations          where organization_id = p_org;

  delete from public.plant_members
    where plant_id in (select id from public.plants where organization_id = p_org);
  delete from public.plants               where organization_id = p_org;
  delete from public.organization_members where organization_id = p_org;
  delete from public.organization_subscriptions where organization_id = p_org;

  delete from public.owner_invitations    where created_org_id = p_org;

  delete from public.organizations where id = p_org;
  get diagnostics n = row_count;

  return jsonb_build_object('deleted', n > 0, 'company', org_name);
exception when others then
  raise exception 'Could not delete %: %', org_name, sqlerrm;
end $$;

grant execute on function public.control_delete_company(uuid,text) to authenticated;


-- ============================================================
--  VERIFY
-- ============================================================
select 'delete policies' as check,
       (select count(*)::text from pg_policies
         where schemaname='public'
           and tablename in ('signup_requests','owner_invitations')
           and cmd='DELETE') as value
union all
select 'delete grants',
       (select count(*)::text from information_schema.role_table_grants
         where table_schema='public'
           and table_name in ('signup_requests','owner_invitations')
           and privilege_type='DELETE' and grantee='authenticated')
union all
select 'helper functions',
       (select count(*)::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
         where n.nspname='public'
           and p.proname in ('control_delete_signup_request',
                             'control_delete_owner_invitation',
                             'control_purge_signup_requests',
                             'control_delete_company'));
