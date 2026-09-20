#!/usr/bin/env node
/**
 * PlantMaster Pro — database verification harness.
 *
 * Boots a real PostgreSQL 18 (PGlite/WASM), applies the Supabase shim and then
 * every migration in supabase/migrations in order. Then it runs the assertion
 * suite in tools/db-verify/tests.mjs, which exercises the RLS policies as
 * actual tenant users.
 *
 *   node tools/db-verify/verify.mjs          # migrate + test
 *   node tools/db-verify/verify.mjs --schema # also dump the resulting schema
 */
import { PGlite } from '@electric-sql/pglite';
import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';

const here = path.dirname(url.fileURLToPath(import.meta.url));
const repo = path.resolve(here, '..', '..');
const migrationsDir = path.join(repo, 'supabase', 'migrations');

const GREEN = '\x1b[32m', RED = '\x1b[31m', DIM = '\x1b[2m', YEL = '\x1b[33m', RESET = '\x1b[0m';

export async function boot({ quiet = false } = {}) {
  const db = await PGlite.create();
  const log = (...a) => { if (!quiet) console.log(...a); };

  await db.exec(fs.readFileSync(path.join(here, 'shim.sql'), 'utf8'));
  log(`${DIM}shim applied (auth/storage schemas, supabase roles)${RESET}`);

  const files = fs.readdirSync(migrationsDir).filter(f => f.endsWith('.sql')).sort();
  if (!files.length) throw new Error('no migrations found');

  for (const f of files) {
    const sql = fs.readFileSync(path.join(migrationsDir, f), 'utf8');
    try {
      await db.exec(sql);
      log(`${GREEN}  ok${RESET}  ${f}`);
    } catch (e) {
      console.error(`${RED}FAIL${RESET}  ${f}\n      ${e.message}`);
      if (e.position && sql) {
        const line = sql.slice(0, Number(e.position)).split('\n').length;
        console.error(`${DIM}      at line ${line}: ${sql.split('\n')[line - 1]?.trim()}${RESET}`);
      }
      if (e.detail) console.error(`${DIM}      detail: ${e.detail}${RESET}`);
      if (e.hint) console.error(`${DIM}      hint: ${e.hint}${RESET}`);
      // A Postgres error object stringifies to the whole failing script; the
      // fields above are the useful part.
      const clean = new Error(`${f}: ${e.message}`);
      clean.stack = clean.message;
      throw clean;
    }
  }
  return db;
}

/** Applying the suite twice must be a no-op — proves idempotency. */
export async function verifyIdempotent(db) {
  const files = fs.readdirSync(migrationsDir).filter(f => f.endsWith('.sql')).sort();
  for (const f of files) {
    await db.exec(fs.readFileSync(path.join(migrationsDir, f), 'utf8'));
  }
}

async function main() {
  console.log(`\n${DIM}── applying migrations ──${RESET}`);
  const db = await boot();

  console.log(`\n${DIM}── re-applying (idempotency) ──${RESET}`);
  await verifyIdempotent(db);
  console.log(`${GREEN}  ok${RESET}  suite is idempotent`);

  // ---- structural report ---------------------------------------------------
  const tables = await db.query(`
    select c.relname,
           c.relrowsecurity as rls,
           (select count(*) from pg_policies p
             where p.schemaname='public' and p.tablename=c.relname) as policies
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r'
    order by c.relname`);

  const noRls = tables.rows.filter(t => !t.rls);
  const noPolicy = tables.rows.filter(t => t.rls && Number(t.policies) === 0);

  console.log(`\n${DIM}── structure ──${RESET}`);
  console.log(`  tables:    ${tables.rows.length}`);
  const fns = await db.query(`
    select count(*)::int n from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
    where ns.nspname='public'`);
  console.log(`  functions: ${fns.rows[0].n}`);
  const pol = await db.query(`select count(*)::int n from pg_policies where schemaname='public'`);
  console.log(`  policies:  ${pol.rows[0].n}`);
  const idx = await db.query(`select count(*)::int n from pg_indexes where schemaname='public'`);
  console.log(`  indexes:   ${idx.rows[0].n}`);

  let bad = false;
  if (noRls.length) {
    console.log(`${RED}  tables WITHOUT RLS: ${noRls.map(t => t.relname).join(', ')}${RESET}`);
    bad = true;
  } else console.log(`${GREEN}  every table has RLS enabled${RESET}`);

  if (noPolicy.length) {
    console.log(`${YEL}  RLS on but NO policy (deny-all): ${noPolicy.map(t => t.relname).join(', ')}${RESET}`);
  }

  // SECURITY DEFINER functions must pin search_path.
  const sd = await db.query(`
    select p.proname, p.proconfig
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prosecdef
    order by p.proname`);
  const unpinned = sd.rows.filter(r =>
    !(r.proconfig || []).some(c => String(c).startsWith('search_path=')));
  if (unpinned.length) {
    console.log(`${RED}  SECURITY DEFINER without search_path: ${unpinned.map(r => r.proname).join(', ')}${RESET}`);
    bad = true;
  } else {
    console.log(`${GREEN}  all ${sd.rows.length} SECURITY DEFINER functions pin search_path${RESET}`);
  }

  if (process.argv.includes('--schema')) {
    console.log(`\n${DIM}── tables ──${RESET}`);
    for (const t of tables.rows) {
      console.log(`  ${t.relname.padEnd(34)} rls=${t.rls ? 'on ' : 'OFF'} policies=${t.policies}`);
    }
  }

  // ---- behavioural tests ---------------------------------------------------
  const { runTests } = await import('./tests.mjs');
  const failures = await runTests(db);

  if (failures || bad) {
    console.log(`\n${RED}VERIFICATION FAILED${RESET}\n`);
    process.exit(1);
  }
  console.log(`\n${GREEN}ALL CHECKS PASSED${RESET}\n`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch(e => { console.error(e); process.exit(1); });
}
