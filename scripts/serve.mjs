#!/usr/bin/env node
/** Local preview: serves the app, marketing site and admin console together. */
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const ROOTS = { 8080: 'public', 8081: 'dist/site', 8082: 'dist/admin' };
const TYPES = {
  '.html':'text/html; charset=utf-8', '.js':'text/javascript; charset=utf-8',
  '.mjs':'text/javascript; charset=utf-8', '.css':'text/css; charset=utf-8',
  '.json':'application/json', '.webmanifest':'application/manifest+json',
  '.png':'image/png', '.jpg':'image/jpeg', '.svg':'image/svg+xml',
  '.ico':'image/x-icon', '.txt':'text/plain; charset=utf-8', '.xml':'application/xml',
};

for (const [port, root] of Object.entries(ROOTS)) {
  const base = path.resolve(root);
  http.createServer((req, res) => {
    const url = decodeURIComponent(req.url.split('?')[0]);
    let file = path.join(base, url);
    if (url.endsWith('/')) file = path.join(file, 'index.html');
    if (!file.startsWith(base)) { res.writeHead(403).end('forbidden'); return; }
    if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      file = path.join(base, 'index.html');   // SPA fallback
    }
    if (!fs.existsSync(file)) { res.writeHead(404).end('not found'); return; }
    res.writeHead(200, {
      'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream',
      'Cache-Control': 'no-store',
      'Service-Worker-Allowed': '/',
    });
    fs.createReadStream(file).pipe(res);
  }).listen(Number(port), '0.0.0.0', () => console.log(`${root} -> http://0.0.0.0:${port}`));
}
