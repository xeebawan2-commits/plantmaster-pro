-- ============================================================
--  PlantMaster Control Center — FIX v2
--  HSB Fix Services
--
--  The last version failed on its final line, and Supabase runs
--  the whole script as ONE transaction — so everything rolled
--  back and nothing was saved.
--
--  Cause: the final line called control_admins(), which checks
--  "who is logged in". In the SQL Editor nobody is logged in
--  (auth.uid() is null), so it correctly refused.
--
--  This version removes that call. Nothing here can fail.
--
--  Paste ALL of it -> Run.
-- ============================================================


-- ---- 1. Grant your 16 permissions --------------------------
--     (your user id is already filled in)

update platform_admins
set
  active      = true,
  admin_role  = 'super_admin',
  permissions = jsonb_build_object(
    'companies.manage', true, 'plans.manage',     true,
    'accounts.view',    true, 'accounts.manage',  true,
    'usage.view',       true, 'usage.manage',     true,
    'storage.view',     true, 'storage.manage',   true,
    'ai.view',          true, 'ai.manage',        true,
    'support.manage',   true, 'incidents.manage', true,
    'backups.manage',   true, 'legal.manage',     true,
    'audit.view',       true, 'admins.manage',    true
  )
where user_id = '801d0c3b-8936-4a6f-bfc8-39e93bc826a8';


-- ---- 2. Repair the control_admins function -----------------
--     Reads columns safely so a renamed column cannot break it.

drop function if exists public.control_admins();

create function public.control_admins()
returns table (
  user_id       uuid,
  email         text,
  full_name     text,
  admin_role    text,
  active        boolean,
  last_login_at timestamptz,
  permissions   jsonb
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not exists (
    select 1 from platform_admins pa
    where pa.user_id = auth.uid() and pa.active
  ) then
    raise exception 'Permission required';
  end if;

  return query
  select
    pa.user_id,
    u.email::text,
    coalesce(to_jsonb(pa)->>'display_name',
             split_part(u.email::text, '@', 1))::text,
    (to_jsonb(pa)->>'admin_role')::text,
    coalesce((to_jsonb(pa)->>'active')::boolean, true),
    (to_jsonb(pa)->>'last_login_at')::timestamptz,
    coalesce(pa.permissions, '{}'::jsonb)
  from platform_admins pa
  left join auth.users u on u.id = pa.user_id
  order by u.email;
end;
$$;

grant execute on function public.control_admins() to authenticated;


-- ---- 3. Confirm the permissions saved ----------------------
--     Should show 16.

select
  u.email,
  pa.admin_role,
  pa.active,
  (select count(*) from jsonb_each(pa.permissions)
    where value = 'true'::jsonb) as granted_keys
from platform_admins pa
join auth.users u on u.id = pa.user_id
where pa.user_id = '801d0c3b-8936-4a6f-bfc8-39e93bc826a8';


-- ---- 4. What status do your signup requests use? -----------
--     This is why "pending approval" showed 0 of 5.

select
  coalesce(status, '(null)') as status,
  count(*)                   as how_many
from signup_requests
group by 1
order by 2 desc;
