-- ============================================================
--  PlantMaster — make owner / user deletion work
--  HSB Fix Services
--
--  Paste the whole file, Run. Safe to run more than once.
-- ============================================================
--
--  Why script 04 did not fix this:
--  it repaired the links that point at COMPANIES. Deleting a
--  USER is blocked by a completely different set of links --
--  every table that records "who did this" points at the user,
--  and Postgres will not delete somebody while those rows exist.
--
--  This script keeps all of that history. It does NOT delete
--  work orders, logs or records. It only unhooks the person
--  from them, so the login can be removed.
-- ============================================================


-- ---- 1. Show me the delete function's own rules ------------
--  If platform_delete_user refuses on purpose (for example
--  "cannot delete the last owner"), the reason is written here.
--  Read the output of this one and tell me what it says.

select pg_get_functiondef(p.oid) as delete_user_function
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'platform_delete_user';


-- ---- 2. Everything currently blocking a user delete --------

select
  tc.table_name   as blocking_table,
  kcu.column_name as blocking_column,
  rc.delete_rule
from information_schema.table_constraints tc
join information_schema.key_column_usage kcu
  on kcu.constraint_name = tc.constraint_name
join information_schema.constraint_column_usage ccu
  on ccu.constraint_name = tc.constraint_name
join information_schema.referential_constraints rc
  on rc.constraint_name = tc.constraint_name
where tc.constraint_type = 'FOREIGN KEY'
  and ccu.table_name = 'users'
  and rc.delete_rule = 'NO ACTION'
order by tc.table_name;


-- ---- 3. Unhook the person, keep the history ----------------
--  For each blocking link:
--    * membership / admin rows  -> deleted with the user
--      (a membership means nothing once the person is gone)
--    * everything else          -> the user column becomes
--      empty, and the record itself is kept
--
--  Nothing below deletes business data.

do $$
declare
  r record;
  drop_with_user text[] := array['organization_members','platform_admins'];
begin
  for r in
    select
      tc.constraint_name as con,
      tc.table_name      as tbl,
      kcu.column_name    as col
    from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu
      on kcu.constraint_name = tc.constraint_name
    join information_schema.constraint_column_usage ccu
      on ccu.constraint_name = tc.constraint_name
    join information_schema.referential_constraints rc
      on rc.constraint_name = tc.constraint_name
    where tc.constraint_type = 'FOREIGN KEY'
      and tc.table_schema = 'public'
      and ccu.table_name  = 'users'
      and rc.delete_rule  = 'NO ACTION'
  loop
    begin
      execute format('alter table public.%I drop constraint %I', r.tbl, r.con);

      if r.tbl = any(drop_with_user) then
        execute format(
          'alter table public.%I add constraint %I foreign key (%I)
             references auth.users(id) on delete cascade',
          r.tbl, r.con, r.col);
        raise notice 'CASCADE  %.%', r.tbl, r.col;
      else
        execute format('alter table public.%I alter column %I drop not null', r.tbl, r.col);
        execute format(
          'alter table public.%I add constraint %I foreign key (%I)
             references auth.users(id) on delete set null',
          r.tbl, r.con, r.col);
        raise notice 'SET NULL %.%', r.tbl, r.col;
      end if;

    exception when others then
      -- a column that cannot be made nullable is left exactly as it was
      raise notice 'SKIPPED  %.%  (%)', r.tbl, r.col, sqlerrm;
    end;
  end loop;
end $$;


-- ---- 4. Anything still blocking? ---------------------------
--  Empty result = user deletion is now clear.

select
  tc.table_name   as still_blocking,
  kcu.column_name as blocking_column
from information_schema.table_constraints tc
join information_schema.key_column_usage kcu
  on kcu.constraint_name = tc.constraint_name
join information_schema.constraint_column_usage ccu
  on ccu.constraint_name = tc.constraint_name
join information_schema.referential_constraints rc
  on rc.constraint_name = tc.constraint_name
where tc.constraint_type = 'FOREIGN KEY'
  and ccu.table_name = 'users'
  and rc.delete_rule = 'NO ACTION'
order by tc.table_name;
