-- ============================================================
-- Schema for this section (auto-extracted from the repo / live snapshot)
-- ============================================================


-- ---------- TABLES ----------


-- [spares]  source: 0003_inventory_procurement.sql
create table if not exists public.spares (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id        uuid not null references public.plants(id) on delete cascade,
  part_number     text,
  description     text not null,
  specification   text,
  unit            text default 'pcs',
  stock           numeric not null default 0,
  minimum         numeric not null default 0,
  location        text,
  unit_cost       numeric default 0,
  asset_id        uuid references public.assets(id) on delete set null,
  created_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  removed_at      timestamptz,
  constraint spares_stock_non_negative check (stock >= 0)
);


-- [tools]  source: 0003_inventory_procurement.sql
create table if not exists public.tools (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references public.organizations(id) on delete cascade,
  plant_id         uuid not null references public.plants(id) on delete cascade,
  tool_code        text,
  name             text not null,
  description      text,
  part_number      text,
  status           text not null default 'available',
  stock            numeric not null default 1,
  holder_id        uuid references auth.users(id) on delete set null,
  location         text,
  calibration_due  date,
  created_by       uuid references auth.users(id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  removed_at       timestamptz
);


-- [inventory_transactions]  source: 0003_inventory_procurement.sql
create table if not exists public.inventory_transactions (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id        uuid not null references public.plants(id) on delete cascade,
  spare_id        uuid not null references public.spares(id) on delete cascade,
  transaction_type text not null,           -- issue | receive | adjust | return
  quantity        numeric not null,
  balance_after   numeric,
  reference       text,
  work_order_id   uuid references public.work_orders(id) on delete set null,
  notes           text,
  performed_by    uuid references auth.users(id) on delete set null,
  worker_name     text,
  created_at      timestamptz not null default now()
);


-- [tool_transactions]  source: 0003_inventory_procurement.sql
create table if not exists public.tool_transactions (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null references public.organizations(id) on delete cascade,
  plant_id         uuid not null references public.plants(id) on delete cascade,
  tool_id          uuid not null references public.tools(id) on delete cascade,
  transaction_type text not null,           -- issue | return | calibrate | repair
  holder_id        uuid references auth.users(id) on delete set null,
  reference        text,
  notes            text,
  performed_by     uuid references auth.users(id) on delete set null,
  worker_name      text,
  created_at       timestamptz not null default now()
);



-- ---------- FUNCTIONS / RPCs ----------


-- [transact_spare()]  source: 0003_inventory_procurement.sql
create or replace function public.transact_spare(
  p_spare_id  uuid,
  p_type      text,
  p_quantity  numeric,
  p_reference text default null,
  p_notes     text default null
) returns public.inventory_transactions
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  s   public.spares;
  d   numeric;
  tx  public.inventory_transactions;
begin
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Quantity must be greater than zero' using errcode = '22023';
  end if;
  if p_type not in ('issue','receive','adjust','return') then
    raise exception 'Unknown transaction type %', p_type using errcode = '22023';
  end if;

  -- Row lock prevents two concurrent issues from overselling stock.
  select * into s from public.spares where id = p_spare_id for update;
  if not found then
    raise exception 'Spare not found' using errcode = 'P0002';
  end if;
  if not public.has_org_role(s.organization_id, 'technician')
     or not public.can_write(s.organization_id) then
    raise exception 'Not authorized to move stock' using errcode = '42501';
  end if;

  d := case when p_type in ('receive','return') then p_quantity
            when p_type = 'adjust' then p_quantity - s.stock
            else -p_quantity end;

  if s.stock + d < 0 then
    raise exception 'Only % % in stock', s.stock, coalesce(s.unit,'pcs')
      using errcode = '23514';
  end if;

  update public.spares
     set stock = stock + d, updated_at = now()
   where id = p_spare_id;

  insert into public.inventory_transactions(
    organization_id, plant_id, spare_id, transaction_type, quantity,
    balance_after, reference, notes, performed_by)
  values (s.organization_id, s.plant_id, p_spare_id, p_type, abs(p_quantity),
          s.stock + d, p_reference, p_notes, auth.uid())
  returning * into tx;

  return tx;
end $$;


-- [transact_tool()]  source: 0003_inventory_procurement.sql
create or replace function public.transact_tool(
  p_tool_id   uuid,
  p_type      text,
  p_holder_id uuid default null,
  p_reference text default null,
  p_notes     text default null
) returns public.tool_transactions
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  t  public.tools;
  tx public.tool_transactions;
begin
  if p_type not in ('issue','return','calibrate','repair') then
    raise exception 'Unknown tool transaction type %', p_type using errcode = '22023';
  end if;

  select * into t from public.tools where id = p_tool_id for update;
  if not found then
    raise exception 'Tool not found' using errcode = 'P0002';
  end if;
  if not public.has_org_role(t.organization_id, 'technician')
     or not public.can_write(t.organization_id) then
    raise exception 'Not authorized to move tools' using errcode = '42501';
  end if;

  if p_type = 'issue' then
    if t.status = 'issued' then
      raise exception 'Tool is already issued' using errcode = '23514';
    end if;
    update public.tools
       set status = 'issued', holder_id = coalesce(p_holder_id, auth.uid()), updated_at = now()
     where id = p_tool_id;
  elsif p_type = 'return' then
    update public.tools
       set status = 'available', holder_id = null, updated_at = now()
     where id = p_tool_id;
  else
    update public.tools
       set status = p_type, updated_at = now()
     where id = p_tool_id;
  end if;

  insert into public.tool_transactions(
    organization_id, plant_id, tool_id, transaction_type, holder_id,
    reference, notes, performed_by)
  values (t.organization_id, t.plant_id, p_tool_id, p_type,
          coalesce(p_holder_id, auth.uid()), p_reference, p_notes, auth.uid())
  returning * into tx;

  return tx;
end $$;
