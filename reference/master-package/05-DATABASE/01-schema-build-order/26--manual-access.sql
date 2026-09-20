-- PlantMaster Pro — manual-access.sql
-- Per-worker "can view manuals" permission (runs in Supabase SQL editor).
--
-- How it works:
--  * Owner & manager ALWAYS see manuals (they manage them).
--  * Every other worker sees manuals by DEFAULT (nothing breaks on deploy).
--  * Owner hides manuals from a specific worker via:
--      People → Members → Edit & Permissions → untick "Can view Manuals & Drawings"
--    That stores permissions['manuals.view'] = false for that worker.
--  * The gate also covers the AI index (document_chunks reads through manuals),
--    so a blocked worker cannot even search manual pages.

drop policy if exists manuals_member on public.manuals;

create policy manuals_member on public.manuals
for all to authenticated
using (exists (
  select 1 from public.organization_members om
  where om.organization_id = manuals.organization_id
    and om.user_id = auth.uid()
    and om.active
    and (om.role in ('owner','manager')
         or coalesce((om.permissions->>'manuals.view')::boolean, true))
))
with check (exists (
  select 1 from public.organization_members om
  where om.organization_id = manuals.organization_id
    and om.user_id = auth.uid()
    and om.active
    and (om.role in ('owner','manager')
         or coalesce((om.permissions->>'manuals.view')::boolean, true))
));
