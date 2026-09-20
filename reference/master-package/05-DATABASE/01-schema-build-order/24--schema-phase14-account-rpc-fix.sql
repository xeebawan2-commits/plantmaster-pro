-- PlantMaster Control Center v1.3.3 — Accounts RPC return-type repair
-- Fixes: structure of query does not match function result type.

create or replace function public.control_accounts(p_search text default null)
returns table(
 user_id uuid,
 email text,
 full_name text,
 created_at timestamptz,
 last_sign_in_at timestamptz,
 banned_until timestamptz,
 memberships bigint,
 companies jsonb,
 owner_count bigint
)
language plpgsql stable security definer set search_path=public as $$
begin
 if not public.platform_has_permission('accounts.view') then
  raise exception 'Permission required';
 end if;

 return query
 select
  u.id::uuid as user_id,
  coalesce(u.email,'')::text as email,
  coalesce(p.full_name,'')::text as full_name,
  u.created_at::timestamptz as created_at,
  u.last_sign_in_at::timestamptz as last_sign_in_at,
  u.banned_until::timestamptz as banned_until,
  (select count(*)::bigint from public.organization_members m where m.user_id=u.id) as memberships,
  coalesce((
   select jsonb_agg(jsonb_build_object(
    'organization_id',o.id,
    'company',o.name,
    'role',m.role,
    'active',m.active
   ) order by o.name)
   from public.organization_members m
   join public.organizations o on o.id=m.organization_id
   where m.user_id=u.id
  ),'[]'::jsonb) as companies,
  (select count(*)::bigint from public.organization_members m where m.user_id=u.id and m.role='owner' and m.active) as owner_count
 from auth.users u
 left join public.profiles p on p.id=u.id
 where p_search is null
    or coalesce(u.email,'')::text ilike '%'||p_search||'%'
    or coalesce(p.full_name,'')::text ilike '%'||p_search||'%'
 order by u.created_at desc
 limit 500;
end $$;

grant execute on function public.control_accounts(text) to authenticated;
notify pgrst,'reload schema';
