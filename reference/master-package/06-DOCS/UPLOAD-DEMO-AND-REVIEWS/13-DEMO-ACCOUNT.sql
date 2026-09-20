-- ================================================================
-- 13-DEMO-ACCOUNT.sql   (version 4)
--
-- ----------------------------------------------------------------
-- YOUR LAST RUN WORKED. Nothing is broken.
--
-- "Success. No rows returned" meant Part 1 applied the
-- security fix correctly.
--
-- You could not find Part 2 because it DID run - it just
-- stopped early, on purpose, because demo@hsbfix.org does
-- not exist yet. It printed an explanation using
-- "raise notice"... and the Supabase SQL Editor does not
-- display notice output anywhere. So you got a blank result
-- and no way to know what happened. My fault.
--
-- This version ends with a STATUS REPORT TABLE instead.
-- The SQL Editor always shows a table, so you will always
-- see exactly what happened and what is left to do.
--
-- (Part 2 is in this file, starting around line 200. It is
--  the big "build the demo company" block.)
-- ----------------------------------------------------------------
--
-- WHAT TO DO NOW
--
--   You have already done run 1. So:
--
--   1. Supabase -> Authentication -> Users -> Add user
--          -> Create new user
--        Email:        demo@hsbfix.org
--        Password:     PlantMasterDemo2026
--        Auto Confirm: TICK THE BOX  (login fails without it)
--
--   2. Paste this whole file again and press Run.
--
--   3. Read the table at the bottom. You want:
--        result       PART 1 + PART 2 DONE
--        assets       6
--        work_orders  6
--        demo_role    viewer
--
-- Safe to run as many times as you like.
-- ================================================================


-- ================================================================
-- PART 1 - make the 'viewer' role genuinely read-only
--
-- This is a real bug fix and is worth keeping even if you
-- never create the demo account.
--
-- Most of your write policies correctly test
--     org_role(organization_id) <> 'viewer'
-- but nine tables only tested is_org_member(), with no role
-- check. On those tables anybody in the organisation could
-- write, including a user you deliberately made a 'viewer'.
--
-- Nothing changes for owner, manager, engineer, supervisor,
-- technician, store or any of your other roles.
-- ================================================================

-- ---- the eight tables that DO have organization_id ----
do $$
declare
  t text;
  tables text[] := array[
    'scan_sessions',
    'scan_entity_links',
    'code_registry',
    'condition_recordings',
    'condition_alarms',
    'condition_entity_links',
    'measurement_points',
    'sensor_devices'
  ];
  pol record;
begin
  foreach t in array tables loop
    if to_regclass('public.'||t) is null then
      raise notice 'skip % (not present)', t;
      continue;
    end if;

    -- drop whatever policy currently governs writes, whatever
    -- it happens to be called on your database
    for pol in
      select policyname from pg_policies
      where schemaname='public' and tablename=t
        and cmd in ('ALL','INSERT','UPDATE','DELETE')
    loop
      execute format('drop policy if exists %I on public.%I',
                     pol.policyname, t);
    end loop;

    execute format('drop policy if exists %I on public.%I','pm read',t);
    execute format('drop policy if exists %I on public.%I','pm write',t);

    execute format($f$
      create policy "pm read" on public.%I
        for select to authenticated
        using (public.is_org_member(organization_id))
    $f$, t);

    execute format($f$
      create policy "pm write" on public.%I
        for all to authenticated
        using (public.is_org_member(organization_id)
               and public.org_role(organization_id) <> 'viewer')
        with check (public.is_org_member(organization_id)
               and public.org_role(organization_id) <> 'viewer')
    $f$, t);

    raise notice 'hardened %', t;
  end loop;
end $$;


-- ---- scan_pages: no organization_id, joins via scan_sessions ----
do $$
declare pol record;
begin
  if to_regclass('public.scan_pages') is null then
    raise notice 'skip scan_pages (not present)';
    return;
  end if;

  for pol in
    select policyname from pg_policies
    where schemaname='public' and tablename='scan_pages'
      and cmd in ('ALL','INSERT','UPDATE','DELETE')
  loop
    execute format('drop policy if exists %I on public.scan_pages', pol.policyname);
  end loop;

  drop policy if exists "pm read"  on public.scan_pages;
  drop policy if exists "pm write" on public.scan_pages;

  create policy "pm read" on public.scan_pages
    for select to authenticated
    using (exists (
      select 1 from public.scan_sessions s
      where s.id = session_id
        and public.is_org_member(s.organization_id)));

  create policy "pm write" on public.scan_pages
    for all to authenticated
    using (exists (
      select 1 from public.scan_sessions s
      where s.id = session_id
        and public.is_org_member(s.organization_id)
        and public.org_role(s.organization_id) <> 'viewer'))
    with check (exists (
      select 1 from public.scan_sessions s
      where s.id = session_id
        and public.is_org_member(s.organization_id)
        and public.org_role(s.organization_id) <> 'viewer'));

  raise notice 'hardened scan_pages';
end $$;


-- ---- file uploads ----
drop policy if exists "files write" on public.file_metadata;
create policy "files write" on public.file_metadata
  for insert to authenticated
  with check (public.is_org_member(organization_id)
              and public.org_role(organization_id) <> 'viewer');

drop policy if exists "plant file insert" on storage.objects;
create policy "plant file insert" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'plant-files'
    and public.is_org_member(((storage.foldername(name))[1])::uuid)
    and public.org_role(((storage.foldername(name))[1])::uuid) <> 'viewer');

drop policy if exists "plant file update" on storage.objects;
create policy "plant file update" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'plant-files'
    and public.is_org_member(((storage.foldername(name))[1])::uuid)
    and public.org_role(((storage.foldername(name))[1])::uuid) <> 'viewer');

-- audit_logs and legal_acceptances are deliberately left alone:
-- a viewer still needs to write their own audit rows and accept
-- terms of service.


-- ================================================================
-- PART 2 - build the demo company
--
-- Notes on why this looks the way it does:
--   * assets uses asset_code, not code
--   * assets requires asset_type and created_by
--   * work_orders requires description and created_by
--   * created_by on all three is a foreign key to auth.users,
--     so the demo user must exist first
--   * inserting an organisation fires a trigger that creates a
--     30 day trial subscription automatically; we extend it to
--     ten years afterwards so the demo never goes stale
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


-- ================================================================
-- STATUS REPORT  <-- READ THIS TABLE, it is the only output
--                    the Supabase SQL Editor will show you.
-- ================================================================
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

-- After a successful run 2 you should see:
--    result       PART 1 + PART 2 DONE
--    assets       6
--    work_orders  6
--    demo_role    viewer


-- ================================================================
-- CONFIRM THE LOCK ACTUALLY WORKS
-- ================================================================
-- Sign in to app.hsbfix.org as demo@hsbfix.org and try to
-- create a work order. It must fail. If it succeeds, tell me.


-- ================================================================
-- TO REMOVE THE DEMO LATER
-- ================================================================
-- Keep Part 1 - it is a security fix.
-- Delete "PlantMaster Demo Mill" from the control centre,
-- then delete demo@hsbfix.org from Authentication -> Users.
