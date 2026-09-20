-- PlantMaster Pro v4.5 production hardening
-- Additive/idempotent. Preserves all existing data.

create or replace function public.has_org_permission(p_org uuid,p_permission text)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(
    select 1 from public.organization_members m
    where m.organization_id=p_org and m.user_id=auth.uid() and m.active
      and (m.role in ('owner','manager') or coalesce((m.permissions->>p_permission)::boolean,false))
  )
$$;
grant execute on function public.has_org_permission(uuid,text) to authenticated;

-- Atomic spare transaction. Row locking prevents two simultaneous users from
-- issuing the same stock balance and creating a negative quantity.
create or replace function public.transact_spare(
  p_spare_id uuid,
  p_type text,
  p_quantity numeric,
  p_reference text default null,
  p_worker_name text default '',
  p_designation text default '',
  p_shift_name text default ''
) returns numeric
language plpgsql security definer set search_path=public as $$
declare s public.spares%rowtype; new_stock numeric; signed_quantity numeric;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_type not in ('receive','issue','adjustment') then raise exception 'Invalid transaction type'; end if;
  if p_quantity <= 0 then raise exception 'Quantity must be greater than zero'; end if;
  select * into s from public.spares where id=p_spare_id for update;
  if not found then raise exception 'Spare not found'; end if;
  if not public.has_org_permission(s.organization_id,'inventory.transact') and public.org_role(s.organization_id) not in ('engineer','supervisor','store','technician') then
    raise exception 'Inventory transaction permission required';
  end if;
  new_stock := case when p_type='issue' then s.stock-p_quantity when p_type='adjustment' then p_quantity else s.stock+p_quantity end;
  if new_stock < 0 then raise exception 'Issue quantity exceeds available stock'; end if;
  signed_quantity := case when p_type='issue' then -p_quantity else p_quantity end;
  insert into public.inventory_transactions(id,spare_id,quantity,transaction_type,reference,performed_by,created_at)
    values(gen_random_uuid(),s.id,signed_quantity,p_type,concat_ws(' | ',nullif(p_reference,''),nullif(p_worker_name,''),nullif(p_designation,''),nullif(p_shift_name,'')),auth.uid(),now());
  update public.spares set stock=new_stock,updated_at=now() where id=s.id;
  insert into public.audit_logs(organization_id,plant_id,user_id,action,entity_type,entity_id,details)
    values(s.organization_id,s.plant_id,auth.uid(),'inventory_transaction','spare',s.id::text,jsonb_build_object('type',p_type,'quantity',p_quantity,'new_stock',new_stock,'worker_name',p_worker_name,'designation',p_designation,'shift_name',p_shift_name,'timestamp',now()));
  return new_stock;
end $$;
grant execute on function public.transact_spare(uuid,text,numeric,text,text,text,text) to authenticated;

-- Atomic tool custody transaction.
create or replace function public.transact_tool(
  p_tool_id uuid,
  p_type text,
  p_holder_id uuid default null,
  p_condition text default null,
  p_notes text default null,
  p_worker_name text default '',
  p_designation text default '',
  p_shift_name text default ''
) returns text
language plpgsql security definer set search_path=public as $$
declare t public.tools%rowtype; new_status text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_type not in ('checkout','return','calibration','inspection') then raise exception 'Invalid tool transaction type'; end if;
  select * into t from public.tools where id=p_tool_id for update;
  if not found then raise exception 'Tool not found'; end if;
  if not public.has_org_permission(t.organization_id,'inventory.transact') and public.org_role(t.organization_id) not in ('engineer','supervisor','store','technician') then
    raise exception 'Tool transaction permission required';
  end if;
  if p_type='checkout' and t.status='checked_out' then raise exception 'Tool is already checked out'; end if;
  new_status := case when p_type='checkout' then 'checked_out' else 'available' end;
  insert into public.tool_transactions(id,organization_id,plant_id,tool_id,transaction_type,holder_id,condition,notes,performed_by,worker_name,designation,shift_name,created_at)
    values(gen_random_uuid(),t.organization_id,t.plant_id,t.id,p_type,p_holder_id,p_condition,p_notes,auth.uid(),p_worker_name,p_designation,p_shift_name,now());
  update public.tools set status=new_status,holder_id=case when p_type='checkout' then p_holder_id else null end,condition=coalesce(p_condition,condition),calibration_due=case when p_type='calibration' then null else calibration_due end,updated_at=now() where id=t.id;
  insert into public.audit_logs(organization_id,plant_id,user_id,action,entity_type,entity_id,details)
    values(t.organization_id,t.plant_id,auth.uid(),'tool_'||p_type,'tool',t.id::text,jsonb_build_object('holder_id',p_holder_id,'condition',p_condition,'worker_name',p_worker_name,'designation',p_designation,'shift_name',p_shift_name,'timestamp',now()));
  return new_status;
end $$;
grant execute on function public.transact_tool(uuid,text,uuid,text,text,text,text,text) to authenticated;

-- Version metadata for later optimistic conflict checks.
do $$ declare t text; begin
  foreach t in array array['assets','work_orders','checklist_templates','maintenance_plans','spares','tools'] loop
    execute format('alter table public.%I add column if not exists row_version bigint not null default 1',t);
  end loop;
end $$;

create or replace function public.bump_row_version()
returns trigger language plpgsql as $$ begin new.row_version=coalesce(old.row_version,0)+1;return new;end $$;
do $$ declare t text; n text; begin
  foreach t in array array['assets','work_orders','checklist_templates','maintenance_plans','spares','tools'] loop
    n:='bump_version_'||t;
    if not exists(select 1 from pg_trigger where tgname=n and not tgisinternal) then
      execute format('create trigger %I before update on public.%I for each row execute function public.bump_row_version()',n,t);
    end if;
  end loop;
end $$;

-- Enable realtime for operational tables when not already included.
do $$ declare t text; begin
  foreach t in array array['notifications','checklist_templates','checklist_runs','maintenance_plans','maintenance_completions','spares','tools','inventory_transactions','tool_transactions','support_threads','support_messages','manuals','problem_cases','shift_assignments','attendance','shift_handovers','daily_logs'] loop
    if to_regclass('public.'||t) is not null and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
      execute format('alter publication supabase_realtime add table public.%I',t);
    end if;
  end loop;
end $$;
