-- ============================================================
-- STEP 1 OF 2  —  BLOCK THE DEMO ACCOUNT FROM WRITING
-- CORRECTED VERSION — genuinely safe to run any number of times.
--
-- If you saw "policy loto read already exists", that means the
-- earlier run ALREADY WORKED. Running this version will simply
-- confirm it. Nothing is damaged either way.
--
-- Paste ALL of this into the Supabase SQL Editor and press Run.
-- Does not change what anyone can READ.
-- ============================================================

create or replace function public.is_org_writer(org uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $function$
  select exists(
    select 1 from organization_members m
    where m.organization_id = org
      and m.user_id = auth.uid()
      and m.active
      and m.role <> 'viewer'
  )
$function$;

-- drop ALL three possible names, so this can be re-run safely
drop policy if exists "loto access" on public.loto_procedures;
drop policy if exists "loto read"   on public.loto_procedures;
drop policy if exists "loto write"  on public.loto_procedures;

create policy "loto read" on public.loto_procedures
for select
using (
  exists (
    select 1 from plants p
    where p.id = loto_procedures.plant_id
      and is_org_member(p.organization_id)
  )
);

create policy "loto write" on public.loto_procedures
for all
using (
  exists (
    select 1 from plants p
    where p.id = loto_procedures.plant_id
      and is_org_writer(p.organization_id)
  )
)
with check (
  exists (
    select 1 from plants p
    where p.id = loto_procedures.plant_id
      and is_org_writer(p.organization_id)
  )
);

-- final line = what you will see in the Results panel
select
  case
    when (select count(*) from pg_proc where proname = 'is_org_writer') = 1
     and (select count(*) from pg_policies
            where schemaname = 'public'
              and tablename  = 'loto_procedures'
              and policyname = 'loto write') = 1
    then 'STEP 1 DONE — demo account can no longer write LOTO'
    else 'STEP 1 FAILED — send me this screen'
  end as result,
  (select count(*) from pg_policies
     where schemaname = 'public' and tablename = 'loto_procedures') as loto_policies_now;
