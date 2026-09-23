-- ============================================================
-- Schema for this section (auto-extracted from the repo / live snapshot)
-- ============================================================


-- ---------- TABLES ----------


-- [material_requests]  source: 0003_inventory_procurement.sql
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


-- [purchase_orders]  source: 0003_inventory_procurement.sql
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


-- [purchase_order_lines]  source: 0003_inventory_procurement.sql
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


-- [suppliers]  source: 0003_inventory_procurement.sql
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



-- ---------- FUNCTIONS / RPCs ----------


-- [next_po_number()]  source: 0003_inventory_procurement.sql
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


-- [receive_po_line()]  source: 0003_inventory_procurement.sql
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
