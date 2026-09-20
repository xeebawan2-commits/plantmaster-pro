#!/usr/bin/env node
/**
 * Edge function checks:
 *   1. every function the client invokes exists on disk
 *   2. no function is left behind that nothing calls
 *   3. each one type-checks
 *   4. each one is declared in supabase/config.toml with the right JWT setting
 *   5. no secret is hard-coded in a function
 */
import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join } from 'node:path';

const DIM='\x1b[2m', RED='\x1b[31m', GREEN='\x1b[32m', YELLOW='\x1b[33m', RESET='\x1b[0m';
const root = process.cwd();
const fnDir = join(root, 'supabase', 'functions');
const problems = [], warnings = [];

// ---- 1. what the client calls -------------------------------------------
const sources = [];
const walk = (dir) => {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    // 'reference' holds the owner's archived master package — read-only source
    // material, not shipping code. Scanning it would treat its edge-function
    // calls as requirements of this app.
    if (['node_modules','.git','public','dist','android','tools','reference'].includes(e.name)) continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p);
    else if (/\.(js|html|yml|yaml)$/.test(e.name)) sources.push(p);
  }
};
walk(root);

const invoked = new Set();
for (const f of sources) {
  const text = readFileSync(f, 'utf8');
  for (const m of text.matchAll(/functions\.invoke\(\s*['"`]([a-z0-9-]+)/g)) invoked.add(m[1]);
  for (const m of text.matchAll(/functions\/v1\/([a-z0-9-]+)/g)) invoked.add(m[1]);
}

const onDisk = existsSync(fnDir)
  ? readdirSync(fnDir).filter((d) => !d.startsWith('_') && statSync(join(fnDir, d)).isDirectory())
  : [];

console.log(`${DIM}── edge functions ──${RESET}`);
for (const name of [...invoked].sort()) {
  const entry = join(fnDir, name, 'index.ts');
  if (existsSync(entry)) console.log(`  ${GREEN}✓${RESET} ${name}`);
  else { console.log(`  ${RED}✗${RESET} ${name} — invoked by the app but missing`); problems.push(`missing function: ${name}`); }
}
for (const name of onDisk) {
  if (!invoked.has(name)) { console.log(`  ${YELLOW}!${RESET} ${name} — deployed but nothing calls it`); warnings.push(`orphan function: ${name}`); }
}

// ---- 2. type check -------------------------------------------------------
try {
  execFileSync('npx', ['tsc', '-p', 'tools/fn-check/tsconfig.json'], { cwd: root, stdio: 'pipe' });
  console.log(`  ${GREEN}✓${RESET} all functions type-check`);
} catch (e) {
  const out = (e.stdout?.toString() || '') + (e.stderr?.toString() || '');
  console.log(`  ${RED}✗${RESET} type errors:\n${out.split('\n').slice(0, 12).map((l) => '      ' + l).join('\n')}`);
  problems.push('edge functions do not type-check');
}

// ---- 3. config.toml ------------------------------------------------------
const cfgPath = join(root, 'supabase', 'config.toml');
if (!existsSync(cfgPath)) problems.push('supabase/config.toml is missing');
else {
  const cfg = readFileSync(cfgPath, 'utf8');
  for (const name of onDisk) {
    if (!cfg.includes(`[functions.${name}]`)) {
      console.log(`  ${RED}✗${RESET} ${name} is not declared in config.toml`);
      problems.push(`config.toml missing [functions.${name}]`);
    }
  }
  // The two scheduler-driven endpoints authenticate with their own shared
  // token, so they must NOT sit behind Supabase's JWT gate.
  for (const name of ['web-push', 'daily-reports']) {
    const block = cfg.split(`[functions.${name}]`)[1]?.split('[functions.')[0] ?? '';
    if (!/verify_jwt\s*=\s*false/.test(block)) {
      problems.push(`${name} must set verify_jwt = false (the scheduler has no user JWT)`);
    }
  }
  console.log(`  ${GREEN}✓${RESET} config.toml declares every function`);
}

// ---- 4. no hard-coded secrets -------------------------------------------
const secretish = [
  [/eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\./, 'a JWT'],
  [/AIza[0-9A-Za-z_-]{30,}/, 'a Google API key'],
  [/re_[0-9A-Za-z_-]{20,}/, 'a Resend key'],
  [/sb_secret_[0-9A-Za-z_-]{10,}/, 'a Supabase secret key'],
];
let clean = true;
const scan = (dir) => {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) { scan(p); continue; }
    if (!p.endsWith('.ts')) continue;
    const text = readFileSync(p, 'utf8');
    for (const [re, what] of secretish) {
      if (re.test(text)) { problems.push(`${p} contains ${what}`); clean = false; }
    }
  }
};
if (existsSync(fnDir)) scan(fnDir);
if (clean) console.log(`  ${GREEN}✓${RESET} no hard-coded secrets in function source`);

// ---- report --------------------------------------------------------------
console.log('');
if (warnings.length) for (const w of warnings) console.log(`${YELLOW}advisory:${RESET} ${w}`);
if (problems.length) {
  for (const p of problems) console.log(`${RED}blocking:${RESET} ${p}`);
  console.log(`\n${RED}${problems.length} blocking issue(s)${RESET}\n`);
  process.exit(1);
}
console.log(`${GREEN}EDGE FUNCTIONS OK${RESET}${warnings.length ? ` ${DIM}(${warnings.length} advisory)${RESET}` : ''}\n`);
