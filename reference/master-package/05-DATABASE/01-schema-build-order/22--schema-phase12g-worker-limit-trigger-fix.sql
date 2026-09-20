-- PlantMaster v1.3.1 — table-safe worker/invitation plan-limit trigger
-- Fixes: record "new" has no field "id" on organization_members.

create or replace function public.enforce_worker_plan_limit()
returns trigger language plpgsql security definer set search_path=public as $$
declare
 row_data jsonb:=to_jsonb(new);
 oid uuid;
 new_user_id uuid;
 new_invitation_id uuid;
 new_role text;
 new_active boolean;
 new_accepted_at timestamptz;
 new_expires_at timestamptz;
 base_limit bigint;
 limit_value bigint;
 active_workers bigint;
 pending_invites bigint;
begin
 oid:=nullif(row_data->>'organization_id','')::uuid;
 new_user_id:=nullif(row_data->>'user_id','')::uuid;
 new_invitation_id:=nullif(row_data->>'id','')::uuid;
 new_role:=row_data->>'role';
 new_active:=coalesce((row_data->>'active')::boolean,false);
 new_accepted_at:=nullif(row_data->>'accepted_at','')::timestamptz;
 new_expires_at:=nullif(row_data->>'expires_at','')::timestamptz;

 if oid is null then raise exception 'Organization is required for worker-limit validation';end if;
 if tg_table_name='invitations' and new_role='owner' then raise exception 'Owner cannot be granted by invitation';end if;

 select p.max_workers into base_limit
 from public.organization_subscriptions s
 join public.subscription_plans p on p.id=s.plan_id
 where s.organization_id=oid and s.status in('active','trial');
 if base_limit is null then raise exception 'Active subscription required';end if;

 limit_value:=public.effective_company_limit(oid,'workers',base_limit);

 if tg_table_name='organization_members' then
  select count(*) into active_workers
  from public.organization_members m
  where m.organization_id=oid and m.active and m.user_id is distinct from new_user_id;
 else
  select count(*) into active_workers
  from public.organization_members m
  where m.organization_id=oid and m.active;
 end if;

 if tg_table_name='invitations' then
  select count(*) into pending_invites
  from public.invitations i
  where i.organization_id=oid and i.accepted_at is null and i.expires_at>now() and i.id is distinct from new_invitation_id;
 else
  select count(*) into pending_invites
  from public.invitations i
  where i.organization_id=oid and i.accepted_at is null and i.expires_at>now();
 end if;

 if tg_table_name='organization_members' and new_active then
  active_workers:=active_workers+1;
 end if;
 if tg_table_name='invitations' and new_accepted_at is null and coalesce(new_expires_at,now()-interval '1 second')>now() then
  pending_invites:=pending_invites+1;
 end if;

 if active_workers+pending_invites>limit_value then
  raise exception 'Worker limit of % reached (active %, pending %)',limit_value,active_workers,pending_invites;
 end if;
 return new;
end $$;

notify pgrst,'reload schema';
