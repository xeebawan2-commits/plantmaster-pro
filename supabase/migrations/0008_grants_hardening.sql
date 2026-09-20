-- ===========================================================================
-- PlantMaster Pro — 0008 grants & hardening (runs last)
--
-- Re-applies privileges across every object created by the preceding
-- migrations and closes the default-privilege gaps that make a Supabase
-- project leak data: anon must reach nothing but explicitly public reference
-- tables, and future tables must not silently inherit broad access.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Baseline: revoke everything from anon, then hand back only what is public.
-- ---------------------------------------------------------------------------
revoke all on all tables    in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke all on all functions in schema public from anon;

grant usage on schema public to anon, authenticated;

grant select, insert, update, delete on all tables    in schema public to authenticated;
grant usage, select                  on all sequences in schema public to authenticated;

-- Public reference data used by the marketing site before sign-in.
grant select on public.subscription_plans to anon;
grant select on public.legal_documents    to anon;

-- ---------------------------------------------------------------------------
-- Tables the client must never touch directly. RLS already denies them, but
-- removing the grant means PostgREST will not even expose a writable route.
-- ---------------------------------------------------------------------------
revoke insert, update, delete on public.audit_logs             from authenticated;
grant  insert                 on public.audit_logs             to   authenticated;

revoke insert, update, delete on public.inventory_transactions from authenticated;
revoke insert, update, delete on public.tool_transactions      from authenticated;
revoke all                    on public.storage_reservations   from authenticated;
grant  select                 on public.storage_reservations   to   authenticated;
revoke all                    on public.storage_usage_events   from authenticated;
grant  select                 on public.storage_usage_events   to   authenticated;
revoke insert, update, delete on public.platform_admins        from authenticated;
revoke insert, update, delete on public.subscription_plans     from authenticated;
revoke update, delete         on public.legal_documents        from authenticated;

-- ---------------------------------------------------------------------------
-- Default privileges for anything added later.
-- ---------------------------------------------------------------------------
alter default privileges in schema public
  grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public
  grant usage, select on sequences to authenticated;
alter default privileges in schema public
  revoke all on tables from anon;
alter default privileges in schema public
  revoke all on functions from anon;

-- ---------------------------------------------------------------------------
-- Function execution: authenticated only, except the two helpers the public
-- marketing site needs. Internal/cron routines stay service_role-only.
-- ---------------------------------------------------------------------------
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure::text as sig, p.proname
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
  loop
    execute format('revoke all on function %s from public, anon', r.sig);

    if r.proname in ('purge_expired_soft_deletes','expire_storage_reservations') then
      -- cron / service_role only
      execute format('revoke all on function %s from authenticated', r.sig);
    else
      execute format('grant execute on function %s to authenticated', r.sig);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Realtime. The app subscribes to postgres_changes for live collaboration;
-- Supabase still applies RLS to realtime payloads, so only the tenant's own
-- rows are delivered.
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array[
      'work_orders','assets','notifications','checklist_runs','material_requests',
      'support_messages','support_threads','condition_recordings','purchase_orders']
    loop
      begin
        execute format('alter publication supabase_realtime add table public.%I', t);
      exception
        when duplicate_object then null;
        when others then raise notice 'realtime: could not add % (%)', t, sqlerrm;
      end;
    end loop;
  else
    raise notice 'publication supabase_realtime not present — skipping realtime wiring';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- Performance: RLS policies call is_org_member()/has_org_role() per row, and
-- both read organization_members. This partial index is the one that keeps
-- those lookups off a sequential scan.
-- ---------------------------------------------------------------------------
create index if not exists org_members_auth_idx
  on public.organization_members(user_id, organization_id, role)
  where active;

-- ---------------------------------------------------------------------------
-- Documentation for future maintainers.
-- ---------------------------------------------------------------------------
comment on function public.is_org_member(uuid) is
  'True when the caller is an active member of the organization (or platform staff). Used by nearly every RLS policy.';
comment on function public.can_write(uuid) is
  'False for the read-only demo role (viewer). Every write policy ANDs this.';
comment on function public.reserve_storage_upload(uuid, bigint, text, text) is
  'Step 1 of the upload protocol: enforces the plan storage quota and returns a reservation id. Must be followed by finalize_storage_upload or cancel_storage_reservation.';
comment on table public.audit_logs is
  'Append-only. No UPDATE or DELETE policy exists by design.';
comment on table public.inventory_transactions is
  'Append-only stock ledger. Written only by transact_spare(); balance_after must always equal spares.stock at that point in time.';
