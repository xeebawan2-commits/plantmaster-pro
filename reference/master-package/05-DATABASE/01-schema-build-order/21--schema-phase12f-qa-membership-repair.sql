-- PlantMaster QA Lab v1.3.0 — repair incomplete QA memberships and diagnostics
-- Restricted to registered organizations whose names begin __PM_QA.

-- Ensure current registered QA environments use a plan that supports all seven roles.
with qa as(
 select e.id,e.organization_id,e.plant_id,e.isolation_organization_id,e.user_ids
 from public.qa_environments e join public.organizations o on o.id=e.organization_id
 where e.status in('ready','failed') and o.name like '__PM_QA__%'
),pro as(select id from public.subscription_plans where code='professional' limit 1)
update public.organization_subscriptions s set plan_id=pro.id,status='active',current_period_end=greatest(coalesce(s.current_period_end,now()),now()+interval '30 days'),updated_at=now()
from qa,pro where s.organization_id in(qa.organization_id,qa.isolation_organization_id);

update public.organizations o set commercial_status='active',status_reason='QA environment membership repair',commercial_updated_at=now()
where o.id in(select organization_id from public.qa_environments where name like '__PM_QA__%' union select isolation_organization_id from public.qa_environments where name like '__PM_QA__%');

-- Restore every role from the server-generated user_ids map.
insert into public.organization_members(organization_id,user_id,role,active,permissions,updated_at)
select e.organization_id,(j.value #>> '{}')::uuid,j.key,true,'{}'::jsonb,now()
from public.qa_environments e cross join lateral jsonb_each(e.user_ids) j
join public.organizations o on o.id=e.organization_id
where e.name like '__PM_QA__%' and o.name like '__PM_QA__%' and j.key in('owner','manager','engineer','supervisor','technician','store','viewer')
on conflict(organization_id,user_id) do update set active=true,role=excluded.role,updated_at=now();

insert into public.plant_members(plant_id,user_id)
select e.plant_id,(j.value #>> '{}')::uuid
from public.qa_environments e cross join lateral jsonb_each(e.user_ids) j
where e.name like '__PM_QA__%' and e.plant_id is not null and j.key in('owner','manager','engineer','supervisor','technician','store','viewer')
on conflict do nothing;

insert into public.organization_members(organization_id,user_id,role,active,permissions,updated_at)
select e.isolation_organization_id,(e.user_ids->>'owner')::uuid,'owner',true,'{}'::jsonb,now()
from public.qa_environments e join public.organizations o on o.id=e.isolation_organization_id
where e.name like '__PM_QA__%' and o.name like '__PM_QA_ISOLATION__%' and e.user_ids ? 'owner'
on conflict(organization_id,user_id) do update set active=true,role='owner',updated_at=now();

insert into public.plant_members(plant_id,user_id)
select p.id,(e.user_ids->>'owner')::uuid from public.qa_environments e join public.plants p on p.organization_id=e.isolation_organization_id
where e.name like '__PM_QA__%' and e.user_ids ? 'owner'
on conflict do nothing;

update public.qa_environments e set status='ready',last_error=null,seed_summary=e.seed_summary||jsonb_build_object('members_repaired_at',now(),'expected_roles',7),updated_at=now()
where e.name like '__PM_QA__%' and e.organization_id is not null;

-- User-scoped identity diagnostic used by the corrected runner.
create or replace function public.qa_identity_context(p_organization_id uuid)
returns jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object(
  'user_id',auth.uid(),
  'organization_id',p_organization_id,
  'is_member',public.is_org_member(p_organization_id),
  'role',public.org_role(p_organization_id),
  'active',exists(select 1 from public.organization_members m where m.organization_id=p_organization_id and m.user_id=auth.uid() and m.active)
 )
$$;
grant execute on function public.qa_identity_context(uuid) to authenticated;

notify pgrst,'reload schema';
