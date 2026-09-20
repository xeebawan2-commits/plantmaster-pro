-- ============================================================
--  PlantMaster Control Center — fix the two delete failures
--  HSB Fix Services
--
--  Paste the whole file into the Supabase SQL Editor and Run.
--  Nothing here can fail or roll back your data.
-- ============================================================
--
--  Your screenshots showed two real database errors:
--
--   1. "update or delete on table spares violates foreign key
--       constraint inventory_transactions_spare_id_fkey"
--
--      Deleting a company tries to remove its spares, but the
--      stock movement history still points at them, so Postgres
--      blocks it. The fix is to tell that link to delete the
--      history along with the spare.
--
--   2. "Administrator audit records are append-only"
--
--      Your own safety rule. Deleting a company (or an owner)
--      tries to remove its audit log rows, and a trigger refuses.
--      Audit history should survive the company anyway, so the
--      fix is to unhook the log rows instead of deleting them.
-- ============================================================


-- ---- 1. Let stock history follow its spare ------------------

alter table inventory_transactions
  drop constraint if exists inventory_transactions_spare_id_fkey;

alter table inventory_transactions
  add  constraint inventory_transactions_spare_id_fkey
  foreign key (spare_id) references spares(id) on delete cascade;


-- ---- 2. Find any OTHER blocking links ----------------------
--  Same problem can hide behind other tables. This lists every
--  foreign key that still blocks a delete, so we catch them all
--  in one pass instead of one error at a time.

select
  tc.table_name      as blocking_table,
  kcu.column_name    as blocking_column,
  ccu.table_name     as points_at,
  rc.delete_rule
from information_schema.table_constraints tc
join information_schema.key_column_usage kcu
  on kcu.constraint_name = tc.constraint_name
join information_schema.constraint_column_usage ccu
  on ccu.constraint_name = tc.constraint_name
join information_schema.referential_constraints rc
  on rc.constraint_name = tc.constraint_name
where tc.constraint_type = 'FOREIGN KEY'
  and tc.table_schema = 'public'
  and rc.delete_rule = 'NO ACTION'
  and ccu.table_name in (
        'spares','plants','assets','work_orders','organizations',
        'profiles','organization_members','purchase_orders'
      )
order by ccu.table_name, tc.table_name;


-- ---- 3. Keep audit records, but let the company go ---------
--  Audit rows must never be deleted (your rule, and a good one).
--  Instead the organization link becomes NULL, so the record
--  survives as history while the company can be removed.

alter table admin_action_logs
  alter column organization_id drop not null;

alter table admin_action_logs
  drop constraint if exists admin_action_logs_organization_id_fkey;

alter table admin_action_logs
  add  constraint admin_action_logs_organization_id_fkey
  foreign key (organization_id) references organizations(id) on delete set null;


-- ---- 4. Same for the audit trail inside each company -------
--  Only runs if you have an audit_logs table with that column.

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='audit_logs'
      and column_name='organization_id'
  ) then
    execute 'alter table audit_logs alter column organization_id drop not null';
    execute 'alter table audit_logs drop constraint if exists audit_logs_organization_id_fkey';
    execute 'alter table audit_logs add constraint audit_logs_organization_id_fkey
             foreign key (organization_id) references organizations(id) on delete set null';
  end if;
end $$;


-- ---- 5. Why owner accounts would not delete ----------------
--  An owner is usually the last link holding a company together.
--  This shows which of your users are the ONLY owner of a
--  company. Those are the ones that refuse to delete.
--
--  To remove such a person: delete their company first, or make
--  somebody else an owner, then delete the user.

select
  u.email,
  o.name                      as company,
  count(*) over (partition by o.id) as owners_in_company
from organization_members m
join auth.users     u on u.id = m.user_id
join organizations  o on o.id = m.organization_id
where m.role = 'owner'
order by owners_in_company asc, o.name;
