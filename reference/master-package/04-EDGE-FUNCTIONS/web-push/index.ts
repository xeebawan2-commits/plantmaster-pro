/* PlantMaster Pro — web-push edge function v1.0.0
 * Routes (all POST):
 *   /subscribe   {subscription}                     — user JWT auth
 *   /unsubscribe {endpoint}                         — user JWT auth
 *   /send        {organization_id,title,body,tag,severity,route}
 *                internal only (X-Internal-Token)
 *   /poll        {}                                 — internal only; pushes new
 *                rows from the notifications table since the per-org cursor
 * Secrets: VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT (mailto:),
 *          PUSH_INTERNAL_TOKEN (long random string)
 */
import {createClient} from 'npm:@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';

const cors={
  'Access-Control-Allow-Origin':'*',
  'Access-Control-Allow-Headers':'authorization,x-client-info,apikey,content-type,x-internal-token',
  'Access-Control-Allow-Methods':'POST,OPTIONS'
};
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{...cors,'Content-Type':'application/json'}});

function serverSecret(){
  const d=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||Deno.env.get('SUPABASE_SECRET_KEY');
  if(d)return d;
  try{
    const p=JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS')||'{}');
    const v=(Array.isArray(p)?p:Object.values(p||{})).flatMap((x:unknown)=>typeof x==='string'?[x]:Object.values((x||{}) as Record<string,unknown>).filter((y):y is string=>typeof y==='string'));
    const m=v.find(x=>x.startsWith('sb_secret_'));
    return m||v.find(x=>{try{return JSON.parse(atob(x.split('.')[1].replace(/-/g,'+').replace(/_/g,'/'))).role==='service_role'}catch{return false}});
  }catch{return undefined}
}

const url=Deno.env.get('SUPABASE_URL')!;
const anon=Deno.env.get('SUPABASE_ANON_KEY')||Deno.env.get('SUPABASE_PUBLISHABLE_KEY')||'';
const server=serverSecret();
const internalToken=Deno.env.get('PUSH_INTERNAL_TOKEN')||'';
const vapidPub=Deno.env.get('VAPID_PUBLIC_KEY')||'';
const vapidPriv=Deno.env.get('VAPID_PRIVATE_KEY')||'';
const vapidSubject=Deno.env.get('VAPID_SUBJECT')||'mailto:admin@plantmasterpro.com';
if(vapidPriv)webpush.setVapidDetails(vapidSubject,vapidPub,vapidPriv);

function userClient(jwt:string){return createClient(url,anon||'anon',{global:{headers:{Authorization:'Bearer '+jwt}},auth:{persistSession:false,autoRefreshToken:false}})}
async function resolveOrg(admin:any,userId:string):Promise<string|null>{
  const r=await admin.from('organization_members')
    .select('organization_id,role')
    .eq('user_id',userId).eq('active',true)
    .order('role',{ascending:true}).limit(1);
  return r.data?.[0]?.organization_id||null;
}
async function sendToOrg(admin:any,orgId:string,payload:{title:string;body:string;tag?:string;severity?:string;route?:string}){
  const subs=await admin.from('push_subscriptions').select('*').eq('organization_id',orgId);
  if(!subs.data?.length)return{sent:0,pruned:0};
  let sent=0,pruned=0;
  for(const s of subs.data){
    try{
      await webpush.sendNotification(
        {endpoint:s.endpoint,keys:{p256dh:s.p256dh,auth:s.auth}},
        JSON.stringify({title:payload.title,body:payload.body,tag:payload.tag||'pmpro-default',severity:payload.severity,route:payload.route||'/notifications',org_id:orgId}),
        {TTL:60,urgency:'high' as const}
      );
      sent++;
    }catch(err:any){
      const st=err?.statusCode||err?.status;
      if(st===404||st===410){await admin.from('push_subscriptions').delete().eq('id',s.id);pruned++}
      else if(st===429){await admin.from('push_subscriptions').update({last_error_at:new Date().toISOString()}).eq('id',s.id)}
    }
  }
  return{sent,pruned};
}

