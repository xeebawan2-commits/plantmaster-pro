-- ===========================================================================
-- PlantMaster Pro — 0007 storage bucket, soft delete & recovery bin
--
-- Object paths are always  <organization_id>/<plant_id>/...  so the first
-- path segment is the tenant boundary. Storage policies enforce that segment,
-- which is what stops one company reading another company's manuals.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- Bucket. Private: downloads always go through a signed URL.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit)
values ('plant-files', 'plant-files', false, 52428800)  -- 50 MB per object
on conflict (id) do update
  set public = false,
      file_size_limit = greatest(coalesce(storage.buckets.file_size_limit, 0), 52428800);

-- Helper: is the caller a member of the tenant that owns this object path?
create or replace function public.storage_path_allowed(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare seg text; org uuid;
begin
  seg := split_part(p_name, '/', 1);
  if seg is null or seg = '' then return false; end if;
  begin
    org := seg::uuid;
  exception when invalid_text_representation then
    return false;
  end;
  return public.is_org_member(org);
end $$;

create or replace function public.storage_path_writable(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare seg text; org uuid;
begin
  seg := split_part(p_name, '/', 1);
  if seg is null or seg = '' then return false; end if;
  begin
    org := seg::uuid;
  exception when invalid_text_representation then
    return false;
  end;
  return public.is_org_member(org)
     and public.can_write(org)
     and public.has_org_role(org, 'technician');
end $$;

do $$
begin
  -- storage.objects is owned by the storage role on hosted Supabase; if this
  -- migration is run by a less-privileged role the policy creation will fail.
  -- Wrapped so the rest of the suite still applies; re-run as owner if needed.
  begin
    drop policy if exists plant_files_select on storage.objects;
    create policy plant_files_select on storage.objects
      for select to authenticated
      using (bucket_id = 'plant-files' and public.storage_path_allowed(name));

    drop policy if exists plant_files_insert on storage.objects;
    create policy plant_files_insert on storage.objects
      for insert to authenticated
      with check (bucket_id = 'plant-files' and public.storage_path_writable(name));

    drop policy if exists plant_files_update on storage.objects;
    create policy plant_files_update on storage.objects
      for update to authenticated
      using (bucket_id = 'plant-files' and public.storage_path_writable(name))
      with check (bucket_id = 'plant-files' and public.storage_path_writable(name));

    drop policy if exists plant_files_delete on storage.objects;
    create policy plant_files_delete on storage.objects
      for delete to authenticated
      using (bucket_id = 'plant-files'
             and public.storage_path_allowed(name)
             and public.has_org_role(split_part(name,'/',1)::uuid, 'manager'));
  exception when insufficient_privilege or undefined_table then
    raise notice 'storage.objects policies skipped (insufficient privilege) — apply as the storage owner';
  end;
end $$;

-- ===========================================================================
-- SOFT DELETE + RECOVERY BIN
--
-- The UI's Recovery Bin lists soft-deleted rows across the tenant. Rather than
-- a hand-written union per table, both functions iterate the tables that have
-- a removed_at column, so a new module is covered automatically.
-- ===========================================================================
create or replace function public.pm_soft_delete_tables()
returns table (table_name text)
language sql
stable
as $$
  select c.table_name::text
  from information_schema.columns c
  join information_schema.tables t
    on t.table_schema = c.table_schema and t.table_name = c.table_name
  where c.table_schema = 'public'
    and c.column_name  = 'removed_at'
    and t.table_type   = 'BASE TABLE'
  order by 1;
$$;

create or replace function public.recovery_bin(
  p_organization_id uuid,
  p_limit           int default 200
) returns table (
  source_table text,
  record_id    uuid,
  label        text,
  removed_at   timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  t text;
  label_col text;
  sql text;
begin
  if not public.is_org_member(p_organization_id) then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  for t in select table_name from public.pm_soft_delete_tables()
  loop
    -- Skip tables that are not tenant scoped.
    if not exists (select 1 from information_schema.columns
                   where table_schema='public' and table_name=t
                     and column_name='organization_id') then
      continue;
    end if;

    select column_name into label_col
      from information_schema.columns
     where table_schema='public' and table_name=t
       and column_name in ('title','name','description','subject','file_name','po_number')
     order by array_position(
       array['title','name','description','subject','file_name','po_number'], column_name)
     limit 1;

    sql := format(
      'select %L::text, id, %s::text, removed_at
         from public.%I
        where organization_id = $1 and removed_at is not null
        order by removed_at desc limit $2',
      t, coalesce(quote_ident(label_col), format('%L', t)), t);

    return query execute sql using p_organization_id, p_limit;
  end loop;
end $$;

-- Restore one soft-deleted row.
create or replace function public.restore_record(
  p_table     text,
  p_record_id uuid
) returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  org uuid;
  ok  boolean;
begin
  -- Whitelist: only tables that actually carry removed_at.
  if not exists (select 1 from public.pm_soft_delete_tables() where table_name = p_table) then
    raise exception 'Table % cannot be restored', p_table using errcode = '22023';
  end if;

  execute format('select organization_id from public.%I where id = $1', p_table)
    into org using p_record_id;
  if org is null then
    raise exception 'Record not found' using errcode = 'P0002';
  end if;

  ok := public.has_org_role(org, 'manager') and public.can_write(org);
  if not ok then
    raise exception 'Only a manager can restore deleted records' using errcode = '42501';
  end if;

  execute format('update public.%I set removed_at = null where id = $1', p_table)
    using p_record_id;

  insert into public.audit_logs
    (organization_id, user_id, action, entity_type, entity_id, details)
  values (org, auth.uid(), 'record_restored', p_table, p_record_id::text, '{}'::jsonb);

  return true;
end $$;

-- Permanently purge rows whose grace period has lapsed. Called by a cron job.
create or replace function public.purge_expired_soft_deletes()
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t text;
  n int := 0;
  hit int;
begin
  for t in select table_name from public.pm_soft_delete_tables()
  loop
    if not exists (select 1 from information_schema.columns
                   where table_schema='public' and table_name=t
                     and column_name='organization_id') then
      continue;
    end if;
    execute format($f$
      delete from public.%I x
       using public.data_retention_policies p
       where x.organization_id = p.organization_id
         and x.removed_at is not null
         and x.removed_at < now() - make_interval(days => p.soft_delete_grace_days)
    $f$, t);
    get diagnostics hit = row_count;
    n := n + hit;
  end loop;
  return n;
end $$;

revoke all on function public.purge_expired_soft_deletes() from public, anon, authenticated;

-- Expire abandoned storage reservations (cron).
create or replace function public.expire_storage_reservations()
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare n int;
begin
  update public.storage_reservations
     set status = 'expired', settled_at = now()
   where status = 'pending' and expires_at <= now();
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.expire_storage_reservations() from public, anon, authenticated;
