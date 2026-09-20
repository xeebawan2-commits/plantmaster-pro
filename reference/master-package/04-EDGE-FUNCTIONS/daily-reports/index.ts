/* PlantMaster Pro — daily-reports edge function v1.0.0
 * Sends the per-organization daily maintenance summary by email via Resend.
 * Triggered by GitHub Actions cron (see workflows/daily-reports.yml) —
 * no Supabase plan features required.
 *
 * POST /run  {"token":"<DAILY_REPORTS_TOKEN>"}
 *
 * Secrets: DAILY_REPORTS_TOKEN (long random string),
 *          RESEND_API_KEY (re_xxx),
 *          DAILY_REPORTS_FROM (e.g. 'PlantMaster Pro <reports@plantmasterpro.com>')
 *
 * Notes:
 *  - Resend free tier = 3 emails/hour, 100/day. Fine for the first ~30
 *    customers; upgrade or switch to Brevo (300/day free) later.
 *  - Sends only for orgs in trial/active with a non-empty settings.email.
 *  - Each metric is defensive: a missing column returns 0, never 500.
 */
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'content-type,x-internal-token','Access-Control-Allow-Methods':'POST,OPTIONS'};
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

const sleep=(ms:number)=>new Promise(r=>setTimeout(r,ms));
const today=new Date().toISOString().slice(0,10);
const dayAgo=new Date(Date.now()-24*3600*1000).toISOString();

function esc(s:string){return String(s??'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;')}

function emailHtml(orgName:string,m:any,top:string[]){
  const rows=(k:string,v:string,alert=false)=>`<tr><td style="padding:10px 14px;border-bottom:1px solid #e5eef7;color:#41546e">${k}</td><td style="padding:10px 14px;border-bottom:1px solid #e5eef7;font-weight:700;text-align:right;color:${alert?'#b45309':'#0b1526'}">${v}</td></tr>`;
  return `<!doctype html><html><body style="margin:0;background:#f2f6fb;font-family:Arial,Helvetica,sans-serif">
  <div style="max-width:560px;margin:24px auto;background:#ffffff;border-radius:14px;overflow:hidden;border:1px solid #dbe7f3">
    <div style="background:#07101c;padding:22px 24px">
      <div style="color:#22d3ee;font-size:12px;font-weight:700;letter-spacing:.12em;text-transform:uppercase">PlantMaster Pro — Daily Report</div>
      <div style="color:#ffffff;font-size:20px;font-weight:700;margin-top:6px">${esc(orgName)}</div>
      <div style="color:#8fa3bd;font-size:12px;margin-top:2px">${today}</div>
    </div>
    <table style="width:100%;border-collapse:collapse;font-size:14px">
      ${rows('Open work orders',String(m.openWos))}
      ${rows('Overdue work orders',String(m.overdueWos),m.overdueWos>0)}
      ${rows('Preventive due today / overdue',String(m.pmDue),m.pmDue>0)}
      ${rows('Condition alarms (24 h)',String(m.alarms),m.alarms>0)}
      ${rows('Work completed (24 h)',String(m.completed),false)}
    </table>
    <div style="padding:18px 24px 6px">
      <div style="color:#41546e;font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.08em;margin-bottom:8px">Oldest open work orders</div>
      ${top.length?top.map(t=>`<div style="color:#0b1526;font-size:13.5px;padding:7px 0;border-bottom:1px solid #eef4fa">• ${esc(t)}</div>`).join(''):'<div style="color:#41546e;font-size:13.5px;padding:7px 0">Nothing open 🎉</div>'}
    </div>
    <div style="padding:16px 24px 22px;color:#8fa3bd;font-size:11.5px;line-height:1.6">
      Open PlantMaster Pro for full detail. If your workspace is suspended or paused, contact your administrator.
    </div>
  </div></body></html>`;
}

