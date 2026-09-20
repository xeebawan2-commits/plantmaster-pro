-- ===========================================================================
-- PlantMaster Pro — 0003 inventory & procurement
--   spares, tools, custody/stock ledgers, suppliers, purchase orders,
--   material requests, and the QR code registry.
--
-- Stock is never mutated directly by the client. transact_spare() /
-- transact_tool() / receive_po_line() are the only write paths, so the ledger
-- and the on-hand quantity can never drift apart.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- SPARES
-- ---------------------------------------------------------------------------
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
create index if not exists spares_plant_idx on public.spares(plant_id) where removed_at is null;
create index if not exists spares_org_idx   on public.spares(organization_id);
create unique index if not exists spares_part_unique
  on public.spares(organization_id, part_number)
  where part_number is not null and removed_at is null;
-- Low-stock dashboard query.
create index if not exists spares_low_idx on public.spares(plant_id)
  where removed_at is null;

-- ---------------------------------------------------------------------------
-- TOOLS
-- ---------------------------------------------------------------------------
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
create index if not exists tools_plant_idx on public.tools(plant_id) where removed_at is null;
create unique index if not exists tools_code_unique
  on public.tools(organization_id, tool_code)
  where tool_code is not null and removed_at is null;

-- ---------------------------------------------------------------------------
-- LEDGERS (append-only)
-- ---------------------------------------------------------------------------
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
create index if not exists inv_tx_spare_idx on public.inventory_transactions(spare_id, created_at desc);
create index if not exists inv_tx_plant_idx on public.inventory_transactions(plant_id, created_at desc);

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
create index if not exists tool_tx_tool_idx  on public.tool_transactions(tool_id, created_at desc);
create index if not exists tool_tx_plant_idx on public.tool_transactions(plant_id, created_at desc);

-- ---------------------------------------------------------------------------
-- SUPPLIERS
-- ---------------------------------------------------------------------------
create table if not exists public.suppliers (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id        uuid references public.plants(id) on delete cascade,
  name            text not null,
  contact_person  text,
  phone           text,
  email           text,
  ntn             text,
  strn            text,
  payment_terms   text,
  currency        text default 'PKR',
  rating          numeric,
  address         text,
  notes           text,
  created_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  removed_at      timestamptz
);
create index if not exists suppliers_org_idx on public.suppliers(organization_id) where removed_at is null;

-- ---------------------------------------------------------------------------
-- PURCHASE ORDERS
-- ---------------------------------------------------------------------------
create table if not exists public.purchase_orders (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id        uuid not null references public.plants(id) on delete cascade,
  po_number       text not null,
  supplier_id     uuid references public.suppliers(id) on delete set null,
  status          text not null default 'draft',   -- draft|submitted|approved|partial|received|cancelled
  currency        text default 'PKR',
  tax_percent     numeric default 0,
  subtotal        numeric default 0,
  tax_amount      numeric default 0,
  total           numeric default 0,
  expected_date   date,
  notes           text,
  requested_by    uuid references auth.users(id) on delete set null,
  approved_by     uuid references auth.users(id) on delete set null,
  approved_at     timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  removed_at      timestamptz
);
create unique index if not exists po_number_unique
  on public.purchase_orders(organization_id, po_number);
create index if not exists po_plant_idx    on public.purchase_orders(plant_id) where removed_at is null;
create index if not exists po_supplier_idx on public.purchase_orders(supplier_id);

create table if not exists public.purchase_order_lines (
  id                uuid primary key default gen_random_uuid(),
  purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
  spare_id          uuid references public.spares(id) on delete set null,
  description       text not null,
  quantity          numeric not null default 1,
  received_qty      numeric not null default 0,
  unit              text default 'pcs',
  unit_price        numeric not null default 0,
  line_total        numeric generated always as (quantity * unit_price) stored,
  created_at        timestamptz not null default now(),
  constraint pol_qty_positive check (quantity > 0),
  constraint pol_received_sane check (received_qty >= 0 and received_qty <= quantity)
);
create index if not exists pol_po_idx on public.purchase_order_lines(purchase_order_id);

