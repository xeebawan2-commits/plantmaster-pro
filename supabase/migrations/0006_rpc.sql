-- ===========================================================================
-- PlantMaster Pro — 0006 RPC surface
--
-- Every function the client calls via supabase.rpc(). Signatures match the
-- exact argument names used in app.js / operations.js / procurement.js —
-- PostgREST resolves overloads by argument name, so these must not drift.
--
-- All are SECURITY DEFINER with a pinned search_path and re-check
-- authorization internally: RLS does not apply inside a definer function,
-- so the check must be explicit.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- create_organization — onboarding. Creates org + first plant + owner
-- membership atomically so a half-built workspace can never exist.
-- ---------------------------------------------------------------------------
create or replace function public.create_organization(
  org_name   text,
  plant_name text default 'Main Plant'
) returns public.organizations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := auth.uid();
  o   public.organizations;
  p   public.plants;
begin
  if uid is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;
  if coalesce(trim(org_name), '') = '' then
    raise exception 'Company name is required' using errcode = '22023';
  end if;

  -- One workspace per person keeps the "which org am I in" problem away.
  if exists (select 1 from public.organization_members m
             where m.user_id = uid and m.active) then
    raise exception 'You already belong to a workspace' using errcode = '23505';
  end if;

  insert into public.organizations (name, owner_id, commercial_status, plan_code)
  values (trim(org_name), uid, 'trial', 'trial')
  returning * into o;

  insert into public.plants (organization_id, name)
  values (o.id, coalesce(nullif(trim(plant_name), ''), 'Main Plant'))
  returning * into p;

  insert into public.organization_members
    (organization_id, user_id, plant_id, role, active, accepted_at)
  values (o.id, uid, p.id, 'owner', true, now());

  insert into public.organization_settings (organization_id, plant_id, app_name)
  values (o.id, p.id, trim(org_name))
  on conflict (organization_id) do nothing;

  insert into public.data_retention_policies (organization_id)
  values (o.id) on conflict (organization_id) do nothing;

  insert into public.audit_logs
    (organization_id, plant_id, user_id, action, entity_type, entity_id, details)
  values (o.id, p.id, uid, 'organization_created', 'organization', o.id::text,
          jsonb_build_object('name', o.name));

  return o;
end $$;

-- ---------------------------------------------------------------------------
-- accept_invitation — joins the caller to an org using a token.
-- ---------------------------------------------------------------------------
create or replace function public.accept_invitation(invite_token text)
returns public.organization_members
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := auth.uid();
  inv public.invitations;
  mem public.organization_members;
  mail text;
begin
  if uid is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;

  select * into inv from public.invitations
   where token = invite_token for update;

  if not found then
    raise exception 'This invitation link is not valid' using errcode = 'P0002';
  end if;
  if inv.accepted_at is not null then
    raise exception 'This invitation has already been used' using errcode = '23505';
  end if;
  if inv.expires_at < now() then
    raise exception 'This invitation has expired' using errcode = '22023';
  end if;

  -- The invitation is addressed to an email; only that person may use it.
  select email into mail from auth.users where id = uid;
  if mail is not null and lower(mail) <> lower(inv.email) then
    raise exception 'This invitation was sent to %', inv.email using errcode = '42501';
  end if;

  insert into public.organization_members
    (organization_id, user_id, plant_id, role, permissions, active, accepted_at)
  values (inv.organization_id, uid, inv.plant_id, inv.role,
          coalesce(inv.permissions, '{}'::jsonb), true, now())
  on conflict (organization_id, user_id) do update
    set active = true, role = excluded.role, deactivated_at = null, updated_at = now()
  returning * into mem;

  update public.invitations
     set accepted_at = now(), accepted_by = uid
   where id = inv.id;

  -- Carry the worker details captured at invite time onto the profile.
  if inv.worker_details <> '{}'::jsonb then
    update public.profiles
       set full_name   = coalesce(nullif(inv.worker_details->>'full_name',''), full_name),
           employee_id = coalesce(inv.worker_details->>'employee_id', employee_id),
           designation = coalesce(inv.worker_details->>'designation', designation),
           contact     = coalesce(inv.worker_details->>'contact', contact),
           default_shift = coalesce(inv.worker_details->>'default_shift', default_shift),
           updated_at  = now()
     where id = uid;
  end if;

  insert into public.audit_logs
    (organization_id, plant_id, user_id, action, entity_type, entity_id, details)
  values (inv.organization_id, inv.plant_id, uid, 'invitation_accepted', 'member',
          uid::text, jsonb_build_object('role', inv.role));

  return mem;
end $$;

