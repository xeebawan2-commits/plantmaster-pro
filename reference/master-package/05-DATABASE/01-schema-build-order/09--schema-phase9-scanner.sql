-- PlantMaster Pro v4.8 Unified Scanner
-- Additive/idempotent. Does not alter or delete existing operational records.

create table if not exists public.scan_sessions(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id uuid references public.plants(id) on delete cascade,
  mode text not null check(mode in ('qr_barcode','document','nameplate','identify','import')),
  source_type text not null default 'camera' check(source_type in ('camera','gallery','file','offline')),
  status text not null default 'draft' check(status in ('draft','processing','completed','failed','submitted','approved')),
  title text,
  original_path text,
  enhanced_path text,
  thumbnail_path text,
  mime_type text,
  file_name text,
  file_size bigint,
  detected_codes jsonb not null default '[]'::jsonb,
  extracted_text text,
  structured_result jsonb not null default '{}'::jsonb,
  confidence text,
  safety_notes text,
  linked_entity_type text,
  linked_entity_id text,
  created_by uuid not null references auth.users(id),
  worker_name text not null,
  designation text,
  shift_name text,
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  removed_at timestamptz,
  removed_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists scan_sessions_org_time_idx on public.scan_sessions(organization_id,created_at desc);
create index if not exists scan_sessions_plant_mode_idx on public.scan_sessions(plant_id,mode,status);
create index if not exists scan_sessions_link_idx on public.scan_sessions(organization_id,linked_entity_type,linked_entity_id);

create table if not exists public.scan_pages(
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.scan_sessions(id) on delete cascade,
  page_number integer not null,
  storage_path text,
  enhanced_path text,
  mime_type text,
  size_bytes bigint,
  width integer,
  height integer,
  rotation integer not null default 0,
  enhancement text default 'original',
  extracted_text text,
  structured_result jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(session_id,page_number)
);

create table if not exists public.code_registry(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id uuid references public.plants(id) on delete cascade,
  code_value text not null,
  code_format text not null default 'QR_CODE',
  entity_type text not null,
  entity_id text not null,
  label text,
  active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_id,code_value)
);
create index if not exists code_registry_entity_idx on public.code_registry(organization_id,entity_type,entity_id);

create table if not exists public.scan_entity_links(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  scan_session_id uuid not null references public.scan_sessions(id) on delete cascade,
  entity_type text not null,
  entity_id text not null,
  relation text not null default 'attachment',
  linked_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique(scan_session_id,entity_type,entity_id,relation)
);

alter table public.scan_sessions enable row level security;
alter table public.scan_pages enable row level security;
alter table public.code_registry enable row level security;
alter table public.scan_entity_links enable row level security;

do $$ begin
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='scan_sessions' and policyname='scanner member access') then
    create policy "scanner member access" on public.scan_sessions for all to authenticated using(public.is_org_member(organization_id)) with check(public.is_org_member(organization_id));
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='scan_pages' and policyname='scanner page member access') then
    create policy "scanner page member access" on public.scan_pages for all to authenticated using(exists(select 1 from public.scan_sessions s where s.id=session_id and public.is_org_member(s.organization_id))) with check(exists(select 1 from public.scan_sessions s where s.id=session_id and public.is_org_member(s.organization_id)));
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='code_registry' and policyname='code registry member access') then
    create policy "code registry member access" on public.code_registry for all to authenticated using(public.is_org_member(organization_id)) with check(public.is_org_member(organization_id));
  end if;
  if not exists(select 1 from pg_policies where schemaname='public' and tablename='scan_entity_links' and policyname='scan links member access') then
    create policy "scan links member access" on public.scan_entity_links for all to authenticated using(public.is_org_member(organization_id)) with check(public.is_org_member(organization_id));
  end if;
end $$;

grant select,insert,update,delete on public.scan_sessions,public.scan_pages,public.code_registry,public.scan_entity_links to authenticated;
grant usage,select on all sequences in schema public to authenticated;

-- Suspended companies cannot create or modify scans.
do $$ declare t text;n text;begin
  foreach t in array array['scan_sessions','code_registry','scan_entity_links'] loop
    n:='commercial_write_guard_'||t;
    if not exists(select 1 from pg_trigger where tgname=n and not tgisinternal) then execute format('create trigger %I before insert or update or delete on public.%I for each row execute function public.require_commercial_write_access()',n,t);end if;
  end loop;
end $$;

-- Owner-only permanent erasure for scan sessions. Normal UI uses removed_at.
do $$ begin
  if not exists(select 1 from pg_trigger where tgname='owner_hard_delete_scan_sessions' and not tgisinternal) then
    create trigger owner_hard_delete_scan_sessions before delete on public.scan_sessions for each row execute function public.require_owner_for_hard_delete();
  end if;
end $$;

-- Realtime scanner log.
do $$ begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='scan_sessions') then
    alter publication supabase_realtime add table public.scan_sessions;
  end if;
end $$;