Deno.serve(async req=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
  if(req.method!=='POST')return json({error:'Method not allowed'},405);
  const path=new URL(req.url).pathname.replace(/\/+$/,'');
  try{
    const body=await req.json().catch(()=>({}));

    if(path.endsWith('/subscribe')){
      if(!vapidPriv)return json({error:'Push not configured on server'},500);
      const jwt=(req.headers.get('Authorization')||'').replace(/^Bearer\s+/i,'');
      if(!jwt)return json({error:'Authentication required'},401);
      const uc=userClient(jwt);
      const ur=await uc.auth.getUser(jwt);
      const user=ur.data.user;
      if(!user||ur.error)return json({error:'Invalid or expired session'},401);
      const org=await resolveOrg(createClient(url,server!),user.id);
      if(!org)return json({error:'No active company membership'},403);
      const sub:any=body.subscription||{};
      if(!sub.endpoint||!sub.keys?.p256dh||!sub.keys?.auth)return json({error:'Invalid subscription payload'},400);
      await createClient(url,server!).from('push_subscriptions')
        .upsert({organization_id:org,user_id:user.id,endpoint:sub.endpoint,p256dh:sub.keys.p256dh,auth:sub.keys.auth,ua:navigator?.userAgent||undefined,created_at:new Date().toISOString()},
          {onConflict:'endpoint'});
      return json({ok:true});
    }

    if(path.endsWith('/unsubscribe')){
      const jwt=(req.headers.get('Authorization')||'').replace(/^Bearer\s+/i,'');
      if(!jwt)return json({error:'Authentication required'},401);
      const uc=userClient(jwt);
      const ur=await uc.auth.getUser(jwt);
      if(!ur.data.user)return json({error:'Invalid or expired session'},401);
      const endpoint=String(body.endpoint||'');
      if(endpoint)await createClient(url,server!).from('push_subscriptions').delete().eq('endpoint',endpoint).eq('user_id',ur.data.user.id);
      return json({ok:true});
    }

    /* ---- internal-only ---- */
    if(req.headers.get('x-internal-token')!==internalToken||!internalToken)return json({error:'Forbidden'},403);

    if(path.endsWith('/send')){
      const orgId=String(body.organization_id||'');
      if(!orgId)return json({error:'organization_id required'},400);
      const r=await sendToOrg(createClient(url,server!),orgId,{
        title:String(body.title||'PlantMaster Pro'),body:String(body.body||''),
        tag:String(body.tag||'pmpro-default'),severity:String(body.severity||'normal'),route:String(body.route||'/notifications')
      });
      return json({ok:true,...r});
    }

    if(path.endsWith('/poll')){
      const admin=createClient(url,server!);
      const orgs=(await admin.from('push_cursors').select('organization_id,last_created_at')).data||[];
      const now=new Date().toISOString();
      let totalSent=0,totalPruned=0,touched=0;
      for(const o of orgs){
        const since=o.last_created_at||'1970-01-01T00:00:00Z';
        const rows=(await admin.from('notifications')
          .select('id,organization_id,title,body,severity,created_at')
          .eq('organization_id',o.organization_id).gt('created_at',since)
          .order('created_at',{ascending:true}).limit(100)).data||[];
        if(!rows.length)continue;
        for(const n of rows){
          const r=await sendToOrg(admin,o.organization_id,{
            title:'PlantMaster Pro',body:(n.body?n.body+' — ':'')+n.title,
            tag:'notif-'+n.id,severity:n.severity==='high'?'high':'normal',route:'/notifications'
          });
          totalSent+=r.sent;totalPruned+=r.pruned;
        }
        const maxTs=rows[rows.length-1].created_at;
        await admin.from('push_cursors').upsert({organization_id:o.organization_id,last_created_at:maxTs||now});
        touched++;
      }
      return json({ok:true,orgs_touched:touched,sent:totalSent,pruned:totalPruned});
    }

    return json({error:'Unknown route'},404);
  }catch(e){
    console.error(e);
    return json({error:'Internal error'},500);
  }
});