Deno.serve(async req=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
  if(req.method!=='POST')return json({error:'Method not allowed'},405);
  try{
    const body=await req.json().catch(()=>({}));
    const token=Deno.env.get('DAILY_REPORTS_TOKEN')||'';
    if(!token||body.token!==token)return json({error:'Forbidden'},403);
    const resendKey=Deno.env.get('RESEND_API_KEY')||'';
    if(!resendKey)return json({error:'RESEND_API_KEY missing'},500);
    const from=Deno.env.get('DAILY_REPORTS_FROM')||'PlantMaster Pro <onboarding@resend.dev>';
    const url=Deno.env.get('SUPABASE_URL')!;
    const server=serverSecret();
    if(!server)return json({error:'Supabase server environment incomplete'},500);
    const admin:any=createClient(url,server,{auth:{persistSession:false,autoRefreshToken:false}});

    const orgs=(await admin.from('organizations').select('id,name,commercial_status').in('commercial_status',['active','trial'])).data||[];
    const settings=(await admin.from('organization_settings').select('organization_id,email')).data||[]
      .filter((s:any)=>s.email&&String(s.email).includes('@'));
    const byOrg:Record<string,string>=Object.fromEntries(settings.map((s:any)=>[s.organization_id,s.email]));

    const sent:any[]=[],skipped:any[]=[],errors:any[]=[];
    for(const o of orgs){
      const email=byOrg[o.id];
      if(!email){skipped.push({org:o.name,reason:'no email configured'});continue}
      const safe=(fn:()=>Promise<any>,fallback:any=0)=>fn().then(r=>(r.error?fallback:r.data)).catch(()=>fallback);
      const count=(r:any)=>Array.isArray(r)?(r.length>1?r[1]?.count??r.length:(r[0]?.count??r.length)):0;

      const openWos=await count(safe(()=>admin.from('work_orders').select('id',{count:'exact',head:true}).eq('organization_id',o.id).eq('status','open')));
      const overdueWos=await count(safe(()=>admin.from('work_orders').select('id',{count:'exact',head:true}).eq('organization_id',o.id).eq('status','open').lt('due_at',today+'T23:59:59Z')));
      const pmDue=await count(safe(()=>admin.from('maintenance_plans').select('id',{count:'exact',head:true}).eq('organization_id',o.id).eq('status','pending').lte('next_due',today)));
      const alarms=await count(safe(()=>admin.from('condition_alarms').select('id',{count:'exact',head:true}).eq('organization_id',o.id).gte('created_at',dayAgo)));
      const completed=await count(safe(()=>admin.from('work_orders').select('id',{count:'exact',head:true}).eq('organization_id',o.id).in('status',['completed','closed']).gte('updated_at',dayAgo)));
      const top=(await safe(()=>admin.from('work_orders').select('title,due_at').eq('organization_id',o.id).eq('status','open').order('created_at',{ascending:true}).limit(5),[])).map((w:any)=>w.due_at&&w.due_at.slice(0,10)<today?`${w.title} (OVERDUE ${w.due_at.slice(0,10)})`:w.title);

      const html=emailHtml(o.name,{openWos:openWos||0,overdueWos:overdueWos||0,pmDue:pmDue||0,alarms:alarms||0,completed:completed||0},top||[]);
      const r=await fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:'Bearer '+resendKey,'Content-Type':'application/json'},body:JSON.stringify({from,to:email,subject:`Daily maintenance summary — ${o.name} — ${today}`,html})});
      const jr=await r.json().catch(()=>({}));
      if(r.ok)sent.push({org:o.name,email});
      else errors.push({org:o.name,status:r.status,error:jr.message||String(r.status)});
      await sleep(250); // stay well under Resend rate limits
    }
    return json({ok:true,sent:sent.length,skipped:skipped.length,errors,results:{sent,skipped,errors}});
  }catch(e){
    console.error(e);
    return json({error:'Internal error: '+(e as Error).message},500);
  }
});
