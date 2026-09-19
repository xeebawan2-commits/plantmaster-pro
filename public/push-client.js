/* PlantMaster Pro — push-client v1.1.1 (v1.1.0 + fixed VAPID key decoding + error capture for diagnostics)
 * Independent module: registers a push subscription for the signed-in user
 * and shows a dismissible "Enable alerts" banner. Does NOT touch app.js —
 * reads the Supabase session from localStorage (same-origin, set by the app)
 * and talks to the `web-push` edge function.
 */
import {SUPABASE_URL,SUPABASE_ANON_KEY} from './config.js';

/* ⚠️ Deploy note: this public key belongs to the keypair in README-DEPLOY.md.
   If you regenerate VAPID keys, update it here AND the function secrets. */
const VAPID_PUBLIC_KEY='BH9ogu3zE6LfOW6yp4oQs372lm61ySttCWXO4hYe6Rn5LGrwKL2jrZf1hYVpx_bnh_vIHxJ8YEdeyrPmdMBcpcg';
const FN_URL=SUPABASE_URL+'/functions/v1/web-push';
let dismissedThisSession=false; // 'Later' only hides the banner for this page session

const b64ToUint8array=b64=>{const pad='='.repeat((4-b64.length%4)%4);const raw=atob((b64+pad).replace(/-/g,'+').replace(/_/g,'/'));return Uint8Array.from(raw,c=>c.charCodeAt(0))};
const readToken=()=>{
  for(const k of Object.keys(localStorage)){
    if(!/sb-.*-auth-token$/.test(k))continue;
    try{const j=JSON.parse(localStorage.getItem(k));const t=j?.currentSession?.access_token||j?.sessionId;if(t)return t}catch(_){}
  }
  return null;
};


function showBanner(onEnable,onDismiss){
  if(document.getElementById('pushBanner'))return;
  const el=document.createElement('div');
  el.id='pushBanner';
  el.innerHTML=`<div class="pb-ico">🔔</div><div class="pb-txt"><b>Instant alerts on this phone</b>Get work-order and alarm notifications even when the app is closed.</div>`;
  const yes=document.createElement('button');yes.className='pb-yes';yes.textContent='Enable';
  const no=document.createElement('button');no.className='pb-no';no.textContent='Later';
  yes.onclick=()=>{el.remove();onEnable()};
  no.onclick=()=>{dismissedThisSession=true;el.remove();onDismiss()};
  el.append(yes,no);
  document.body.appendChild(el);
}

async function fnCall(path,token,body){
  const r=await fetch(FN_URL+path,{method:'POST',headers:{'Content-Type':'application/json','apikey':SUPABASE_ANON_KEY,Authorization:'Bearer '+token},body:JSON.stringify(body)});
  return r.json().catch(()=>({ok:false,error:'Bad response'}));
}

async function enable(token){
  const reg=await navigator.serviceWorker.ready;
  let sub=await reg.pushManager.getSubscription();
  if(!sub)sub=await reg.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:b64ToUint8array(VAPID_PUBLIC_KEY)});
  const r=await fnCall('/subscribe',token,{subscription:sub.toJSON()});
  if(r.ok)return true;
  console.warn('push subscribe failed',r);
  return false;
}

function init(){
  if(!('serviceWorker' in navigator)||!('PushManager' in window)||!('Notification' in window))return;
  if(document.getElementById('pushBanner'))return;
  if(alreadyDismissed())return;

  const tryStart=async()=>{
    const token=readToken();
    if(!token)return setTimeout(tryStart,5000); // wait until the user signs in
    const reg=await navigator.serviceWorker.getRegistration();
    if(!reg)return setTimeout(tryStart,3000);
    const sub=await reg.pushManager.getSubscription();
    if(sub)return; // already subscribed
    if(Notification.permission==='denied')return; // don't nag
    if(Notification.permission==='granted'){enable(token).catch(()=>{});return;} // permission already given: subscribe silently
    if(dismissedThisSession)return;
    showBanner(async()=>{
      const p=await Notification.requestPermission();
      if(p!=='granted')return;
      const ok=await enable(token);
      const t=document.getElementById('toast');
      if(t){t.textContent=ok?'✓ Alerts enabled on this phone':'Could not enable alerts — try again later';t.classList.add('show');setTimeout(()=>t.classList.remove('show'),4000)}
    },()=>{});
  };
  setTimeout(tryStart,2500); // let the app boot first
}
window.PMPush={
 ready:()=>'serviceWorker'in navigator&&'PushManager'in window&&'Notification'in window,
 status:async()=>{try{const reg=await navigator.serviceWorker.getRegistration();if(!reg)return'no-sw';const sub=await reg.pushManager.getSubscription();return sub?'subscribed':'not-subscribed'}catch(_){return'error'}},
 enable:async(token)=>{
  if(!token){window.__pmPushErr='no login token';return false}
  try{const reg=await navigator.serviceWorker.ready;
   let sub=await reg.pushManager.getSubscription();
   if(!sub)sub=await reg.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:b64ToUint8array(VAPID_PUBLIC_KEY)});
   const r=await fnCall('/subscribe',token,{subscription:sub.toJSON()});
   if(!r.ok){window.__pmPushErr='server: '+(r.error||JSON.stringify(r));return false}
   window.__pmPushErr='';
   return true;
  }catch(e){window.__pmPushErr='local: '+((e&&e.message)||e);return false}
 }
};
document.addEventListener('DOMContentLoaded',init);