-- ---------------------------------------------------------------------------
-- MATERIAL REQUESTS
-- ---------------------------------------------------------------------------
create table if not exists public.material_requests (
  id                uuid primary key default gen_random_uuid(),
  organization_id   uuid not null references public.organizations(id) on delete cascade,
  plant_id          uuid not null references public.plants(id) on delete cascade,
  spare_id          uuid references public.spares(id) on delete set null,
  description       text,
  part_number       text,
  unit              text,
  quantity          numeric not null default 1,
  urgency           text default 'normal',
  status            text not null default 'requested',
  notes             text,
  requested_by      uuid references auth.users(id) on delete set null,
  managed_by        uuid references auth.users(id) on delete set null,
  purchase_order_id uuid references public.purchase_orders(id) on delete set null,
  work_order_id     uuid references public.work_orders(id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  removed_at        timestamptz
);
create index if not exists mr_plant_idx on public.material_requests(plant_id, created_at desc);
create index if not exists mr_po_idx    on public.material_requests(purchase_order_id);

-- ---------------------------------------------------------------------------
-- QR CODE REGISTRY — resolves a scanned code to any entity
-- ---------------------------------------------------------------------------
create table if not exists public.code_registry (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id        uuid references public.plants(id) on delete cascade,
  code_value      text not null,
  entity_type     text not null,           -- asset | spare | tool | location
  entity_id       uuid,
  name            text,
  description     text,
  asset_code      text,
  part_number     text,
  tool_code       text,
  status          text,
  stock           numeric,
  active          boolean not null default true,
  created_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create unique index if not exists code_registry_unique
  on public.code_registry(organization_id, code_value) where active;

-- ===========================================================================
-- Triggers + policies
-- ===========================================================================
do $$
declare t text;
begin
  foreach t in array array[
    'spares','tools','inventory_transactions','tool_transactions','suppliers',
    'purchase_orders','material_requests','code_registry']
  loop
    perform public.pm_attach_tenant_guards(t);
  end loop;
end $$;

select public.pm_standard_policies('spares',            'technician');
select public.pm_standard_policies('tools',             'technician');
select public.pm_standard_policies('suppliers',         'manager');
select public.pm_standard_policies('purchase_orders',   'supervisor');
select public.pm_standard_policies('material_requests', 'operator');
select public.pm_standard_policies('code_registry',     'supervisor');

-- Ledgers are append-only: readable by members, insertable by the RPCs
-- (which run as SECURITY DEFINER), never updatable or deletable.
do $$
declare t text;
begin
  foreach t in array array['inventory_transactions','tool_transactions']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %1$s_select on public.%1$s', t);
    execute format(
      'create policy %1$s_select on public.%1$s for select to authenticated
         using (public.is_org_member(organization_id))', t);
    execute format('drop policy if exists %1$s_insert on public.%1$s', t);
    execute format(
      'create policy %1$s_insert on public.%1$s for insert to authenticated
         with check (public.has_org_role(organization_id, ''technician'')
                     and public.can_write(organization_id))', t);
    -- deliberately no update/delete policy: the ledger is immutable.
  end loop;
end $$;

-- purchase_order_lines authorize through the parent PO.
alter table public.purchase_order_lines enable row level security;

drop policy if exists pol_select on public.purchase_order_lines;
create policy pol_select on public.purchase_order_lines
  for select to authenticated
  using (exists (select 1 from public.purchase_orders po
                 where po.id = purchase_order_id and public.is_org_member(po.organization_id)));

drop policy if exists pol_write on public.purchase_order_lines;
create policy pol_write on public.purchase_order_lines
  for all to authenticated
  using (exists (select 1 from public.purchase_orders po
                 where po.id = purchase_order_id
                   and public.has_org_role(po.organization_id, 'supervisor')
                   and public.can_write(po.organization_id)))
  with check (exists (select 1 from public.purchase_orders po
                 where po.id = purchase_order_id
                   and public.has_org_role(po.organization_id, 'supervisor')
                   and public.can_write(po.organization_id)));

-- ===========================================================================
-- RPCs
-- ===========================================================================

-- Sequential, gap-tolerant PO numbers per tenant: PO-2026-0001.
-- Advisory lock serialises concurrent callers within the transaction.
create or replace function public.next_po_number(p_org uuid)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  yr text := to_char(now(), 'YYYY');
  n  int;
begin
  if not public.has_org_role(p_org, 'supervisor') then
    raise exception 'Not authorized to create purchase orders' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtext('po_number:' || p_org::text));

  select coalesce(max((regexp_replace(po_number, '^PO-\d{4}-', ''))::int), 0) + 1
    into n
  from public.purchase_orders
  where organization_id = p_org
    and po_number ~ ('^PO-' || yr || '-\d+$');

  return 'PO-' || yr || '-' || lpad(n::text, 4, '0');
end $$;

-- Atomic spare movement: writes the ledger and the on-hand quantity together.
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

-- Tool custody. Issuing sets the holder; returning clears it.
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

-- Goods receipt: increments the PO line, adds the spare to stock through the
-- same ledger, and rolls the PO status forward — one transaction.
create or replace function public.receive_po_line(
  p_line_id  uuid,
  p_quantity numeric,
  p_notes    text default null
) returns public.purchase_order_lines
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  ln  public.purchase_order_lines;
  po  public.purchase_orders;
  remaining numeric;
begin
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Received quantity must be greater than zero' using errcode = '22023';
  end if;

  select * into ln from public.purchase_order_lines where id = p_line_id for update;
  if not found then
    raise exception 'Purchase order line not found' using errcode = 'P0002';
  end if;
  select * into po from public.purchase_orders where id = ln.purchase_order_id for update;

  if not public.has_org_role(po.organization_id, 'supervisor')
     or not public.can_write(po.organization_id) then
    raise exception 'Not authorized to receive goods' using errcode = '42501';
  end if;

  remaining := ln.quantity - ln.received_qty;
  if p_quantity > remaining then
    raise exception 'Only % remaining on this line', remaining using errcode = '23514';
  end if;

  update public.purchase_order_lines
     set received_qty = received_qty + p_quantity
   where id = p_line_id
  returning * into ln;

  if ln.spare_id is not null then
    perform public.transact_spare(
      ln.spare_id, 'receive', p_quantity,
      'PO ' || po.po_number, coalesce(p_notes, 'Goods receipt'));
  end if;

  update public.purchase_orders
     set status = case
           when not exists (select 1 from public.purchase_order_lines l
                            where l.purchase_order_id = po.id
                              and l.received_qty < l.quantity) then 'received'
           else 'partial' end,
         updated_at = now()
   where id = po.id;

  return ln;
end $$;

-- Keep PO money columns correct whenever lines change.
create or replace function public.recalc_po_totals()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  target uuid := coalesce(new.purchase_order_id, old.purchase_order_id);
  sub numeric;
  pct numeric;
begin
  select coalesce(sum(line_total), 0) into sub
    from public.purchase_order_lines where purchase_order_id = target;
  select coalesce(tax_percent, 0) into pct
    from public.purchase_orders where id = target;

  update public.purchase_orders
     set subtotal   = sub,
         tax_amount = round(sub * pct / 100.0, 2),
         total      = sub + round(sub * pct / 100.0, 2),
         updated_at = now()
   where id = target;

  return null;
end $$;

drop trigger if exists po_lines_totals on public.purchase_order_lines;
create trigger po_lines_totals
  after insert or update or delete on public.purchase_order_lines
  for each row execute function public.recalc_po_totals();
