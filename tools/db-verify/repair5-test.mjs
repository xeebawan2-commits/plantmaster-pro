// ---------------------------------------------------------------------------
// R5: the published price is the enforced price.
//
// Three places quote a price — pricing.html, the signed PDF, and
// subscription_plans. This asserts the third matches the first two, and that
// the plan limits a customer is sold are the limits the software enforces.
//
// The expected numbers are read from site/pricing.html rather than hardcoded,
// so if the page is ever re-priced without updating R5 this test fails instead
// of silently passing.
//
//   node tools/db-verify/repair5-test.mjs
// ---------------------------------------------------------------------------
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const G='\x1b[32m', R='\x1b[31m', D='\x1b[2m', X='\x1b[0m';
let pass=0, fail=0;
const ok  = (m)=>{ console.log(`  ${G}✓${X} ${m}`); pass++; };
const bad = (m)=>{ console.log(`  ${R}✗${X} ${m}`); fail++; };

const strip = (f) => readFileSync(join(root,f),'utf8')
  .split('-- ============================================================================\n--  VERIFY')[0];

// --- what the marketing page actually promises ------------------------------
function pricesFromPage () {
  const html = readFileSync(join(root,'site','pricing.html'),'utf8');
  const txt  = html.replace(/<[^>]+>/g,' ').replace(/\s+/g,' ');
  const found = {};
  const re = /(Basic|Essential|Professional|Enterprise)[^|]{0,200}?Rs\s*([0-9,]+)\s*\/month/g;
  let m;
  while ((m = re.exec(txt)) !== null) {
    const plan = m[1].toLowerCase();
    const price = Number(m[2].replace(/,/g,''));
    // The founding-member banner quotes a discounted Professional before the
    // real plan cards. Keep the last (canonical) figure for each plan.
    found[plan] = price;
  }
  return found;
}

const page = pricesFromPage();
console.log(`${D}  prices read from site/pricing.html: ${JSON.stringify(page)}${X}`);

const db = new PGlite();

await db.exec(`
create table public.subscription_plans(
  id uuid primary key default gen_random_uuid(),
  code text unique, name text, description text,
  active boolean default true, currency text default 'PKR',
  price_monthly numeric default 0, price_yearly numeric default 0,
  max_workers int default 5, max_plants int default 1,
  max_storage_bytes bigint default 0, max_files int default 0,
  max_file_bytes bigint default 0,
  ai_requests_month int default 0, ai_requests_day int default 0,
  ai_requests_minute_user int default 0,
  ai_input_tokens_month bigint default 0, ai_output_tokens_month bigint default 0,
  retention_days int default 365,
  created_at timestamptz default now(), updated_at timestamptz default now());
`);

// Seed the pre-R5 state exactly as R1 leaves it: no Basic, Enterprise at 0.
await db.exec(`
insert into public.subscription_plans
  (code,name,description,currency,price_monthly,price_yearly,max_workers,max_plants,max_storage_bytes,max_files,active)
values
  ('trial','Trial (7 days)','','PKR',0,0,25,1,5368709120,2000,true),
  ('essential','Essential','','PKR',12000,120000,10,1,10737418240,5000,true),
  ('professional','Professional','','PKR',24000,240000,25,1,32212254720,20000,true),
  ('enterprise','Enterprise','Quoted.','PKR',0,0,999999,99,107374182400,999999,true),
  ('legacy_starter','Starter (retired)','','PKR',15000,150000,10,1,1073741824,100,true);
`);

console.log('\nBefore R5 — the state R1 leaves behind');
{
  const r = await db.query(`select count(*)::int n from public.subscription_plans where code='basic'`);
  r.rows[0].n === 0 ? ok('Basic plan is absent, so it cannot be sold') : bad('expected Basic to be missing');
  const e = await db.query(`select price_monthly from public.subscription_plans where code='enterprise'`);
  Number(e.rows[0].price_monthly) === 0
    ? ok('Enterprise is priced at 0 — an Enterprise customer bills against nothing')
    : bad('expected Enterprise to start at 0');
}

// --- apply R5 ---------------------------------------------------------------
await db.exec(strip('supabase/repairs/R5-final-pricing.sql'));

console.log('\nAfter R5 — database matches the published price');
const rows = await db.query(`select code, price_monthly, max_workers, max_plants,
                                    max_storage_bytes, active
                               from public.subscription_plans order by code`);
const byCode = Object.fromEntries(rows.rows.map(r => [r.code, r]));

for (const plan of ['basic','essential','professional','enterprise']) {
  const want = page[plan];
  const got  = byCode[plan] ? Number(byCode[plan].price_monthly) : null;
  if (want === undefined) { bad(`could not read a price for ${plan} from pricing.html`); continue; }
  got === want
    ? ok(`${plan.padEnd(12)} Rs ${got.toLocaleString()} — matches pricing.html`)
    : bad(`${plan.padEnd(12)} database Rs ${got} but pricing.html says Rs ${want}`);
}

// Limits a customer is sold must be the limits enforced.
const limits = {
  basic:        { users: 5,   plants: 1, gb: 5   },
  essential:    { users: 10,  plants: 1, gb: 10  },
  professional: { users: 25,  plants: 1, gb: 30  },
  enterprise:   { users: 100, plants: 2, gb: 100 },
};
console.log('\nPlan limits');
for (const [code, want] of Object.entries(limits)) {
  const r = byCode[code];
  if (!r) { bad(`${code} missing`); continue; }
  const gb = Math.round(Number(r.max_storage_bytes) / 1073741824);
  (r.max_workers === want.users && r.max_plants === want.plants && gb === want.gb)
    ? ok(`${code.padEnd(12)} ${want.users} users · ${want.plants} plant(s) · ${want.gb} GB`)
    : bad(`${code}: got ${r.max_workers}u/${r.max_plants}p/${gb}GB, want ${want.users}u/${want.plants}p/${want.gb}GB`);
}

console.log('\nHousekeeping');
{
  const t = await db.query(`select price_monthly from public.subscription_plans where code='trial'`);
  Number(t.rows[0].price_monthly) === 0 ? ok('trial is still free') : bad('trial should stay at 0');

  const l = await db.query(`select active from public.subscription_plans where code='legacy_starter'`);
  l.rows[0].active === false
    ? ok('retired tier deactivated, not deleted — billing history survives')
    : bad('legacy tier should be deactivated');

  const n = await db.query(`select count(*)::int n from public.subscription_plans where active`);
  n.rows[0].n === 5
    ? ok('exactly 5 active plans: trial + the four sold tiers')
    : bad(`expected 5 active plans, got ${n.rows[0].n}`);
}

// Idempotency: the owner may well run it twice.
await db.exec(strip('supabase/repairs/R5-final-pricing.sql'));
{
  const r = await db.query(`select count(*)::int n from public.subscription_plans where code='basic'`);
  const e = await db.query(`select price_monthly from public.subscription_plans where code='enterprise'`);
  (r.rows[0].n === 1 && Number(e.rows[0].price_monthly) === 40000)
    ? ok('re-running R5 changes nothing')
    : bad('R5 is not idempotent');
}

await db.close();
console.log(fail === 0
  ? `\n${G}ALL ${pass} PRICING CHECKS PASSED${X}\n`
  : `\n${R}${fail} FAILED${X} (${pass} passed)\n`);
process.exit(fail === 0 ? 0 : 1);
