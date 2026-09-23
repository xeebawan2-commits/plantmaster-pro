-- ============================================================
-- Schema for this section (auto-extracted from the repo / live snapshot)
-- ============================================================


-- ---------- TABLES ----------


-- [platform_admins]  source: 0001_foundation.sql
create table if not exists public.platform_admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  email      text,
  note       text,
  created_at timestamptz not null default now()
);



-- ---------- FUNCTIONS / RPCs ----------


-- [control_accounts()]  source: 02-function-source.sql (LIVE snapshot)
CREATE OR REPLACE FUNCTION public.control_accounts(p_search text DEFAULT NULL::text)
 RETURNS TABLE(user_id uuid, email text, full_name text, created_at timestamp with time zone, last_sign_in_at timestamp with time zone, banned_until timestamp with time zone, memberships bigint, companies jsonb, owner_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;


-- [platform_ban_user()]  source: 02-function-source.sql (LIVE snapshot)
CREATE OR REPLACE FUNCTION public.platform_ban_user(p_user_id uuid, p_reason text, p_ban boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  -- 1. Ensure the caller is an active platform admin
  IF NOT EXISTS (SELECT 1 FROM platform_admins WHERE user_id = auth.uid() AND active = true) THEN
    RAISE EXCEPTION 'Unauthorized: Platform admin access required';
  END IF;

  -- 2. Log the action
  INSERT INTO admin_action_logs (admin_user_id, action, target_type, target_id, reason)
  VALUES (auth.uid(), CASE WHEN p_ban THEN 'ban_user' ELSE 'unban_user' END, 'user', p_user_id, p_reason);

  -- 3. Update the banned_until field in auth.users
  IF p_ban THEN
    UPDATE auth.users SET banned_until = '2100-01-01 00:00:00+00' WHERE id = p_user_id;
  ELSE
    UPDATE auth.users SET banned_until = NULL WHERE id = p_user_id;
  END IF;
END;
$function$;


-- [platform_delete_user()]  source: 02-function-source.sql (LIVE snapshot)
CREATE OR REPLACE FUNCTION public.platform_delete_user(p_user_id uuid, p_reason text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  -- 1. Ensure the caller is an active platform admin
  IF NOT EXISTS (SELECT 1 FROM platform_admins WHERE user_id = auth.uid() AND active = true) THEN
    RETURN 'Unauthorized: Platform admin access required';
  END IF;

  -- 2. Prevent self-deletion
  IF p_user_id = auth.uid() THEN
    RETURN 'Cannot delete your own admin account';
  END IF;

  -- 3. Log the action
  INSERT INTO admin_action_logs (admin_user_id, action, target_type, target_id, reason)
  VALUES (auth.uid(), 'delete_user', 'user', p_user_id, p_reason);

  -- 4. Manually delete dependent records to avoid Foreign Key constraint errors
  DELETE FROM organization_members WHERE user_id = p_user_id;
  DELETE FROM profiles WHERE id = p_user_id;
  
  -- Add any other tables if necessary (e.g. platform_admins)
  DELETE FROM platform_admins WHERE user_id = p_user_id;
  
  -- 5. Finally, delete from auth.users
  DELETE FROM auth.users WHERE id = p_user_id;

  RETURN 'Success';
EXCEPTION WHEN OTHERS THEN
  RETURN SQLERRM;
END;
$function$;
