-- =====================================================================
-- PlantMaster Pro — Procurement schema (suppliers + purchase orders)
-- Builds on your existing `material_requests` table.
-- Run in Supabase SQL editor. Idempotent: safe to re-run.
-- =====================================================================

-- ---------- SUPPLIERS ----------
create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id uuid references public.plants(id) on delete set null,
  name text not null,
  contact_person text,
  phone text,
  email text,
  address text,
  ntn text,                       -- Pakistan National Tax Number
  strn text,                      -- Sales Tax Registration Number
  payment_terms text default 'Net 30',
  currency text not null default 'PKR',
  rating numeric(2,1) check (rating >= 0 and rating <= 5),
  notes text,
  active boolean not null default true,
  removed_at timestamptz,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists suppliers_org_idx   on public.suppliers(organization_id) where removed_at is null;
create index if not exists suppliers_plant_idx on public.suppliers(plant_id)        where removed_at is null;

-- ---------- PURCHASE ORDERS ----------
create table if not exists public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  plant_id uuid not null references public.plants(id) on delete cascade,
  po_number text not null,
  supplier_id uuid references public.suppliers(id) on delete set null,
  status text not null default 'draft'
    check (status in ('draft','pending_approval','approved','sent','partially_received','received','cancelled')),
  currency text not null default 'PKR',
  subtotal    numeric(14,2) not null default 0,
  tax_percent numeric(5,2)  not null default 0,
  tax_amount  numeric(14,2) not null default 0,
  total       numeric(14,2) not null default 0,
  expected_date date,
  received_date date,
  notes text,
  requested_by uuid references auth.users(id),
  approved_by  uuid references auth.users(id),
  approved_at  timestamptz,
  removed_at   timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, po_number)
);

create index if not exists po_plant_idx    on public.purchase_orders(plant_id)    where removed_at is null;
create index if not exists po_status_idx   on public.purchase_orders(status)      where removed_at is null;
create index if not exists po_supplier_idx on public.purchase_orders(supplier_id) where removed_at is null;

