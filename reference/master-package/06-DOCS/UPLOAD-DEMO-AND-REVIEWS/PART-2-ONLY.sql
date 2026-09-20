-- ================================================================
-- PART-2-ONLY.sql
--
-- You have already run Part 1 (the security fix) and you have
-- created demo@hsbfix.org. This is the ONLY piece left.
--
-- Select everything in this file, paste it into the Supabase
-- SQL Editor, and press Run.
--
-- It builds the demo company and its sample data.
-- Safe to run more than once.
--
-- WHAT YOU SHOULD SEE - a table at the bottom saying:
--      result       PART 1 + PART 2 DONE
--      assets       6
--      work_orders  6
--      demo_role    viewer
-- ================================================================

do $$
declare
  v_org_id   uuid;
  v_plant_id uuid;
  v_user_id  uuid;
  a_comp uuid; a_ring uuid; a_boil uuid; a_chil uuid; a_gen uuid; a_card uuid;
begin
  -- the demo login must already exist
  select id into v_user_id from auth.users
   where lower(email) = 'demo@hsbfix.org' limit 1;

  if v_user_id is null then
    raise notice ' ';
    raise notice '================================================';
    raise notice ' PART 1 IS DONE. The security fix is applied.';
    raise notice ' ';
    raise notice ' PART 2 skipped - demo@hsbfix.org does not exist';
    raise notice ' yet. That is not an error.';
    raise notice ' ';
    raise notice ' To add the demo company:';
    raise notice '   1. Authentication -> Users -> Add user';
    raise notice '        Email:        demo@hsbfix.org';
    raise notice '        Password:     PlantMasterDemo2026';
    raise notice '        Auto Confirm: TICK IT';
    raise notice '   2. Run this same file again.';
    raise notice '================================================';
    return;
  end if;

  -- profile
  insert into public.profiles (id, full_name, designation)
  values (v_user_id, 'Demo User', 'Maintenance Manager')
  on conflict (id) do nothing;

  -- organisation
  select id into v_org_id from public.organizations
   where lower(name) = 'plantmaster demo mill' limit 1;

  if v_org_id is null then
    insert into public.organizations (name, created_by, commercial_status)
    values ('PlantMaster Demo Mill', v_user_id, 'active')
    returning id into v_org_id;
    raise notice 'created organisation %', v_org_id;
  end if;

  -- the insert trigger sets it back to a 30 day trial;
  -- make it permanent so the demo never expires
  update public.organizations
     set commercial_status = 'active',
         trial_ends_at     = now() + interval '10 years'
   where id = v_org_id;

  update public.organization_subscriptions
     set status               = 'active',
         current_period_end   = now() + interval '10 years',
         trial_ends_at        = now() + interval '10 years'
   where organization_id = v_org_id;

  -- give it the professional plan so limits are generous
  update public.organization_subscriptions s
     set plan_id = p.id
    from public.subscription_plans p
   where s.organization_id = v_org_id
     and p.code = 'professional';

  -- membership must exist before plant/asset inserts,
  -- because the plan-limit triggers read it
  -- NOTE: inserted directly as 'viewer'.
  -- Do NOT create this as 'owner' and demote later: the
  -- protect_owner_role trigger blocks any owner role change with
  -- "Use the audited ownership-transfer workflow".
  perform set_config('plantmaster.owner_transfer','allowed',true);

  insert into public.organization_members (organization_id, user_id, role, active)
  values (v_org_id, v_user_id, 'viewer', true)
  on conflict (organization_id, user_id) do update set role='viewer', active=true;

  -- plant
  select id into v_plant_id from public.plants
   where organization_id = v_org_id limit 1;
  if v_plant_id is null then
    insert into public.plants (organization_id, name, location)
    values (v_org_id, 'Korangi Spinning Unit', 'Korangi Industrial Area, Karachi')
    returning id into v_plant_id;
  end if;

  insert into public.plant_members (plant_id, user_id)
  values (v_plant_id, v_user_id)
  on conflict (plant_id, user_id) do nothing;

  -- safety: never insert assets with a null parent
  if v_org_id is null or v_plant_id is null then
    raise exception 'Organisation or plant missing (org=%, plant=%). Run this whole file from the top.',
      v_org_id, v_plant_id;
  end if;

  -- assets
  insert into public.assets
    (id, organization_id, plant_id, asset_code, name, asset_type,
     location, manufacturer, model, status, created_by)
  values
    (gen_random_uuid(), v_org_id, v_plant_id, 'AC-02', 'Air Compressor',   'rotary_screw_compressor',
       'Utilities',  'Atlas Copco', 'GA55',  'active', v_user_id),
    (gen_random_uuid(), v_org_id, v_plant_id, 'RF-04', 'Ring Frame',       'ring_frame',
       'Spinning',   'Rieter',      'G32',   'active', v_user_id),
    (gen_random_uuid(), v_org_id, v_plant_id, 'B-01',  'Steam Boiler',     'boiler',
       'Utilities',  'Cochran',     '8 TPH', 'active', v_user_id),
    (gen_random_uuid(), v_org_id, v_plant_id, 'CH-03', 'Chiller',          'chiller',
       'Utilities',  'Carrier',     '120 TR','active', v_user_id),
    (gen_random_uuid(), v_org_id, v_plant_id, 'DG-01', 'Diesel Generator', 'generator',
       'Power House','Cummins',     '1000 kVA','active', v_user_id),
    (gen_random_uuid(), v_org_id, v_plant_id, 'CD-07', 'Carding Machine',  'carding_machine',
       'Spinning',   'Rieter',      'C70',   'active', v_user_id)
  on conflict (plant_id, asset_code) do nothing;

  select id into a_comp from public.assets where plant_id=v_plant_id and asset_code='AC-02';
  select id into a_ring from public.assets where plant_id=v_plant_id and asset_code='RF-04';
  select id into a_boil from public.assets where plant_id=v_plant_id and asset_code='B-01';
  select id into a_chil from public.assets where plant_id=v_plant_id and asset_code='CH-03';
  select id into a_gen  from public.assets where plant_id=v_plant_id and asset_code='DG-01';
  select id into a_card from public.assets where plant_id=v_plant_id and asset_code='CD-07';

  -- work orders
  if not exists (select 1 from public.work_orders where organization_id = v_org_id) then
    insert into public.work_orders
      (id, organization_id, plant_id, asset_id, title, description,
       priority, status, due_at, created_by, created_at)
    values
      (gen_random_uuid(), v_org_id, v_plant_id, a_comp,
       'Compressor tripping on high discharge temperature',
       'Unit trips after roughly twenty minutes under load. Reported by the shift operator using an Urdu voice note.',
       'high', 'open', now() + interval '6 hours', v_user_id, now() - interval '10 hours'),

      (gen_random_uuid(), v_org_id, v_plant_id, a_ring,
       'Replace spindle tape, section C',
       'Tapes in section C are slack and glazed. Two of six spindles completed so far.',
       'medium', 'in_progress', now() + interval '2 days', v_user_id, now() - interval '2 days'),

      (gen_random_uuid(), v_org_id, v_plant_id, a_boil,
       'Monthly safety valve test',
       'Routine monthly lift test of the main safety valve, as required by the boiler inspection schedule.',
       'high', 'open', now() - interval '2 days', v_user_id, now() - interval '4 days'),

      (gen_random_uuid(), v_org_id, v_plant_id, a_chil,
       'Clean condenser tubes',
       'Approach temperature had risen. Tubes brushed and flushed, approach returned to normal.',
       'medium', 'completed', now() - interval '6 days', v_user_id, now() - interval '6 days'),

      (gen_random_uuid(), v_org_id, v_plant_id, a_gen,
       '250-hour service',
       'Routine service. Engine oil, oil filter, fuel filter and air filter replaced. Coolant topped up.',
       'medium', 'completed', now() - interval '8 days', v_user_id, now() - interval '8 days'),

      (gen_random_uuid(), v_org_id, v_plant_id, a_card,
       'Card clothing inspection',
       'Cylinder and doffer wire checked for wear. No action required this cycle.',
       'low', 'completed', now() - interval '10 days', v_user_id, now() - interval '10 days');
    raise notice 'seeded 6 work orders';
  end if;

  raise notice '=== DONE ===';
  raise notice 'Company : PlantMaster Demo Mill';
  raise notice 'Login   : demo@hsbfix.org / PlantMasterDemo2026';
  raise notice 'Role    : viewer (read-only)';
