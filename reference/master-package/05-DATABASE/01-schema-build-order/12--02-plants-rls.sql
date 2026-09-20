-- ============================================================
--  PlantMaster Pro — allow owners/managers to create plants
--  Run ONCE in Supabase → SQL Editor → Run
--
--  WHY THIS IS NEEDED
--  The plants table currently has exactly one policy:
--      "plants read"  → for select → using (is_org_member(organization_id))
--  There is no INSERT or UPDATE policy, so with RLS enabled every
--  attempt to add or rename a plant is rejected. The new
--  "Plants & Sites" screen cannot work until this runs.
-- ============================================================

-- 1 ── create a plant (owner or manager only, and only in your own org)
drop policy if exists "plants insert" on public.plants;
create policy "plants insert" on public.plants
  for insert
  with check ( pm_is_org_leader(organization_id) );

-- 2 ── rename / relocate a plant (owner or manager only)
drop policy if exists "plants update" on public.plants;
create policy "plants update" on public.plants
  for update
  using      ( pm_is_org_leader(organization_id) )
  with check ( pm_is_org_leader(organization_id) );

-- 3 ── no DELETE policy on purpose.
--      Deleting a plant would orphan its assets, work orders, spares and
--      history. If a site genuinely closes, rename it (e.g. "Unit 2 — closed")
--      so the records stay readable.

-- ============================================================
--  VERIFY — should return the three policies below
-- ============================================================
select policyname, cmd
from pg_policies
where schemaname='public' and tablename='plants'
order by policyname;

--  expected:
--    plants insert | INSERT
--    plants read   | SELECT
--    plants update | UPDATE
