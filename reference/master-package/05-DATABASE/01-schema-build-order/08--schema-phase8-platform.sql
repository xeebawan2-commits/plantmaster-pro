-- PlantMaster Pro v4.7 Platform Administration & Tenant Security
-- Additive/idempotent. Requires schema-phase7-commercial.sql.

alter table public.legal_documents add column if not exists required boolean not null default false;
alter table public.legal_documents add column if not exists acceptance_scope text not null default 'all_users';
alter table public.legal_documents add column if not exists published_by uuid references auth.users(id);
alter table public.legal_documents add column if not exists published_at timestamptz;
do $$ begin
  if not exists(select 1 from pg_constraint where conname='legal_acceptance_scope_check') then
    alter table public.legal_documents add constraint legal_acceptance_scope_check check(acceptance_scope in ('all_users','owners','platform_admins'));
  end if;
end $$;

-- Prevent ordinary invitations from creating another owner.
create or replace function public.protect_owner_role()
returns trigger language plpgsql security definer set search_path=public as $$
declare old_owner boolean:=false;new_owner boolean:=false;transfer_flag text;
begin
  transfer_flag:=coalesce(current_setting('plantmaster.owner_transfer',true),'');
  if tg_table_name='invitations' then
    if new.role='owner' then raise exception 'Owner cannot be granted by invitation';end if;
    return new;
  end if;
  old_owner:=old.role='owner';new_owner:=new.role='owner';
  if old_owner<>new_owner and transfer_flag<>'allowed' and not public.is_platform_admin() then
    raise exception 'Use the audited ownership-transfer workflow';
  end if;
  if old_owner and old.active and not new.active and transfer_flag<>'allowed' and not public.is_platform_admin() then
    raise exception 'Transfer ownership before deactivating the owner';
  end if;
  return new;
end $$;

do $$ begin
  if not exists(select 1 from pg_trigger where tgname='protect_invitation_owner_role' and not tgisinternal) then
    create trigger protect_invitation_owner_role before insert or update on public.invitations for each row execute function public.protect_owner_role();
  end if;
  if not exists(select 1 from pg_trigger where tgname='protect_member_owner_role' and not tgisinternal) then
    create trigger protect_member_owner_role before update on public.organization_members for each row execute function public.protect_owner_role();
  end if;
end $$;

-- Enforce worker and pending-invitation limits from the active plan.
create or replace function public.enforce_worker_plan_limit()
returns trigger language plpgsql security definer set search_path=public as $$
declare oid uuid;limit_value integer;active_workers bigint;pending_invites bigint;
begin
  oid:=new.organization_id;
  if tg_table_name='invitations' and new.role='owner' then raise exception 'Owner cannot be granted by invitation';end if;
  select p.max_workers into limit_value from public.organization_subscriptions s join public.subscription_plans p on p.id=s.plan_id where s.organization_id=oid and s.status in ('active','trial');
  if limit_value is null then raise exception 'Active subscription required';end if;
  select count(*) into active_workers from public.organization_members where organization_id=oid and active and (tg_table_name<>'organization_members' or user_id<>new.user_id);
  select count(*) into pending_invites from public.invitations where organization_id=oid and accepted_at is null and expires_at>now() and (tg_table_name<>'invitations' or id<>new.id);
  if tg_table_name='organization_members' and coalesce(new.active,false) then active_workers:=active_workers+1;end if;
  if tg_table_name='invitations' and new.accepted_at is null and new.expires_at>now() then pending_invites:=pending_invites+1;end if;
  if active_workers+pending_invites>limit_value then raise exception 'Worker plan limit of % reached',limit_value;end if;
  return new;
end $$;

do $$ begin
  if not exists(select 1 from pg_trigger where tgname='member_plan_limit' and not tgisinternal) then
    create trigger member_plan_limit before insert or update of active on public.organization_members for each row execute function public.enforce_worker_plan_limit();
  end if;
  if not exists(select 1 from pg_trigger where tgname='invitation_plan_limit' and not tgisinternal) then
    create trigger invitation_plan_limit before insert or update of accepted_at,expires_at on public.invitations for each row execute function public.enforce_worker_plan_limit();
  end if;
