-- PlantMaster Pro v4.13 — expanded role list (run ONCE in Supabase SQL editor, BEFORE uploading the new app files)
-- Existing members keep their current roles. New roles get normal member access + owner-granted actions.
alter table public.organization_members drop constraint if exists organization_members_role_check;
alter table public.organization_members add constraint organization_members_role_check check (role in (
  'owner','manager','deputy_manager','assistant_manager','supervisor',
  'engineer','mechanical_engineer','electrical_engineer','production_engineer','utility_engineer','power_house_engineer',
  'technical_officer','senior_technical_officer','technician','senior_technician',
  'operator','assistant_operator','senior_operator','worker','checker',
  'quality_control_officer','store','admin_officer','time_officer','viewer'
));
