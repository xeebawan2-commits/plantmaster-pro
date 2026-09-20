-- ============================================================
-- STEP 3  —  BLOCK VIEWER WRITES EVERYWHERE ELSE
--
-- HOW IT WORKS, AND WHY IT IS SAFE
--
-- It does NOT rewrite any of your existing policies. It adds
-- extra RESTRICTIVE policies. Postgres ANDs a restrictive policy
-- with whatever is already there, so this can only TIGHTEN
-- access, never loosen it. Your existing logic stays untouched.
--
-- It creates three policies per table: INSERT, UPDATE, DELETE.
-- SELECT is deliberately NOT touched, so viewers keep full read
-- access and the demo still shows everything.
--
-- Safe to run more than once.
-- ============================================================


-- ------------------------------------------------------------
-- 1. Who is a "viewer-only" user?
--
--    Someone whose every active membership is role = 'viewer'.
--    demo@hsbfix.org is exactly this.
--
--    A manager or owner returns FALSE and is unaffected.
--    Someone with no membership at all returns FALSE, so this
--    policy never interferes with signup or invitation flows.
-- ------------------------------------------------------------
create or replace function public.pm_is_viewer_only()
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  select
        exists (select 1 from organization_members
                 where user_id = auth.uid() and active and role =  'viewer')
    and not exists (select 1 from organization_members
                 where user_id = auth.uid() and active and role <> 'viewer')
$function$;

comment on function public.pm_is_viewer_only() is
  'True when every active membership for the caller is role=viewer. Used by the pm_block_viewer_* restrictive policies to make demo and viewer accounts read-only.';


-- ------------------------------------------------------------
-- 2. Apply to every table from the 40-row report.
--
--    DELIBERATELY EXCLUDED, with reasons:
--      legal_acceptances  a viewer must accept terms to use the
--                         app at all
--      audit_logs         INSERT is the audit trail writing
--                         itself; blocking it breaks logging
--      notifications      marking your own notification read is
--                         harmless for any role
-- ------------------------------------------------------------
do $$
declare
  t text;
  targets text[] := array[
    'action_attachments',
    'asset_status_history',
    'assets',
    'attendance',
    'checklist_items',
    'checklist_runs',
    'checklist_templates',
    'checklist_values',
    'code_registry',
    'condition_alarms',
    'condition_entity_links',
    'condition_recordings',
    'daily_logs',
    'file_metadata',
    'inventory_transactions',
    'invitations',
    'loto_procedures',
    'maintenance_completions',
    'maintenance_plans',
    'material_requests',
    'measurement_points',
    'organization_settings',
    'permits',
    'problem_cases',
    'purchase_orders',
    'report_dispatches',
    'scan_entity_links',
    'scan_pages',
    'scan_sessions',
    'sensor_devices',
    'shift_assignments',
    'shift_handovers',
    'spares',
    'support_messages',
    'support_threads',
    'technical_experiences',
    'work_orders'
  ];
begin
  foreach t in array targets loop

    -- skip anything that does not exist in this database
    if not exists (select 1 from pg_tables
                   where schemaname = 'public' and tablename = t) then
      continue;
    end if;

    -- re-runnable
    execute format('drop policy if exists pm_block_viewer_insert on public.%I', t);
    execute format('drop policy if exists pm_block_viewer_update on public.%I', t);
    execute format('drop policy if exists pm_block_viewer_delete on public.%I', t);

    -- INSERT: with check only
    execute format(
      'create policy pm_block_viewer_insert on public.%I '
      'as restrictive for insert '
      'with check ( not public.pm_is_viewer_only() )', t);

    -- UPDATE: both sides
    execute format(
      'create policy pm_block_viewer_update on public.%I '
      'as restrictive for update '
      'using ( not public.pm_is_viewer_only() ) '
      'with check ( not public.pm_is_viewer_only() )', t);

    -- DELETE: using only
    execute format(
      'create policy pm_block_viewer_delete on public.%I '
      'as restrictive for delete '
      'using ( not public.pm_is_viewer_only() )', t);

  end loop;
end $$;


-- ------------------------------------------------------------
-- 3. status
-- ------------------------------------------------------------
select
  count(distinct tablename) || ' tables are now read-only for viewer accounts'
    as result,
  count(*) || ' policies added' as detail
from pg_policies
where schemaname = 'public'
  and policyname like 'pm_block_viewer_%';
