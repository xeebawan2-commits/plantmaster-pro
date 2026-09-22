#!/usr/bin/env node
/**
 * PlantMaster Pro — deployment build.
 *
 * The repository previously kept a hand-maintained duplicate of every asset in
 * public/. It had drifted: seven files index.html requires (designation-options.js,
 * ui-v4.5.css, condition-v4.9.css, manifest.webmanifest, favicon.ico,
 * favicon-32.png, apple-touch-icon.png) were missing, so a Cloudflare deploy
 * served a broken app. public/ is now generated and git-ignored.
 *
 *   node scripts/build.mjs            # build app  -> public/
 *   node scripts/build.mjs --site     # build site -> dist/site
 *   node scripts/build.mjs --admin    # build admin-> dist/admin
 *   node scripts/build.mjs --all
 */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import url from 'node:url';

const repo = path.resolve(path.dirname(url.fileURLToPath(import.meta.url)), '..');
const OUT = path.join(repo, 'public');

const APP_FILES = [
  'index.html', 'offline.html', 'manifest.webmanifest', 'service-worker.js',
  'app.js', 'config.js', 'offline.js', 'operations.js', 'procurement.js',
  'scanner.js', 'condition.js', 'solver.js', 'analytics.js', 'csv-import.js',
  'smart-select.js', 'voice-input.js', 'designation-options.js', 'push-client.js',
  'styles.css', 'ui-v4.5.css', 'scanner-v4.8.css', 'condition-v4.9.css',
  'solver-v4.11.css', 'theme-pro.css',
  'favicon.ico', 'favicon-32.png', 'apple-touch-icon.png',
  '_headers', '_redirects', 'robots.txt',
];
const APP_DIRS = ['icons', 'screenshots', '.well-known'];

const rm = p => fs.rmSync(p, { recursive: true, force: true });
const ensure = p => fs.mkdirSync(p, { recursive: true });

function copyDir(from, to) {
  if (!fs.existsSync(from)) return 0;
  ensure(to);
  let n = 0;
  for (const entry of fs.readdirSync(from, { withFileTypes: true })) {
    const s = path.join(from, entry.name), d = path.join(to, entry.name);
    if (entry.isDirectory()) n += copyDir(s, d);
    else { fs.copyFileSync(s, d); n++; }
  }
  return n;
}