-- ---------------------------------------------------------------------------
-- transfer_organization_ownership
-- ---------------------------------------------------------------------------
create or replace function public.transfer_organization_ownership(
  p_organization_id uuid,
  p_new_owner       uuid
) returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare uid uuid := auth.uid();
begin
  if not public.is_org_owner(p_organization_id) then
    raise exception 'Only the current owner can transfer ownership' using errcode = '42501';
  end if;
  if not exists (select 1 from public.organization_members
                 where organization_id = p_organization_id
                   and user_id = p_new_owner and active) then
    raise exception 'The new owner must be an active member' using errcode = '22023';
  end if;

  update public.organization_members
     set role = 'owner', updated_at = now()
   where organization_id = p_organization_id and user_id = p_new_owner;

  update public.organization_members
     set role = 'manager', updated_at = now()
   where organization_id = p_organization_id and user_id = uid;

  update public.organizations
     set owner_id = p_new_owner, updated_at = now()
   where id = p_organization_id;

  insert into public.audit_logs
    (organization_id, user_id, action, entity_type, entity_id, details)
  values (p_organization_id, uid, 'ownership_transferred', 'organization',
          p_organization_id::text, jsonb_build_object('new_owner', p_new_owner));

  return true;
end $$;

-- ===========================================================================
-- STORAGE QUOTA PROTOCOL
-- ===========================================================================

-- Committed + still-pending bytes for a tenant.
create or replace function public.organization_storage_bytes(p_org uuid)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce((
    select sum(f.size_bytes) from public.file_metadata f
     where f.organization_id = p_org and f.removed_at is null), 0)
   + coalesce((
    select sum(r.bytes) from public.storage_reservations r
     where r.organization_id = p_org and r.status = 'pending' and r.expires_at > now()), 0);
$$;

create or replace function public.organization_plan(p_org uuid)
returns public.subscription_plans
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.* from public.subscription_plans p
   join public.organizations o on o.plan_code = p.code
  where o.id = p_org;
$$;