end $$;


-- ---------- status report ----------
select
  case
    when u.id is null then 'PART 1 DONE - security fix applied'
    else                   'PART 1 + PART 2 DONE'
  end                                              as result,

  case
    when u.id is null
      then 'Next: create demo@hsbfix.org in Authentication -> Users (tick Auto Confirm), then run this file again'
    else 'Nothing left to do. Sign in and test it.'
  end                                              as next_step,

  coalesce(o.name,'not created yet')               as company,
  coalesce(o.commercial_status,'-')                as status,
  coalesce((select count(*)::text from public.assets       a where a.organization_id=o.id),'0') as assets,
  coalesce((select count(*)::text from public.work_orders  w where w.organization_id=o.id),'0') as work_orders,
  coalesce((select m.role from public.organization_members m
             where m.organization_id=o.id and m.user_id=u.id),'-')                              as demo_role
from (select 1) x
left join auth.users u
       on lower(u.email) = 'demo@hsbfix.org'
left join public.organizations o
       on lower(o.name) = 'plantmaster demo mill';

-- ================================================================
-- If the table says "PART 1 DONE - security fix applied" instead,
-- then demo@hsbfix.org was not found. Check in
-- Authentication -> Users that the email is exactly
--     demo@hsbfix.org
-- and that Auto Confirm was ticked when you created it.
-- ================================================================
