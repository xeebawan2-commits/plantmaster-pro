-- ============================================================
--  PlantMaster — give the super admin real delete power
--  HSB Fix Services
--
--  Paste the whole file, Run. Safe to run more than once.
-- ============================================================
--
--  FIRST, THE HONEST ANSWER TO YOUR QUESTION
--
--  You are not being blocked by permissions. You already have
--  every permission. You are being blocked by wiring.
--
--  Postgres refuses to delete a row while another row still
--  points at it. Delete a company -> it must delete its assets
--  -> but "technical_experiences" still points at those assets
--  -> so the whole thing stops.
--
--  It is the same reason you cannot pull out the bottom book
--  in a stack. Not a rule about who you are. A rule about what
--  is resting on what.
--
--  The real fix is to tell each link what to do when its parent
--  disappears. That is what this script does, for every link at
--  once, instead of one error at a time.
-- ============================================================


-- ---- 1. Audit log: stop it blocking anything ---------------
--  Your audit trigger says these records are append-only:
--  they may never be changed or deleted. Good rule. Keep it.
--
--  But the earlier script told the database to blank the
--  company column when a company is deleted -- and blanking IS
--  a change, so the trigger refused. That is why you still saw
--  "Administrator audit records are append-only".
--
--  Fix: remove the LINK, keep the DATA. The log still records
--  which company an action belonged to, it just no longer
--  demands that the company still exist. Nothing is touched
--  when a company or a user is deleted, so nothing is blocked.

do $$
declare r record;
begin
  for r in
    select conname
    from pg_constraint
    where conrelid = 'public.admin_action_logs'::regclass
      and contype  = 'f'
  loop
    execute format('alter table public.admin_action_logs drop constraint %I', r.conname);
    raise notice 'audit log unlinked: %', r.conname;
  end loop;
end $$;


-- ---- 2. Every remaining link, fixed in one pass ------------
--  Rule used: if the thing being pointed at belongs to a
--  company (it has an organization_id), then its children
--  should disappear with it. That is what CASCADE means.
--
--  Price lists, legal documents and other shared reference
--  tables have no organization_id, so they are left alone.
--  Deleting one customer can never wipe a shared list.

do $$
declare
  r record;
  fixed int := 0;
  failed int := 0;
begin
  for r in
    select
      tc.constraint_name as con,
      tc.table_name      as child,
      kcu.column_name    as child_col,
      ccu.table_name     as parent
    from information_schema.table_constraints tc
    join information_schema.key_column_usage kcu
      on kcu.constraint_name = tc.constraint_name
     and kcu.table_schema    = tc.table_schema
    join information_schema.constraint_column_usage ccu
      on ccu.constraint_name = tc.constraint_name
    join information_schema.referential_constraints rc
      on rc.constraint_name  = tc.constraint_name
    where tc.constraint_type = 'FOREIGN KEY'
      and tc.table_schema    = 'public'
      and rc.delete_rule in ('NO ACTION','RESTRICT')
      and (
            ccu.table_name = 'organizations'
            or exists (
              select 1 from information_schema.columns c
              where c.table_schema = 'public'
                and c.table_name   = ccu.table_name
                and c.column_name  = 'organization_id'
            )
          )
      and tc.table_name <> 'admin_action_logs'
  loop
    begin
      execute format('alter table public.%I drop constraint %I', r.child, r.con);
      execute format(
        'alter table public.%I add constraint %I foreign key (%I)
           references public.%I(id) on delete cascade',
        r.child, r.con, r.child_col, r.parent);
      fixed := fixed + 1;
      raise notice 'CASCADE  %.% -> %', r.child, r.child_col, r.parent;
    exception when others then
      failed := failed + 1;
      raise notice 'SKIPPED  %.% (%)', r.child, r.child_col, sqlerrm;
    end;
  end loop;

  raise notice '--- % links fixed, % skipped ---', fixed, failed;
end $$;


-- ---- 3. Anything still able to block a company delete ------
--  Empty result = you can now delete any company.

select
  tc.table_name   as still_blocking,
  kcu.column_name as blocking_column,
  ccu.table_name  as points_at
from information_schema.table_constraints tc
join information_schema.key_column_usage kcu
  on kcu.constraint_name = tc.constraint_name
join information_schema.constraint_column_usage ccu
  on ccu.constraint_name = tc.constraint_name
join information_schema.referential_constraints rc
  on rc.constraint_name = tc.constraint_name
where tc.constraint_type = 'FOREIGN KEY'
  and tc.table_schema = 'public'
  and rc.delete_rule in ('NO ACTION','RESTRICT')
  and (
        ccu.table_name = 'organizations'
        or exists (
          select 1 from information_schema.columns c
          where c.table_schema = 'public'
            and c.table_name   = ccu.table_name
            and c.column_name  = 'organization_id'
        )
      )
order by tc.table_name;


-- ---- 4. Any other guard that could still say no ------------
--  Lists triggers that can refuse a change. Expected: the
--  audit append-only one. It no longer gets in your way,
--  because nothing touches the audit log any more.

select
  c.relname  as on_table,
  t.tgname   as trigger_name,
  p.proname  as runs_function
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_proc  p on p.oid = t.tgfoid
join pg_namespace n on n.oid = c.relnamespace
where not t.tgisinternal
  and n.nspname = 'public'
  and pg_get_functiondef(p.oid) ilike '%raise exception%'
order by c.relname, t.tgname;
