-- ============================================================
--  R3 — VERIFICATION
--
--  Read-only. Changes nothing. Run this in the Supabase SQL Editor
--  after R1 and R2 and check every row says what the Want column says.
--
--  Set the row-limit dropdown beside Run to "No limit".
-- ============================================================

select * from (

  -- ---------------- the create-organization fix ----------------
  select 1 as ord, 'create_organization exists' as check,
         case when exists (
           select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname='public' and p.proname='create_organization')
         then 'yes' else 'NO' end as result,
         'yes' as want

  union all
  select 2, 'subscription inserted before plant',
         case when position('organization_subscriptions' in def)
                   between 1 and position('into public.plants' in def)
              then 'yes' else 'NO — still broken' end,
         'yes'
    from (select pg_get_functiondef(p.oid) def
            from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.proname='create_organization' limit 1) a

  union all
  select 3, 'create_organization is invitation-gated',
         case when exists (
           select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname='public' and p.proname='create_organization'
              and pg_get_functiondef(p.oid) like '%owner_invitations%')
         then 'yes' else 'no (R1 only)' end,
         'yes after R2'

  -- ---------------- gatekeeper tables ----------------
  union all
  select 4, 'table signup_requests',
         case when to_regclass('public.signup_requests') is not null then 'yes' else 'NO' end, 'yes'
  union all
  select 5, 'table owner_invitations',
         case when to_regclass('public.owner_invitations') is not null then 'yes' else 'NO' end, 'yes'

  union all
  select 6, 'owner_invitations.created_org_id is ON DELETE SET NULL',
         coalesce((select case when c.confdeltype='n' then 'yes' else 'NO' end
                     from pg_constraint c
                     join pg_class t on t.oid=c.conrelid
                     join pg_namespace n on n.oid=t.relnamespace
                    where n.nspname='public' and t.relname='owner_invitations'
                      and c.conname='owner_invitations_created_org_id_fkey'),'missing'),
         'yes'

  -- ---------------- the six control RPCs ----------------
  union all
  select 7, 'control RPCs present',
         (select count(*)::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.proname in (
             'control_invite_owner','control_revoke_owner_invitation',
             'control_delete_company','control_delete_owner_invitation',
             'control_delete_signup_request','control_purge_signup_requests')),
         '6'

  -- every RPC the admin console calls
  union all
  select 8, 'all admin-console RPCs present',
         (select count(*)::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and p.proname in (
             'control_dashboard','control_companies','control_accounts','control_admins',
             'control_usage','control_storage','control_ai_usage','control_invite_owner',
             'control_delete_company','control_delete_signup_request',
             'control_purge_signup_requests','control_revoke_owner_invitation',
             'control_delete_owner_invitation','control_save_plan','control_set_complimentary',
             'control_adjust_usage','control_save_admin','control_qa_overview',
             'is_platform_admin','platform_tenant_overview','platform_set_company')),
         '21'

  -- ---------------- grants and policies ----------------
  union all
  select 9, 'delete grants on the two new tables',
         (select count(*)::text from information_schema.role_table_grants
           where table_schema='public'
             and table_name in ('signup_requests','owner_invitations')
             and privilege_type='DELETE' and grantee='authenticated'),
         '2'
  union all
  select 10, 'delete policies on the two new tables',
         (select count(*)::text from pg_policies
           where schemaname='public'
             and tablename in ('signup_requests','owner_invitations') and cmd='DELETE'),
         '2'
  union all
  select 11, 'RLS enabled on both new tables',
         (select count(*)::text from pg_class c join pg_namespace n on n.oid=c.relnamespace
           where n.nspname='public'
             and c.relname in ('signup_requests','owner_invitations') and c.relrowsecurity),
         '2'

  -- ---------------- plans and data health ----------------
  union all
  select 12, 'active subscription plans',
         (select count(*)::text from public.subscription_plans where active), '4 or more'
  union all
  select 13, 'companies with NO subscription (these are broken)',
         (select count(*)::text from public.organizations o
           where not exists (select 1 from public.organization_subscriptions s
                              where s.organization_id=o.id)), '0'
  union all
  select 14, 'companies with no owner',
         (select count(*)::text from public.organizations o
           where not exists (select 1 from public.organization_members m
                              where m.organization_id=o.id and m.role='owner' and m.active)), '0'
  union all
  select 15, 'plants whose organization is missing',
         (select count(*)::text from public.plants p
           where not exists (select 1 from public.organizations o where o.id=p.organization_id)), '0'

  -- ---------------- you can still get in ----------------
  union all
  select 16, 'platform admins configured',
         (select count(*)::text from public.platform_admins where active), '1 or more'

) t order by ord;


-- ============================================================
--  Repair for anything flagged by rows 13 and 14
--
--  Row 13: companies created before the fix have no subscription,
--  so their plant/worker/storage limits all fail. This attaches
--  the trial plan to any company missing one. Review the list
--  first, then uncomment and run.
-- ============================================================

-- select o.id, o.name, o.created_at
--   from public.organizations o
--  where not exists (select 1 from public.organization_subscriptions s
--                     where s.organization_id = o.id)
--  order by o.created_at;

-- insert into public.organization_subscriptions
--   (organization_id, plan_id, status, current_period_start, current_period_end)
-- select o.id,
--        (select id from public.subscription_plans where code='trial'),
--        'trial', now(), now() + interval '7 days'
--   from public.organizations o
--  where not exists (select 1 from public.organization_subscriptions s
--                     where s.organization_id = o.id);
