#!/usr/bin/env node
/** PWA / Play Store (TWA) readiness checks against the built public/ output. */
import fs from 'node:fs'; import path from 'node:path';
const OUT='public'; let fail=0, warn=0;
const ok=m=>console.log(`  \x1b[32m✓\x1b[0m ${m}`);
const no=m=>{console.log(`  \x1b[31m✗\x1b[0m ${m}`);fail++};
const wr=m=>{console.log(`  \x1b[33m!\x1b[0m ${m}`);warn++};

if(!fs.existsSync(OUT)){console.error('run: node scripts/build.mjs');process.exit(1)}
const mf=JSON.parse(fs.readFileSync(path.join(OUT,'manifest.webmanifest'),'utf8'));

console.log('\nWeb app manifest');
for(const k of ['name','short_name','start_url','scope','display','icons'])
  mf[k]?ok(`${k} present`):no(`${k} MISSING (required)`);
mf.short_name?.length<=12?ok(`short_name "${mf.short_name}" fits the launcher`)
  :wr(`short_name "${mf.short_name}" may be truncated on the home screen`);
['standalone','fullscreen','minimal-ui'].includes(mf.display)
  ?ok(`display "${mf.display}" is installable`):no(`display "${mf.display}" blocks install`);
mf.background_color?ok('background_color set (splash screen)'):wr('no background_color — white splash');
mf.theme_color?ok('theme_color set'):wr('no theme_color');
mf.id?ok(`id "${mf.id}"`):wr('no id — a future scope change could orphan installs');

console.log('\nIcons');
const has=(s,p)=>mf.icons.some(i=>i.sizes===s&&(!p||(i.purpose||'').includes(p)));
has('192x192')?ok('192x192 present'):no('192x192 MISSING (required by Play)');
has('512x512')?ok('512x512 present'):no('512x512 MISSING (required by Play)');
has('512x512','maskable')?ok('maskable 512 present (adaptive icon)')
  :no('maskable icon MISSING — Android will letterbox the icon');
for(const i of mf.icons){
  const p=path.join(OUT,i.src.replace(/^\//,''));
  if(!fs.existsSync(p)){no(`icon file missing: ${i.src}`);continue}
  const b=fs.readFileSync(p);
  const w=b.readUInt32BE(16),h=b.readUInt32BE(20);
  `${w}x${h}`===i.sizes?ok(`${i.src} is really ${w}x${h}`)
    :no(`${i.src} declares ${i.sizes} but is ${w}x${h}`);
}

/* Screenshots drive the richer install prompt on Android and are reused for
   the Play listing, so a declared-but-missing file is a blocking error. */
console.log('\nScreenshots');
if(!Array.isArray(mf.screenshots)||!mf.screenshots.length)
  wr('no screenshots — Android shows the minimal install prompt');
else{
  const forms=new Set();
  for(const s of mf.screenshots){
    const p=path.join(OUT,s.src.replace(/^\//,''));
    if(!fs.existsSync(p)){no(`screenshot file missing: ${s.src}`);continue}
    const b=fs.readFileSync(p);
    const isPng=b.slice(0,8).equals(Buffer.from([0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a]));
    if(!isPng){no(`${s.src} is not a valid PNG`);continue}
    const w=b.readUInt32BE(16),h=b.readUInt32BE(20);
    if(s.sizes&&`${w}x${h}`!==s.sizes){no(`${s.src} declares ${s.sizes} but is ${w}x${h}`);continue}
    if(s.form_factor)forms.add(s.form_factor);
    /* Play rejects anything under 320px on its shortest side. */
    Math.min(w,h)>=320?ok(`${s.src} ${w}x${h} (${s.form_factor||'any'})`)
      :no(`${s.src} is ${w}x${h} — Play requires at least 320px on the short side`);
  }
  forms.has('wide')?ok('wide form factor covered'):wr('no wide screenshot — desktop install prompt stays minimal');
  forms.has('narrow')?ok('narrow form factor covered'):wr('no narrow screenshot — phone install prompt stays minimal');
}

console.log('\nService worker & offline');
const sw=path.join(OUT,'service-worker.js');
fs.existsSync(sw)?ok('service-worker.js shipped'):no('no service worker — not installable');
const swSrc=fs.existsSync(sw)?fs.readFileSync(sw,'utf8'):'';
/addEventListener\(\s*['"]fetch/.test(swSrc)?ok('fetch handler present (install criterion)')
  :no('no fetch handler — Chrome will not offer installation');
/addEventListener\(\s*['"]push/.test(swSrc)?ok('push handler present'):wr('no push handler');
fs.existsSync(path.join(OUT,'offline.html'))?ok('offline fallback page shipped')
  :wr('no offline.html');
const idx=fs.readFileSync(path.join(OUT,'index.html'),'utf8');
/rel="manifest"/.test(idx)?ok('index.html links the manifest'):no('manifest not linked');
/name="viewport"/.test(idx)?ok('viewport meta present'):no('viewport meta MISSING');
/name="theme-color"/.test(idx)?ok('theme-color meta present'):wr('no theme-color meta');
/name="description"/.test(idx)?ok('description meta present'):wr('no description meta');

console.log('\nTWA / Digital Asset Links');
const alPath=path.join(OUT,'.well-known','assetlinks.json');
if(!fs.existsSync(alPath)) no('.well-known/assetlinks.json MISSING — TWA shows a URL bar');
else{
  const al=JSON.parse(fs.readFileSync(alPath,'utf8'));
  const st=al[0];
  st?.relation?.includes('delegate_permission/common.handle_all_urls')
    ?ok('relation correct'):no('wrong relation');
  st?.target?.package_name?ok(`package ${st.target.package_name}`):no('no package_name');
  const fp=st?.target?.sha256_cert_fingerprints?.[0]||'';
  /^([A-F0-9]{2}:){31}[A-F0-9]{2}$/i.test(fp)
    ? ok('SHA-256 fingerprint looks valid')
    : wr('fingerprint is still a placeholder — paste the Play App Signing SHA-256 before release');
  const manifest=fs.existsSync('android/app/src/main/AndroidManifest.xml');
  manifest?ok('Android TWA project present'):wr('no android/ project');
}

console.log('\nSecurity headers');
const hd=fs.existsSync(path.join(OUT,'_headers'))?fs.readFileSync(path.join(OUT,'_headers'),'utf8'):'';
for(const h of ['Content-Security-Policy','X-Content-Type-Options',
                'Strict-Transport-Security','Referrer-Policy','Permissions-Policy'])
  hd.includes(h)?ok(h):wr(`${h} not set`);

console.log(`\n${fail?'\x1b[31m':'\x1b[32m'}${fail} blocking, ${warn} advisory\x1b[0m\n`);
process.exit(fail?1:0);
