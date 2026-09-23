-- ============================================================
-- Schema for this section (auto-extracted from the repo / live snapshot)
-- ============================================================



-- ---------- FUNCTIONS / RPCs ----------


-- [control_storage()]  source: 02-function-source.sql (LIVE snapshot)
CREATE OR REPLACE FUNCTION public.control_storage(p_organization_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(file_id uuid, organization_id uuid, company text, file_name text, category text, mime_type text, size_bytes bigint, object_path text, uploaded_by uuid, uploader text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$begin
 if not public.platform_has_permission('storage.view') then raise exception 'Permission required';end if;
 return query select f.id,f.organization_id,o.name,f.file_name,f.category,f.mime_type,f.size_bytes,f.object_path,f.uploaded_by,p.full_name,f.created_at from file_metadata f join organizations o on o.id=f.organization_id left join profiles p on p.id=f.uploaded_by where f.removed_at is null and (p_organization_id is null or f.organization_id=p_organization_id) order by f.created_at desc limit 1000;end$function$;
