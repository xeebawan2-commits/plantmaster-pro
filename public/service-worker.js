/* PlantMaster Pro — service worker v4.49.0
 *
 * Fixes over v4.22.0:
 *  - The precache list used ?v= query strings. A cache hit requires an exact
 *    URL match by default, so every entry whose version tag drifted from
 *    index.html was dead weight and the app was not actually offline-capable.
 *    Entries are now unversioned and matched with {ignoreSearch:true}.
 *  - Navigation requests fall back to the cached shell so a cold start with no
 *    network opens the app instead of the browser's offline page.
 *  - Supabase REST/Realtime/Storage traffic is never touched.
 *  - Cache is capped so a long-lived install cannot grow without bound.
 */
const VERSION = '4.49.0-8a35dca7bed9';
const SHELL = `plantmaster-shell-v${VERSION}`;
const RUNTIME = `plantmaster-runtime-v${VERSION}`;
const MAX_RUNTIME_ENTRIES = 80;

/* Unversioned: requests are matched with ignoreSearch so ?v= tags still hit. */
const SHELL_ASSETS = [
  './',
  './index.html',
  './offline.html',
  './manifest.webmanifest',
  './styles.css',
  './ui-v4.5.css',
  './scanner-v4.8.css',
  './condition-v4.9.css',
  './solver-v4.11.css',
  './theme-pro.css',
  './app.js',
  './config.js',
  './offline.js',
  './operations.js',
  './procurement.js',
  './scanner.js',
  './condition.js',
  './solver.js',
  './analytics.js',
  './csv-import.js',
  './smart-select.js',
  './voice-input.js',
  './designation-options.js',
  './push-client.js',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/maskable-512.png',
  './favicon.ico',
];

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(SHELL);
    // Individually, so one 404 cannot fail the whole install.
    await Promise.all(SHELL_ASSETS.map(url =>
      cache.add(new Request(url, { cache: 'reload' })).catch(() => null)));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys
      .filter(k => k !== SHELL && k !== RUNTIME)
      .map(k => caches.delete(k)));
    if (self.registration.navigationPreload) {
      await self.registration.navigationPreload.enable().catch(() => {});
    }
    await self.clients.claim();
  })());
});

/** Let the page trigger an immediate update. */
self.addEventListener('message', event => {
  if (event.data === 'SKIP_WAITING') self.skipWaiting();
});

async function trimCache(name, max) {
  const cache = await caches.open(name);
  const keys = await cache.keys();
  if (keys.length <= max) return;
  await Promise.all(keys.slice(0, keys.length - max).map(k => cache.delete(k)));
}

const isSupabase = url =>
  url.hostname.endsWith('.supabase.co') || url.hostname.endsWith('.supabase.in');

/* app.js and styles.css are always fetched fresh: a stale copy silently undoes
   every deployment, which is how a password-reset fix got stranded once. */
const isAlwaysFresh = url => /\/(app\.js|styles\.css)$/.test(url.pathname);

self.addEventListener('fetch', event => {
  const { request } = event;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);

  // Never intercept the API, auth, realtime or storage.
  if (isSupabase(url)) return;
  // Only handle our own origin; CDN scripts go straight to the network.
  if (url.origin !== self.location.origin) return;

  // Single-page app: any navigation resolves to the cached shell offline.
  if (request.mode === 'navigate') {
    event.respondWith((async () => {
      try {
        const preload = await event.preloadResponse;
        if (preload) return preload;
        return await fetch(request);
      } catch (_) {
        const cache = await caches.open(SHELL);
        return (await cache.match('./index.html', { ignoreSearch: true }))
            || (await cache.match('./offline.html', { ignoreSearch: true }))
            || new Response('<h1>Offline</h1><p>Reconnect to continue.</p>',
                 { status: 503, headers: { 'Content-Type': 'text/html' } });
      }
    })());
    return;
  }

  if (isAlwaysFresh(url)) {
    event.respondWith((async () => {
      try {
        const fresh = await fetch(request, { cache: 'no-store' });
        if (fresh && fresh.ok) {
          const cache = await caches.open(SHELL);
          cache.put(request, fresh.clone()).catch(() => {});
        }
        return fresh;
      } catch (_) {
        const cached = await caches.match(request, { ignoreSearch: true });
        if (cached) return cached;
        throw new Error('offline and not cached');
      }
    })());
    return;
  }

  // Everything else: cache-first with a background refresh.
  event.respondWith((async () => {
    const cached = await caches.match(request, { ignoreSearch: true });
    if (cached) {
      event.waitUntil((async () => {
        try {
          const fresh = await fetch(request);
          if (fresh && fresh.ok) {
            const cache = await caches.open(RUNTIME);
            await cache.put(request, fresh.clone());
            await trimCache(RUNTIME, MAX_RUNTIME_ENTRIES);
          }
        } catch (_) { /* offline: keep the cached copy */ }
      })());
      return cached;
    }
    try {
      const fresh = await fetch(request);
      if (fresh && fresh.ok && fresh.type === 'basic') {
        const cache = await caches.open(RUNTIME);
        await cache.put(request, fresh.clone());
        await trimCache(RUNTIME, MAX_RUNTIME_ENTRIES);
      }
      return fresh;
    } catch (err) {
      const shell = await caches.open(SHELL);
      const fallback = await shell.match('./index.html', { ignoreSearch: true });
      if (fallback && request.destination === 'document') return fallback;
      throw err;
    }
  })());
});

/* ---------------------------------------------------------------- Web Push */
self.addEventListener('push', event => {
  let d = {};
  try { d = event.data ? event.data.json() : {}; }
  catch (_) { d = { body: event.data && event.data.text() }; }

  const title = d.title || 'PlantMaster Pro';
  const body = d.body || '';
  const options = {
    body,
    icon: 'icons/icon-192.png',
    badge: 'icons/maskable-512.png',
    tag: d.tag || 'pmpro-default',
    renotify: !!d.body,
    requireInteraction: d.severity === 'high' || d.tag === 'alarm',
    timestamp: Date.now(),
    data: { route: d.route || '/notifications', org_id: d.org_id || '' },
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', event => {
  event.notification.close();
  const route = ((event.notification.data && event.notification.data.route) || '')
    .replace(/^\//, '');
  const target = new URL(self.location.origin + '/');
  if (route) target.searchParams.set('pmroute', route);
  const url = target.toString();

  event.waitUntil((async () => {
    const list = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const client of list) {
      try {
        await client.focus();
        if ('navigate' in client) await client.navigate(url);
        return;
      } catch (_) { /* try the next client */ }
    }
    await self.clients.openWindow(url);
  })());
});