end $$;

create or replace function public.enforce_plant_plan_limit()
returns trigger language plpgsql security definer set search_path=public as $$
declare limit_value integer;used bigint;
begin
  select p.max_plants into limit_value from public.organization_subscriptions s join public.subscription_plans p on p.id=s.plan_id where s.organization_id=new.organization_id and s.status in ('active','trial');
  if limit_value is null then raise exception 'Active subscription required';end if;
  select count(*) into used from public.plants where organization_id=new.organization_id and id<>new.id;
  if used+1>limit_value then raise exception 'Plant plan limit of % reached',limit_value;end if;
  return new;
end $$;
do $$ begin
  if not exists(select 1 from pg_trigger where tgname='plant_plan_limit' and not tgisinternal) then
    create trigger plant_plan_limit before insert or update of organization_id on public.plants for each row execute function public.enforce_plant_plan_limit();
  end if;
end $$;

-- Audited transfer. One primary owner remains after transfer; the former owner
-- becomes manager. Platform admin may also perform recovery transfers.
create or replace function public.transfer_organization_ownership(p_organization_id uuid,p_new_owner uuid)
returns void language plpgsql security definer set search_path=public as $$
declare current_owner uuid;
begin
  select user_id into current_owner from public.organization_members where organization_id=p_organization_id and role='owner' and active order by created_at limit 1 for update;
  if current_owner is null then raise exception 'Active owner not found';end if;
  if auth.uid()<>current_owner and not public.is_platform_admin() then raise exception 'Only the current owner or platform administrator can transfer ownership';end if;
  if not exists(select 1 from public.organization_members where organization_id=p_organization_id and user_id=p_new_owner and active) then raise exception 'New owner must be an active company member';end if;
  if p_new_owner=current_owner then return;end if;
  perform set_config('plantmaster.owner_transfer','allowed',true);
  update public.organization_members set role='manager',updated_at=now() where organization_id=p_organization_id and user_id=current_owner;
  update public.organization_members set role='owner',updated_at=now() where organization_id=p_organization_id and user_id=p_new_owner;
  insert into public.audit_logs(organization_id,user_id,action,entity_type,entity_id,details) values(p_organization_id,auth.uid(),'ownership_transferred','organization',p_organization_id::text,jsonb_build_object('old_owner',current_owner,'new_owner',p_new_owner,'timestamp',now()));
end $$;
grant execute on function public.transfer_organization_ownership(uuid,uuid) to authenticated;

-- Required legal documents not yet accepted by the signed-in user.
create or replace function public.pending_legal_documents(p_organization_id uuid)
returns table(id uuid,document_type text,version text,title text,content text,effective_at timestamptz)
language sql stable security definer set search_path=public as $$
  select d.id,d.document_type,d.version,d.title,d.content,d.effective_at
  from public.legal_documents d
  where d.active and d.required and d.effective_at<=now()
    and (d.acceptance_scope='all_users' or (d.acceptance_scope='owners' and public.org_role(p_organization_id)='owner') or (d.acceptance_scope='platform_admins' and public.is_platform_admin()))
    and (public.is_org_member(p_organization_id) or public.is_platform_admin())
    and not exists(select 1 from public.legal_acceptances a where a.document_id=d.id and a.user_id=auth.uid())
  order by d.effective_at,d.document_type
$$;
grant execute on function public.pending_legal_documents(uuid) to authenticated;

