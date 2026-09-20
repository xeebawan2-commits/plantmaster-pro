-- PlantMaster QA Lab v1.2.4 — definitive service-role privilege repair
-- The server secret bypasses RLS, but PostgreSQL table/sequence privileges are
-- still required for tables created after the Supabase project's defaults.

-- Confirm the target role exists before granting.
do $$ begin
 if not exists(select 1 from pg_roles where rolname='service_role') then
  raise exception 'Supabase service_role does not exist in this project';
 end if;
end $$;

grant usage on schema public to service_role;
grant select,insert,update,delete on all tables in schema public to service_role;
grant usage,select,update on all sequences in schema public to service_role;
grant execute on all functions in schema public to service_role;

-- Ensure future PlantMaster tables/functions created by the SQL Editor retain
-- server-side access. This does not grant anything to anon or authenticated.
alter default privileges in schema public grant select,insert,update,delete on tables to service_role;
alter default privileges in schema public grant usage,select,update on sequences to service_role;
alter default privileges in schema public grant execute on functions to service_role;

-- Explicit QA grants remain here for verification/readability.
grant select,insert,update,delete on
 public.qa_environments,
 public.qa_test_runs,
 public.qa_test_results,
 public.qa_manual_checks
 to service_role;

grant usage,select,update on all sequences in schema public to service_role;

-- Ask PostgREST to refresh privileges/schema immediately.
notify pgrst,'reload schema';