function buildApp() {
  rm(OUT); ensure(OUT);
  let copied = 0, missing = [];

  for (const f of APP_FILES) {
    const src = path.join(repo, f);
    if (!fs.existsSync(src)) { missing.push(f); continue; }
    fs.copyFileSync(src, path.join(OUT, f));
    copied++;
  }
  for (const d of APP_DIRS) copied += copyDir(path.join(repo, d), path.join(OUT, d));

  // Cache-bust: stamp every local asset reference in index.html with a hash of
  // the file it points at, so a deploy can never serve a stale mix.
  const indexPath = path.join(OUT, 'index.html');
  if (fs.existsSync(indexPath)) {
    let html = fs.readFileSync(indexPath, 'utf8');
    html = html.replace(/(src|href)="([^"]+?)(\?v=[^"]*)?"/g, (m, attr, file) => {
      if (/^(https?:|data:|mailto:|tel:|#|\/\/)/.test(file)) return m;
      const clean = file.replace(/^\.\//, '');
      const target = path.join(OUT, clean);
      if (!fs.existsSync(target)) return `${attr}="${file}"`;
      const hash = crypto.createHash('sha256')
        .update(fs.readFileSync(target)).digest('hex').slice(0, 10);
      return `${attr}="${file}?v=${hash}"`;
    });
    fs.writeFileSync(indexPath, html);
  }

  // Keep the service worker's cache name tied to real content, so shipping any
  // change guarantees clients drop the old cache.
  const swPath = path.join(OUT, 'service-worker.js');
  if (fs.existsSync(swPath)) {
    const fingerprint = crypto.createHash('sha256');
    for (const f of fs.readdirSync(OUT).sort()) {
      const p = path.join(OUT, f);
      if (fs.statSync(p).isFile()) fingerprint.update(fs.readFileSync(p));
    }
    const build = fingerprint.digest('hex').slice(0, 12);
    let sw = fs.readFileSync(swPath, 'utf8')
      .replace(/const VERSION = '[^']+';/, `const VERSION = '4.49.0-${build}';`);
    fs.writeFileSync(swPath, sw);
  }

  console.log(`app   -> public/            ${copied} files`);
  if (missing.length) console.log(`        (optional, absent: ${missing.join(', ')})`);
  return missing;
}

/** Shared assets both the site and the admin console reference from /. */
const SHARED = ['favicon.ico', 'favicon-32.png', 'apple-touch-icon.png'];

function buildStatic(name) {
  const from = path.join(repo, name);
  const to = path.join(repo, 'dist', name);
  if (!fs.existsSync(from)) { console.log(`${name} -> skipped (no ${name}/ directory)`); return; }
  rm(to);
  let n = copyDir(from, to);

  // Both properties use the app's icon set and favicons.
  n += copyDir(path.join(repo, 'icons'), path.join(to, 'icons'));
  for (const f of SHARED) {
    const src = path.join(repo, f);
    if (fs.existsSync(src)) { fs.copyFileSync(src, path.join(to, f)); n++; }
  }

  // The admin console imports ./config.js. It needs CUSTOMER_APP_URL and
  // WHATSAPP_NUMBER, which the app's root config.js does not export, so the
  // console ships its own. Only fall back to the root one if it is absent.
  if (name === 'admin') {
    if (!fs.existsSync(path.join(from, 'config.js'))) {
      fs.copyFileSync(path.join(repo, 'config.js'), path.join(to, 'config.js'));
      n++;
    }
    fs.writeFileSync(path.join(to, 'robots.txt'), 'User-agent: *\nDisallow: /\n');
    fs.writeFileSync(path.join(to, '_headers'), [
      '/*',
      '  X-Robots-Tag: noindex, nofollow',
      '  X-Frame-Options: DENY',
      '  X-Content-Type-Options: nosniff',
      '  Referrer-Policy: no-referrer',
      '  Strict-Transport-Security: max-age=31536000; includeSubDomains; preload',
      "  Content-Security-Policy: default-src 'self'; script-src 'self' https://cdn.jsdelivr.net;" +
        " style-src 'self' 'unsafe-inline'; img-src 'self' data:;" +
        " connect-src 'self' https://*.supabase.co wss://*.supabase.co;" +
        " frame-ancestors 'none'; base-uri 'self'; form-action 'self'",
      '',
    ].join('\n'));
    fs.writeFileSync(path.join(to, '_redirects'), '/*    /index.html   200\n');
    n += 3;
  }

  if (name === 'site') {
    fs.writeFileSync(path.join(to, '_headers'), [
      '/*',
      '  X-Content-Type-Options: nosniff',
      '  X-Frame-Options: SAMEORIGIN',
      '  Referrer-Policy: strict-origin-when-cross-origin',
      '  Strict-Transport-Security: max-age=31536000; includeSubDomains; preload',
      '',
      '/.well-known/assetlinks.json',
      '  Content-Type: application/json',
      '  Access-Control-Allow-Origin: *',
      '',
    ].join('\n'));
    const sitemapUrls = fs.readdirSync(from)
      .filter(f => f.endsWith('.html'))
      .map(f => `  <url><loc>https://hsbfix.org/${f === 'index.html' ? '' : f}</loc></url>`)
      .join('\n');
    fs.writeFileSync(path.join(to, 'sitemap.xml'),
      `<?xml version="1.0" encoding="UTF-8"?>\n` +
      `<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${sitemapUrls}\n</urlset>\n`);
    fs.writeFileSync(path.join(to, 'robots.txt'),
      'User-agent: *\nAllow: /\n\nSitemap: https://hsbfix.org/sitemap.xml\n');
    n += 3;
  }

  console.log(`${name.padEnd(5)} -> dist/${name}${' '.repeat(Math.max(0, 12 - name.length))} ${n} files`);
}

const args = process.argv.slice(2);
const all = args.includes('--all') || args.length === 0;
if (all || args.includes('--app')) buildApp();
if (all || args.includes('--site')) buildStatic('site');
if (all || args.includes('--admin')) buildStatic('admin');

// --workers: prepare the same outputs for Cloudflare *Workers* static assets
// rather than Pages.
//
// Workers reads _headers and _redirects natively, with one exception: the
// Pages SPA catch-all "/* /index.html 200" is not how Workers expresses a SPA
// fallback. Left in place the deploy fails outright with "infinite loop
// detected" (code 100324). On Workers the equivalent is
// assets.not_found_handling = "single-page-application", which is set in
// wrangler.app.jsonc and wrangler.admin.jsonc.
//
// So strip only that one line, keep every other rule, and delete the file if
// nothing else remains.
if (args.includes('--workers')) {
  const targets = [
    path.join(repo, 'public'),
    path.join(repo, 'dist', 'site'),
    path.join(repo, 'dist', 'admin'),
  ];
  const isSpaCatchAll = line => /^\/\*\s+\/index\.html\s+200\b/.test(line.trim());

  for (const dir of targets) {
    const f = path.join(dir, '_redirects');
    if (!fs.existsSync(f)) continue;

    const before = fs.readFileSync(f, 'utf8');
    const kept = before.split('\n').filter(l => !isSpaCatchAll(l));
    const meaningful = kept.filter(l => l.trim() && !l.trim().startsWith('#'));

    if (meaningful.length === 0) {
      fs.rmSync(f);
      console.log(`workers: removed ${path.relative(repo, f)} (SPA fallback is in wrangler config)`);
    } else if (kept.join('\n') !== before) {
      fs.writeFileSync(f, kept.join('\n'));
      console.log(`workers: stripped SPA catch-all from ${path.relative(repo, f)}`);
    }
  }
}