create or replace function public.accept_legal_document(p_document_id uuid,p_organization_id uuid,p_locale text default null,p_user_agent_hash text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or (not public.is_org_member(p_organization_id) and not public.is_platform_admin()) then raise exception 'Access denied';end if;
  if not exists(select 1 from public.legal_documents where id=p_document_id and active and effective_at<=now()) then raise exception 'Legal document not available';end if;
  insert into public.legal_acceptances(document_id,organization_id,user_id,locale,user_agent_hash) values(p_document_id,p_organization_id,auth.uid(),p_locale,p_user_agent_hash) on conflict(document_id,user_id) do nothing;
end $$;
grant execute on function public.accept_legal_document(uuid,uuid,text,text) to authenticated;

-- Platform tenant overview. It intentionally returns aggregate/commercial data,
-- not customer operational content.
create or replace function public.platform_tenant_overview()
returns table(organization_id uuid,organization_name text,commercial_status text,status_reason text,created_at timestamptz,plan_code text,plan_name text,subscription_status text,period_end timestamptz,workers bigint,plants bigint,files bigint,storage_bytes numeric,ai_requests_month bigint,open_incidents bigint)
language plpgsql stable security definer set search_path=public as $$
begin
  if not public.is_platform_admin() then raise exception 'Platform administrator required';end if;
  return query
  select o.id,o.name,o.commercial_status,o.status_reason,o.created_at,p.code,p.name,s.status,s.current_period_end,
    (select count(*) from public.organization_members m where m.organization_id=o.id and m.active),
    (select count(*) from public.plants pl where pl.organization_id=o.id),
    (select count(*) from public.file_metadata f where f.organization_id=o.id and f.removed_at is null),
    (select coalesce(sum(f.size_bytes),0) from public.file_metadata f where f.organization_id=o.id and f.removed_at is null),
    coalesce((select u.quantity from public.usage_counters u where u.organization_id=o.id and u.metric='ai_requests' and u.period_start=date_trunc('month',current_date)::date),0),
    (select count(*) from public.system_incidents i where i.organization_id=o.id and i.status<>'resolved')
  from public.organizations o left join public.organization_subscriptions s on s.organization_id=o.id left join public.subscription_plans p on p.id=s.plan_id order by o.created_at desc;
end $$;
grant execute on function public.platform_tenant_overview() to authenticated;

create or replace function public.platform_set_company(p_organization_id uuid,p_status text,p_plan_code text default null,p_reason text default null)
returns void language plpgsql security definer set search_path=public as $$
declare plan_uuid uuid;subscription_state text;
begin
  if not public.is_platform_admin() then raise exception 'Platform administrator required';end if;
  if p_status not in ('trial','active','past_due','suspended','cancelled','deletion_pending') then raise exception 'Invalid company status';end if;
  if p_plan_code is not null then select id into plan_uuid from public.subscription_plans where code=p_plan_code and active;if plan_uuid is null then raise exception 'Plan not found';end if;end if;
  update public.organizations set commercial_status=p_status,status_reason=p_reason,suspended_at=case when p_status='suspended' then now() else null end,deletion_scheduled_at=case when p_status='deletion_pending' then coalesce(deletion_scheduled_at,now()+interval '30 days') else null end,commercial_updated_at=now() where id=p_organization_id;
  subscription_state:=case when p_status in ('active','trial','past_due','suspended','cancelled') then p_status else 'cancelled' end;
  update public.organization_subscriptions set plan_id=coalesce(plan_uuid,plan_id),status=subscription_state,updated_at=now() where organization_id=p_organization_id;
  insert into public.audit_logs(organization_id,user_id,action,entity_type,entity_id,details) values(p_organization_id,auth.uid(),'platform_company_updated','organization',p_organization_id::text,jsonb_build_object('status',p_status,'plan_code',p_plan_code,'reason',p_reason,'timestamp',now()));
end $$;
grant execute on function public.platform_set_company(uuid,text,text,text) to authenticated;

create or replace function public.platform_update_incident(p_incident_id uuid,p_status text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_platform_admin() then raise exception 'Platform administrator required';end if;
  if p_status not in ('open','acknowledged','resolved') then raise exception 'Invalid incident status';end if;
  update public.system_incidents set status=p_status,resolved_at=case when p_status='resolved' then now() else null end,last_seen_at=now() where id=p_incident_id;
end $$;
grant execute on function public.platform_update_incident(uuid,text) to authenticated;
