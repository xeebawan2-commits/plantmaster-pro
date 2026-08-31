/* PlantMaster Pro — service worker v4.12.0
 * = v4.11.1 base (versioned precache, offline shell, Supabase passthrough)
 * + Web Push handlers (push + notificationclick).
 * New cache name => old caches are cleaned on activate; app.js registers
 * this file with ?v=4.12.0 so browsers pick it up immediately.
 */
const C='plantmaster-pro-v4.12.0';
const F=['./','./index.html','./styles.css?v=4.11.1','./ui-v4.5.css?v=4.11.1','./scanner-v4.8.css?v=4.11.1','./condition-v4.9.css?v=4.11.1','./solver-v4.11.css?v=4.11.1','./theme-pro.css?v=1.0.0','./app.js?v=4.11.1','./scanner.js?v=4.11.1','./condition.js?v=4.11.1','./solver.js?v=4.11.1','./config.js?v=4.3.1','./offline.js?v=4.11.1','./operations.js?v=4.11.1','./manifest.webmanifest','./icons/icon-192.png','./icons/icon-512.png','./icons/maskable-512.png'];
self.addEventListener('install',e=>e.waitUntil(caches.open(C).then(c=>Promise.all(F.map(f=>c.add(f).catch(()=>null)))).then(()=>self.skipWaiting())));
self.addEventListener('activate',e=>e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!==C).map(x=>caches.delete(x)))).then(()=>self.clients.claim())));
self.addEventListener('fetch',e=>{if(e.request.method!=='GET'||new URL(e.request.url).hostname.endsWith('.supabase.co'))return;if(e.request.mode==='navigate')return e.respondWith(fetch(e.request,{cache:'no-store'}).catch(()=>caches.match('./index.html')));e.respondWith(caches.match(e.request).then(x=>x||fetch(e.request).then(r=>{if(r.ok)caches.open(C).then(c=>c.put(e.request,r.clone()));return r})))});
/* ---------- Web Push ---------- */
self.addEventListener('push',e=>{
  let d={};
  try{d=e.data?e.data.json():{}}catch(_){d={body:e.data&&e.data.text()}}
  const title=d.title||'PlantMaster Pro';
  const body=d.body||'';
  const opts={
    body,
    icon:'icons/icon-192.png',
    badge:'icons/maskable-512.png',
    tag:d.tag||'pmpro-default',
    renotify:!!d.body,
    requireInteraction:d.severity==='high'||d.tag==='alarm',
    data:{route:d.route||'/notifications',org_id:d.org_id||''}
  };
  e.waitUntil(self.registration.showNotification(title,opts));
});
self.addEventListener('notificationclick',e=>{
  e.notification.close();
  const route=(e.notification.data&&e.notification.data.route)||'/' ;
  const path=/^\//.test(route)?route:'/';
  e.waitUntil(
    self.clients.matchAll({type:'window',includeUncontrolled:true}).then(list=>{
      for(const c of list){try{c.navigate(new URL(path,self.location.origin).toString());c.focus();return}catch(_){}}
      return self.clients.openWindow('./'+path.replace(/^\//,''));
    })
  );
});