-- ---------- PURCHASE ORDER LINES ----------
create table if not exists public.purchase_order_lines (
  id uuid primary key default gen_random_uuid(),
  purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
  spare_id uuid references public.spares(id) on delete set null,
  description text not null,
  quantity      numeric(12,3) not null check (quantity > 0),
  unit          text default 'pcs',
  unit_price    numeric(14,2) not null default 0,
  line_total    numeric(14,2) not null default 0,
  received_qty  numeric(12,3) not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists pol_po_idx on public.purchase_order_lines(purchase_order_id);

-- ---------- LINK material_requests -> PO (if table exists) ----------
do $$
begin
  if exists (select 1 from information_schema.tables
             where table_schema='public' and table_name='material_requests') then
    alter table public.material_requests
      add column if not exists purchase_order_id uuid references public.purchase_orders(id) on delete set null;
  end if;
end $$;

-- ---------- PO NUMBER GENERATOR ----------
-- Produces PO-2026-0001, resetting per organization per year.
create or replace function public.next_po_number(p_org uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  yr text := to_char(now(),'YYYY');
  n  int;
begin
  select coalesce(max(
           nullif(regexp_replace(split_part(po_number,'-',3), '\D','','g'),'')::int
         ), 0) + 1
    into n
    from public.purchase_orders
   where organization_id = p_org
     and po_number like 'PO-'||yr||'-%';
  return 'PO-'||yr||'-'||lpad(n::text, 4, '0');
end $$;

-- ---------- RECALC TOTALS ----------
create or replace function public.recalc_po_totals(p_po uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  s numeric(14,2);
  t numeric(5,2);
begin
  select coalesce(sum(line_total),0) into s
    from public.purchase_order_lines where purchase_order_id = p_po;
  select coalesce(tax_percent,0) into t
    from public.purchase_orders where id = p_po;

  update public.purchase_orders
     set subtotal   = s,
         tax_amount = round(s * t / 100.0, 2),
         total      = s + round(s * t / 100.0, 2),
         updated_at = now()
   where id = p_po;
end $$;

-- keep line_total and header totals correct automatically
create or replace function public.po_line_after_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (tg_op in ('INSERT','UPDATE')) then
    new.line_total := round(new.quantity * new.unit_price, 2);
  end if;

  if tg_op = 'DELETE' then
    perform public.recalc_po_totals(old.purchase_order_id);
    return old;
  end if;

  perform public.recalc_po_totals(new.purchase_order_id);
  return new;
end $$;

drop trigger if exists trg_po_line_biu on public.purchase_order_lines;
create trigger trg_po_line_biu
  before insert or update on public.purchase_order_lines
  for each row execute function public.po_line_after_change();

drop trigger if exists trg_po_line_aid on public.purchase_order_lines;
create trigger trg_po_line_aid
  after insert or update or delete on public.purchase_order_lines
  for each row execute function public.po_line_after_change();

-- ---------- RECEIVE STOCK ATOMICALLY ----------
-- Receives a quantity against a PO line, increments spare stock,
-- writes an inventory_transactions row, and rolls up PO status.
create or replace function public.receive_po_line(
  p_line uuid,
  p_qty  numeric,
  p_user uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_line record;
  v_po   record;
  v_open integer;
begin
  select * into v_line from public.purchase_order_lines where id = p_line;
  if v_line is null then
    raise exception 'Purchase order line not found';
  end if;

  select * into v_po from public.purchase_orders where id = v_line.purchase_order_id;
  if v_po is null then
    raise exception 'Purchase order not found';
  end if;

  if not public.pm_is_org_leader(v_po.organization_id) then
    raise exception 'Only an owner or manager can receive goods';
  end if;

  if p_qty is null or p_qty <= 0 then
    raise exception 'Received quantity must be greater than zero';
  end if;

  if v_line.received_qty + p_qty > v_line.quantity then
    raise exception 'Cannot receive % — only % outstanding',
      p_qty, (v_line.quantity - v_line.received_qty);
  end if;

  update public.purchase_order_lines
     set received_qty = received_qty + p_qty
   where id = p_line;

  -- ---------------- stock + movement log ----------------
  -- Only PO lines linked to a spare affect stock. A line typed in freehand
  -- (or pointing at a tool) updates the PO but moves no inventory.
  if v_line.spare_id is not null then

    update public.spares
       set stock = coalesce(stock,0) + p_qty,
           updated_at = now()
     where id = v_line.spare_id;

    insert into public.inventory_transactions
      (id, spare_id, quantity, transaction_type, reference, performed_by, created_at)
    values
      (gen_random_uuid(),
       v_line.spare_id,
       p_qty,
       'receive',
       'PO ' || v_po.po_number,
       coalesce(p_user, auth.uid()),
       now());

  end if;

  -- ---------------- roll up PO status ----------------
  select count(*) into v_open
    from public.purchase_order_lines
   where purchase_order_id = v_po.id
     and received_qty < quantity;

  update public.purchase_orders
     set status = case when v_open = 0 then 'received' else 'partially_received' end,
         received_date = case when v_open = 0 then current_date else received_date end,
         updated_at = now()
   where id = v_po.id;

  return jsonb_build_object(
    'ok', true,
    'lines_outstanding', v_open,
    'stock_moved', (v_line.spare_id is not null)
  );
end;
$$;

-- =====================================================================
-- ROW LEVEL SECURITY
-- Mirrors your existing organization_members pattern.
-- =====================================================================
alter table public.suppliers            enable row level security;
alter table public.purchase_orders      enable row level security;
alter table public.purchase_order_lines enable row level security;

-- helper: is the caller a member of this org?
create or replace function public.pm_is_org_member(p_org uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.organization_members m
     where m.organization_id = p_org
       and m.user_id = auth.uid()
  );
$$;

-- helper: is the caller owner/manager in this org?
create or replace function public.pm_is_org_leader(p_org uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.organization_members m
     where m.organization_id = p_org
       and m.user_id = auth.uid()
       and m.role in ('owner','manager')
  );
$$;

drop policy if exists suppliers_read  on public.suppliers;
drop policy if exists suppliers_write on public.suppliers;
create policy suppliers_read  on public.suppliers
  for select using (public.pm_is_org_member(organization_id));
create policy suppliers_write on public.suppliers
  for all    using (public.pm_is_org_leader(organization_id))
             with check (public.pm_is_org_leader(organization_id));

drop policy if exists po_read  on public.purchase_orders;
drop policy if exists po_write on public.purchase_orders;
create policy po_read  on public.purchase_orders
  for select using (public.pm_is_org_member(organization_id));
create policy po_write on public.purchase_orders
  for all    using (public.pm_is_org_leader(organization_id))
             with check (public.pm_is_org_leader(organization_id));

drop policy if exists pol_read  on public.purchase_order_lines;
drop policy if exists pol_write on public.purchase_order_lines;
create policy pol_read on public.purchase_order_lines
  for select using (exists (
    select 1 from public.purchase_orders po
     where po.id = purchase_order_id
       and public.pm_is_org_member(po.organization_id)));
create policy pol_write on public.purchase_order_lines
  for all using (exists (
    select 1 from public.purchase_orders po
     where po.id = purchase_order_id
       and public.pm_is_org_leader(po.organization_id)))
  with check (exists (
    select 1 from public.purchase_orders po
     where po.id = purchase_order_id
       and public.pm_is_org_leader(po.organization_id)));

-- =====================================================================

-- ---------- TABLE GRANTS ----------
-- Postgres has two permission layers: GRANT (may this role touch the table?)
-- and RLS (which rows?). Both must pass. Without these, every write fails
-- with error 42501 before RLS is ever evaluated.
grant select, insert, update, delete on public.suppliers            to authenticated;
grant select, insert, update, delete on public.purchase_orders      to authenticated;
grant select, insert, update, delete on public.purchase_order_lines to authenticated;

grant execute on function public.next_po_number(uuid)               to authenticated;
grant execute on function public.receive_po_line(uuid,numeric,uuid) to authenticated;
grant execute on function public.pm_is_org_member(uuid)             to authenticated;
grant execute on function public.pm_is_org_leader(uuid)             to authenticated;

-- DONE.
-- Verify:
--   select public.next_po_number('<your-org-uuid>');
-- =====================================================================
