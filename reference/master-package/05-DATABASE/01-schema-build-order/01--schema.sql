-- PlantMaster Pro v4 Phase 1: multi-tenant production foundation
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  avatar_path text,
  created_at timestamptz not null default now()
);
create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text unique,
  logo_path text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);
create table if not exists public.organization_members (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check(role in ('owner','manager','engineer','supervisor','technician','store','viewer')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key(organization_id,user_id)
);
create table if not exists public.plants (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  location text,
  created_at timestamptz not null default now()
);
create table if not exists public.plant_members (
  plant_id uuid not null references public.plants(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(plant_id,user_id)
);
create table if not exists public.assets (
  id uuid primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id uuid not null references public.plants(id) on delete cascade,
  asset_code text not null,
  name text not null,
  asset_type text not null,
  location text,
  manufacturer text,
  model text,
  serial_number text,
  rating text,
  status text not null default 'operational',
  running_state text not null default 'shutdown',
  details jsonb not null default '{}'::jsonb,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(plant_id,asset_code)
);
create index if not exists assets_plant_updated_idx on public.assets(plant_id,updated_at desc);
create table if not exists public.work_orders (
  id uuid primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id uuid not null references public.plants(id) on delete cascade,
  asset_id uuid references public.assets(id) on delete set null,
  title text not null,
  description text not null,
  priority text not null default 'medium',
  status text not null default 'open',
  assigned_to uuid references auth.users(id),
  due_at timestamptz,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists work_orders_plant_updated_idx on public.work_orders(plant_id,updated_at desc);
create table if not exists public.file_metadata (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id uuid references public.plants(id) on delete cascade,
  asset_id uuid references public.assets(id) on delete set null,
  bucket text not null default 'plant-files',
  object_path text not null unique,
  file_name text not null,
  mime_type text,
  size_bytes bigint,
  category text,
  uploaded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);
create table if not exists public.audit_logs (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id uuid references public.plants(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.is_org_member(org uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from organization_members m where m.organization_id=org and m.user_id=auth.uid() and m.active)
$$;
create or replace function public.org_role(org uuid)
returns text language sql stable security definer set search_path=public as $$
  select role from organization_members where organization_id=org and user_id=auth.uid() and active limit 1
$$;
create or replace function public.create_organization(org_name text, plant_name text)
returns table(organization_id uuid, plant_id uuid)
language plpgsql security definer set search_path=public as $$
declare o uuid; p uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  insert into organizations(name,slug,created_by) values(org_name,lower(regexp_replace(org_name,'[^a-zA-Z0-9]+','-','g'))||'-'||substr(gen_random_uuid()::text,1,6),auth.uid()) returning id into o;
  insert into organization_members values(o,auth.uid(),'owner',true,now());
  insert into plants(organization_id,name) values(o,plant_name) returning id into p;
  insert into plant_members values(p,auth.uid(),now());
  return query select o,p;
end $$;
grant execute on function public.create_organization(text,text) to authenticated;

alter table profiles enable row level security; alter table organizations enable row level security; alter table organization_members enable row level security; alter table plants enable row level security; alter table plant_members enable row level security; alter table assets enable row level security; alter table work_orders enable row level security; alter table file_metadata enable row level security; alter table audit_logs enable row level security;
create policy "profile self" on profiles for all to authenticated using(id=auth.uid()) with check(id=auth.uid());
create policy "org members read" on organizations for select to authenticated using(is_org_member(id));
create policy "members read" on organization_members for select to authenticated using(is_org_member(organization_id));
create policy "plants read" on plants for select to authenticated using(is_org_member(organization_id));
create policy "assets read" on assets for select to authenticated using(is_org_member(organization_id));
create policy "assets write" on assets for all to authenticated using(is_org_member(organization_id) and org_role(organization_id) in ('owner','manager','engineer','supervisor','technician')) with check(is_org_member(organization_id) and org_role(organization_id) in ('owner','manager','engineer','supervisor','technician'));
create policy "work read" on work_orders for select to authenticated using(is_org_member(organization_id));
create policy "work write" on work_orders for all to authenticated using(is_org_member(organization_id) and org_role(organization_id) <> 'viewer') with check(is_org_member(organization_id) and org_role(organization_id) <> 'viewer');
create policy "files read" on file_metadata for select to authenticated using(is_org_member(organization_id));
create policy "files write" on file_metadata for insert to authenticated with check(is_org_member(organization_id));
create policy "audit read" on audit_logs for select to authenticated using(is_org_member(organization_id));
create policy "audit insert" on audit_logs for insert to authenticated with check(is_org_member(organization_id));

grant usage on schema public to authenticated;
grant select,insert,update,delete on profiles,organizations,organization_members,plants,plant_members,assets,work_orders,file_metadata,audit_logs to authenticated;
grant usage,select on all sequences in schema public to authenticated;

insert into storage.buckets(id,name,public,file_size_limit) values('plant-files','plant-files',false,52428800) on conflict(id) do update set file_size_limit=excluded.file_size_limit;
create policy "plant file read" on storage.objects for select to authenticated
using(bucket_id='plant-files' and public.is_org_member(((storage.foldername(name))[1])::uuid));
create policy "plant file insert" on storage.objects for insert to authenticated
with check(bucket_id='plant-files' and public.is_org_member(((storage.foldername(name))[1])::uuid));
create policy "plant file update" on storage.objects for update to authenticated
using(bucket_id='plant-files' and public.is_org_member(((storage.foldername(name))[1])::uuid))
with check(bucket_id='plant-files' and public.is_org_member(((storage.foldername(name))[1])::uuid));

alter publication supabase_realtime add table public.assets;
alter publication supabase_realtime add table public.work_orders;
