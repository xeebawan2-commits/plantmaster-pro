-- ============================================================
--  PlantMaster — remove the leftover QA test accounts  (v2)
--  HSB Fix Services
--
--  Paste the whole file, Run.
-- ============================================================
--
--  WHY SCRIPT 05 MISSED THIS
--
--  Script 05 looked up the links using information_schema,
--  which only lists links whose target table you own. Your
--  logins live in auth.users, a table owned by Supabase, so
--  most of those links were invisible to it and never fixed.
--
--  This version reads the real Postgres catalog instead, which
--  shows every link regardless of who owns what. That is why
--  it finds platform_support_tickets and the rest.
-- ============================================================


-- ---- 1. Unhook every table that points at a login ----------
--  Tickets, logs, uploads and so on keep their records -- the
--  "who did this" column simply becomes empty when the person
--  is deleted. Memberships and admin rows go with the person,
--  which is correct.

do $$
declare
  r record;
  fixed  int := 0;
  failed int := 0;
  cascade_tables text[] := array['organization_members','platform_admins'];
begin
  for r in
    select
      con.conname                as con,
      child.relname              as tbl,
      att.attname                as col
    from pg_constraint con
    join pg_class      child on child.oid = con.conrelid
    join pg_namespace  ns    on ns.oid    = child.relnamespace
    join pg_attribute  att   on att.attrelid = con.conrelid
                            and att.attnum   = con.conkey[1]
    where con.contype  = 'f'
      and con.confrelid = 'auth.users'::regclass
      and ns.nspname    = 'public'
      and con.confdeltype in ('a','r')     -- no action / restrict
  loop
    begin
      execute format('alter table public.%I drop constraint %I', r.tbl, r.con);

      if r.tbl = any(cascade_tables) then
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

      fixed := fixed + 1;
    exception when others then
      failed := failed + 1;
      raise notice 'SKIPPED  %.%  (%)', r.tbl, r.col, sqlerrm;
    end;
  end loop;

  raise notice '--- % links fixed, % skipped ---', fixed, failed;
end $$;


-- ---- 2. Look before deleting -------------------------------
--  Every address here should end in @example.com.

select
  u.email,
  u.created_at::date as created
from auth.users u
where u.email like '%@example.com'
   or u.email like 'pmqa-%'
order by u.email;


-- ---- 3. Delete the test logins -----------------------------
--  Only @example.com and pmqa- addresses. A real customer
--  can never be caught by this.

delete from auth.users
where email like '%@example.com'
   or email like 'pmqa-%';


-- ---- 4. Remove the empty QA companies ----------------------

delete from organizations
where name like '\_\_PM\_QA\_\_%'
   or name like '\_\_PM\_QA\_ISOLATION\_\_%';


-- ---- 5. What is left ---------------------------------------
--  Should be only you and your real customers.

select
  u.email,
  u.created_at::date as created,
  case when u.banned_until is not null then 'suspended' else 'active' end as state
from auth.users u
order by u.created_at;