-- reserve_storage_upload — quota gate. Returns the reservation id.
create or replace function public.reserve_storage_upload(
  p_organization_id uuid,
  p_bytes           bigint,
  p_file_name       text default null,
  p_mime_type       text default null
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  plan  public.subscription_plans;
  used  bigint;
  limit_bytes bigint;
  rid   uuid;
  org   public.organizations;
begin
  if not public.is_org_member(p_organization_id) then
    raise exception 'Not a member of this workspace' using errcode = '42501';
  end if;
  if not public.can_write(p_organization_id) then
    raise exception 'Read-only demo — uploads are disabled' using errcode = '42501';
  end if;
  if p_bytes is null or p_bytes <= 0 then
    raise exception 'Invalid file size' using errcode = '22023';
  end if;

  select * into org from public.organizations where id = p_organization_id;
  if org.commercial_status in ('suspended','cancelled') then
    raise exception 'This workspace is % — uploads are disabled', org.commercial_status
      using errcode = '42501';
  end if;

  -- Release anything abandoned before measuring.
  update public.storage_reservations
     set status = 'expired', settled_at = now()
   where organization_id = p_organization_id
     and status = 'pending' and expires_at <= now();

  select * into plan from public.organization_plan(p_organization_id);
  limit_bytes := (coalesce(plan.storage_gb, 1) * 1024 * 1024 * 1024)::bigint;
  used := public.organization_storage_bytes(p_organization_id);

  if used + p_bytes > limit_bytes then
    raise exception 'Storage limit reached (% GB). Free space or upgrade the plan.',
      coalesce(plan.storage_gb, 1) using errcode = '53100';
  end if;

  insert into public.storage_reservations
    (organization_id, bytes, file_name, mime_type, created_by)
  values (p_organization_id, p_bytes, p_file_name, p_mime_type, auth.uid())
  returning id into rid;

  return rid;
end $$;

create or replace function public.finalize_storage_upload(
  p_reservation_id   uuid,
  p_object_path      text,
  p_file_metadata_id uuid default null
) returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare r public.storage_reservations;
begin
  select * into r from public.storage_reservations
   where id = p_reservation_id for update;
  if not found then
    raise exception 'Unknown storage reservation' using errcode = 'P0002';
  end if;
  if not public.is_org_member(r.organization_id) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  if r.status <> 'pending' then
    return true;   -- already settled; make this idempotent
  end if;

  update public.storage_reservations
     set status = 'committed', settled_at = now(),
         object_path = p_object_path, file_metadata_id = p_file_metadata_id
   where id = p_reservation_id;

  insert into public.storage_usage_events
    (organization_id, event_type, bytes, object_path, user_id)
  values (r.organization_id, 'upload', r.bytes, p_object_path, auth.uid());

  return true;
end $$;

create or replace function public.cancel_storage_reservation(p_reservation_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare r public.storage_reservations;
begin
  select * into r from public.storage_reservations
   where id = p_reservation_id for update;
  if not found then return true; end if;
  if not public.is_org_member(r.organization_id) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  update public.storage_reservations
     set status = 'cancelled', settled_at = now()
   where id = p_reservation_id and status = 'pending';
  return true;
end $$;

create or replace function public.record_storage_download(
  p_organization_id uuid,
  p_object_path     text,
  p_bytes           bigint default 0
) returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_org_member(p_organization_id) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  insert into public.storage_usage_events
    (organization_id, event_type, bytes, object_path, user_id)
  values (p_organization_id, 'download', greatest(coalesce(p_bytes, 0), 0),
          p_object_path, auth.uid());
  return true;
end $$;

-- ===========================================================================
-- PLAN / FEATURE INTROSPECTION
-- ===========================================================================
create or replace function public.organization_effective_features(p_organization_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case when public.is_org_member(p_organization_id)
    then coalesce((select p.features from public.organization_plan(p_organization_id) p), '{}'::jsonb)
         || coalesce((select f.overrides from public.organization_features f
                       where f.organization_id = p_organization_id), '{}'::jsonb)
    else '{}'::jsonb end;
$$;

create or replace function public.organization_plan_summary(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  plan public.subscription_plans;
  org  public.organizations;
  used_bytes bigint;
  users_n int;
  plants_n int;
  assets_n int;
  ai_n int;
begin
  if not public.is_org_member(p_organization_id) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  select * into org  from public.organizations where id = p_organization_id;
  select * into plan from public.organization_plan(p_organization_id);
  used_bytes := public.organization_storage_bytes(p_organization_id);

  select count(*) into users_n from public.organization_members
   where organization_id = p_organization_id and active;
  select count(*) into plants_n from public.plants
   where organization_id = p_organization_id and removed_at is null;
  select count(*) into assets_n from public.assets
   where organization_id = p_organization_id and removed_at is null;
  select count(*) into ai_n from public.ai_usage_events
   where organization_id = p_organization_id
     and created_at >= date_trunc('month', now());

  return jsonb_build_object(
    'organization_id',   p_organization_id,
    'organization_name', org.name,
    'plan_code',         org.plan_code,
    'plan_name',         coalesce(plan.name, org.plan_code),
    'price_monthly',     coalesce(plan.price_monthly, 0),
    'currency',          coalesce(plan.currency, 'PKR'),
    'commercial_status', org.commercial_status,
    'status_reason',     org.status_reason,
    'trial_ends_at',     org.trial_ends_at,
    'storage_used_bytes',  used_bytes,
    'storage_limit_bytes', (coalesce(plan.storage_gb, 1) * 1024 * 1024 * 1024)::bigint,
    'storage_gb',        coalesce(plan.storage_gb, 1),
    'users',             users_n,
    'max_users',         plan.max_users,
    'plants',            plants_n,
    'max_plants',        plan.max_plants,
    'assets',            assets_n,
    'max_assets',        plan.max_assets,
    'ai_requests_month', ai_n,
    'ai_limit_month',    coalesce(plan.ai_requests_month, 0),
    'features',          public.organization_effective_features(p_organization_id)
  );
end $$;

-- ===========================================================================
-- LEGAL CONSENT
-- ===========================================================================
create or replace function public.pending_legal_documents(p_organization_id uuid default null)
returns setof public.legal_documents
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select d.* from public.legal_documents d
   where d.active and d.mandatory
     and not exists (
       select 1 from public.legal_acceptances a
        where a.document_id = d.id
          and a.user_id = auth.uid()
          and (a.organization_id is not distinct from p_organization_id))
   order by d.effective_at desc;
$$;

create or replace function public.accept_legal_document(
  p_document_id     uuid,
  p_organization_id uuid default null,
  p_locale          text default null,
  p_user_agent_hash text default null
) returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;
  insert into public.legal_acceptances
    (document_id, organization_id, user_id, locale, user_agent_hash)
  values (p_document_id, p_organization_id, auth.uid(), p_locale, p_user_agent_hash)
  on conflict (document_id, user_id, organization_id) do nothing;
  return true;
end $$;

-- ===========================================================================
-- PLATFORM COMPLAINTS
-- ===========================================================================
create or replace function public.submit_app_complaint(
  p_organization_id uuid,
  p_category        text,
  p_priority        text,
  p_subject         text,
  p_description     text,
  p_app_version     text default null,
  p_device_info     jsonb default '{}'::jsonb
) returns public.app_complaints
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare t public.app_complaints;
begin
  if not public.is_org_owner(p_organization_id) then
    raise exception 'Only the workspace owner can raise a platform complaint'
      using errcode = '42501';
  end if;
  insert into public.app_complaints
    (organization_id, category, priority, subject, description,
     app_version, device_info, created_by)
  values (p_organization_id, coalesce(p_category,'application'),
          coalesce(p_priority,'medium'), p_subject, p_description,
          p_app_version, coalesce(p_device_info,'{}'::jsonb), auth.uid())
  returning * into t;
  return t;
end $$;

create or replace function public.owner_app_complaints(p_organization_id uuid)
returns setof public.app_complaints
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select c.* from public.app_complaints c
   where c.organization_id = p_organization_id
     and (public.is_org_owner(p_organization_id) or public.is_platform_admin())
   order by c.updated_at desc;
$$;

create or replace function public.owner_app_complaint_messages(p_ticket_id uuid)
returns setof public.app_complaint_messages
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select m.* from public.app_complaint_messages m
   join public.app_complaints c on c.id = m.ticket_id
  where m.ticket_id = p_ticket_id
    and (public.is_org_owner(c.organization_id) or public.is_platform_admin())
  order by m.created_at;
$$;

create or replace function public.reply_app_complaint(
  p_ticket_id uuid,
  p_message   text
) returns public.app_complaint_messages
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c public.app_complaints;
  m public.app_complaint_messages;
  staff boolean := public.is_platform_admin();
begin
  select * into c from public.app_complaints where id = p_ticket_id;
  if not found then
    raise exception 'Ticket not found' using errcode = 'P0002';
  end if;
  if not (staff or public.is_org_owner(c.organization_id)) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  insert into public.app_complaint_messages (ticket_id, user_id, message, is_staff)
  values (p_ticket_id, auth.uid(), p_message, staff)
  returning * into m;

  update public.app_complaints
     set updated_at = now(),
         status = case when staff and status = 'open' then 'in_progress' else status end
   where id = p_ticket_id;

  return m;
end $$;

-- ===========================================================================
-- PLATFORM ADMINISTRATION (admin.hsbfix.org)
-- ===========================================================================
create or replace function public.platform_tenant_overview()
returns table (
  organization_id   uuid,
  organization_name text,
  created_at        timestamptz,
  commercial_status text,
  status_reason     text,
  plan_code         text,
  plan_name         text,
  workers           bigint,
  plants            bigint,
  files             bigint,
  storage_bytes     bigint,
  ai_requests_month bigint,
  open_incidents    bigint
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    o.id,
    o.name,
    o.created_at,
    o.commercial_status::text,
    o.status_reason,
    o.plan_code,
    coalesce(p.name, o.plan_code),
    (select count(*) from public.organization_members m
      where m.organization_id = o.id and m.active),
    (select count(*) from public.plants pl
      where pl.organization_id = o.id and pl.removed_at is null),
    (select count(*) from public.file_metadata f
      where f.organization_id = o.id and f.removed_at is null),
    public.organization_storage_bytes(o.id),
    (select count(*) from public.ai_usage_events a
      where a.organization_id = o.id and a.created_at >= date_trunc('month', now())),
    (select count(*) from public.system_incidents i
      where i.organization_id = o.id and i.status <> 'resolved')
  from public.organizations o
  left join public.subscription_plans p on p.code = o.plan_code
  where public.is_platform_admin()
  order by o.created_at desc;
$$;

create or replace function public.platform_set_company(
  p_organization_id uuid,
  p_status          text,
  p_plan_code       text default null,
  p_reason          text default null
) returns public.organizations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare o public.organizations;
begin
  if not public.is_platform_admin() then
    raise exception 'Platform administrator required' using errcode = '42501';
  end if;
  if p_plan_code is not null
     and not exists (select 1 from public.subscription_plans where code = p_plan_code) then
    raise exception 'Unknown plan %', p_plan_code using errcode = '22023';
  end if;

  update public.organizations
     set commercial_status = p_status::public.commercial_status,
         plan_code         = coalesce(p_plan_code, plan_code),
         status_reason     = p_reason,
         updated_at        = now()
   where id = p_organization_id
  returning * into o;

  insert into public.audit_logs
    (organization_id, user_id, action, entity_type, entity_id, details)
  values (p_organization_id, auth.uid(), 'platform_status_changed', 'organization',
          p_organization_id::text,
          jsonb_build_object('status', p_status, 'plan', p_plan_code, 'reason', p_reason));

  return o;
end $$;

-- ---------------------------------------------------------------------------
-- Execute grants. Revoke from anon so unauthenticated callers cannot probe.
-- ---------------------------------------------------------------------------
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure::text as sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
  loop
    execute format('revoke all on function %s from public, anon', r.sig);
    execute format('grant execute on function %s to authenticated', r.sig);
  end loop;
end $$;
