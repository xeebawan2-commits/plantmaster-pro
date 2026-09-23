/* ============================================================
   PlantMaster Control Center
   HSB Fix Services — admin front-end

   Uses the existing Supabase project and the existing control_*
   RPCs. No backend changes required.
   ============================================================ */

import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import {
  SUPABASE_URL, SUPABASE_ANON_KEY, CUSTOMER_APP_URL
} from './config.js';

const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
});

/* ---------- state ---------- */
let user  = null;
let admin = null;
let route = 'dashboard';
let plansCache = [];

/* Rows are kept in JS and looked up by id.
   Nothing is round-tripped through HTML attributes, so escaping,
   stray spaces and quotes in a company name can never corrupt it. */
const STORE = { companies:{}, accounts:{}, requests:{}, invites:{}, plans:{}, files:{}, tickets:{} };

/* ---------- helpers ---------- */
const $  = s => document.querySelector(s);
const $$ = s => Array.from(document.querySelectorAll(s));
const view = () => $('#view');

const esc = v => String(v ?? '').replace(/[&<>"']/g,
  c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));

const fmtDate = v => {
  if (!v) return '—';
  const d = new Date(v);
  return isNaN(d) ? '—' : d.toLocaleDateString('en-GB',{day:'2-digit',month:'short',year:'numeric'});
};
const fmtDateTime = v => {
  if (!v) return '—';
  const d = new Date(v);
  return isNaN(d) ? '—' : d.toLocaleString('en-GB',{day:'2-digit',month:'short',year:'numeric',hour:'2-digit',minute:'2-digit'});
};
const bytes = n => {
  n = Number(n||0);
  if (!n) return '0';
  const u=['B','KB','MB','GB','TB']; const i=Math.min(Math.floor(Math.log(n)/Math.log(1024)),4);
  return (n/Math.pow(1024,i)).toFixed(i?1:0)+' '+u[i];
};
const num = v => Number(v||0).toLocaleString();
const GB = 1024**3, MB = 1024**2;

const badge = v => {
  const k = String(v||'unknown').toLowerCase().replace(/[^a-z_]/g,'');
  return `<span class="badge ${k}">${esc(String(v||'unknown').replace(/_/g,' '))}</span>`;
};

function errText(e){
  if (!e) return 'Unknown error';
  if (typeof e === 'string') return e;
  return e.message || e.error_description || e.error || e.details || e.hint || JSON.stringify(e);
}

function toast(msg, kind='ok'){
  const t = $('#toast');
  t.textContent = msg;
  t.className = 'show ' + kind;
  clearTimeout(t._timer);
  t._timer = setTimeout(() => { t.className = ''; }, 4200);
}

/* ============================================================
   MODALS
   ============================================================ */
function closeModal(){ $('#modalRoot').innerHTML = ''; }

/* fields: {name,label,type,value,options,required,placeholder,help,heading} */
function openForm({ title, intro, fields = [], submitLabel = 'Save', danger = false, onSubmit }){
  return new Promise(resolve => {
    const body = fields.map(f => {
      if (f.heading) return `<div class="section-title">${esc(f.heading)}</div>`;
      if (f.note) return `<p class="form-note">${f.note}</p>`;
      const req = f.required ? 'required' : '';
      const val = esc(f.value ?? '');
      const help = f.help ? `<small style="display:block;margin-top:4px">${esc(f.help)}</small>` : '';

      if (f.type === 'select'){
        const opts = (f.options||[]).map(o => {
          const v = typeof o === 'string' ? o : o.value;
          const l = typeof o === 'string' ? o : o.label;
          return `<option value="${esc(v)}" ${String(v)===String(f.value)?'selected':''}>${esc(l)}</option>`;
        }).join('');
        return `<label class="field"><span>${esc(f.label)}</span><select name="${f.name}" ${req}>${opts}</select>${help}</label>`;
      }
      if (f.type === 'textarea'){
        return `<label class="field"><span>${esc(f.label)}</span><textarea name="${f.name}" ${req} placeholder="${esc(f.placeholder||'')}">${val}</textarea>${help}</label>`;
      }
      if (f.type === 'checkbox'){
        const dis = f.disabled ? 'disabled' : '';
        return `<label class="checkline${f.disabled?' is-locked':''}"><input type="checkbox" name="${f.name}" ${f.value?'checked':''} ${dis}><span>${esc(f.label)}</span></label>`;
      }
      /* autocapitalize/autocorrect off: phone keyboards were changing
         typed confirmations and breaking the match. */
      return `<label class="field"><span>${esc(f.label)}</span>
        <input type="${f.type||'text'}" name="${f.name}" value="${val}" ${req}
               placeholder="${esc(f.placeholder||'')}"
               ${f.step?`step="${f.step}"`:''}
               autocomplete="off" autocapitalize="off" autocorrect="off" spellcheck="false">
        ${help}</label>`;
    }).join('');

    $('#modalRoot').innerHTML = `
      <div class="modal-backdrop">
        <form class="modal" id="modalForm">
          <h3>${esc(title)}</h3>
          ${intro?`<p>${intro}</p>`:''}
          <div class="error-box" id="modalError" hidden></div>
          ${body}
          <div class="actions">
            <button type="button" class="ghost" id="modalCancel">Cancel</button>
            <button type="submit" class="${danger?'danger':'primary'}" id="modalOk">${esc(submitLabel)}</button>
          </div>
        </form>
      </div>`;

    const close = v => { closeModal(); resolve(v); };
    $('#modalCancel').onclick = () => close(null);
    $('.modal-backdrop').onclick = e => { if (e.target.classList.contains('modal-backdrop')) close(null); };

    $('#modalForm').onsubmit = async e => {
      e.preventDefault();
      const fd = new FormData(e.target);
      const data = {};
      fields.forEach(f => {
        if (f.heading) return;
        data[f.name] = f.type === 'checkbox' ? fd.get(f.name)==='on' : String(fd.get(f.name) ?? '').trim();
      });
      const btn = $('#modalOk');
      btn.disabled = true; btn.textContent = 'Working…';
      try {
        if (onSubmit) await onSubmit(data);
        close(data);
      } catch (err){
        const box = $('#modalError');
        box.textContent = errText(err);
        box.hidden = false;
        btn.disabled = false; btn.textContent = submitLabel;
        $('.modal').scrollTop = 0;
      }
    };
  });
}

/* Replies have to go before the ticket they belong to. The column
   name differs between installs, so try each and ignore misses. */
async function deleteTicketMessages(ids){
  for (const col of ['ticket_id','support_ticket_id','thread_id']){
    const { error } = await sb.from('platform_support_messages').delete().in(col, ids);
    if (!error) return;
  }
}

/* Turn a Postgres error into something worth reading. */
function explainDbError(raw){
  if (/append-only/i.test(raw))
    return `The audit log is protected and refused this change.\n\nRun 07-FULL-CONTROL.sql — it unhooks the audit log so it stops blocking deletes while keeping every record.\n\nExact error: ${raw}`;

  if (/foreign key|violates/i.test(raw)){
    const child  = raw.match(/on table "([a-z_]+)"/i);
    const parent = raw.match(/table "([a-z_]+)" violates/i);
    return `Other records still point at this${parent?` ${parent[1].replace(/_/g,' ')}`:''}${child?`, in "${child[1].replace(/_/g,' ')}"`:''}, so the database will not remove it yet.\n\nRun 07-FULL-CONTROL.sql — it fixes every link like this in one pass.\n\nExact error: ${raw}`;
  }
  if (/permission|denied|not allowed/i.test(raw))
    return `Your admin account was refused this action.\n\nExact error: ${raw}`;

  return raw;
}

/* A full, selectable error. Toasts vanish and truncate; database
   messages are long and worth reading. */
function showError(title, message){
  $('#modalRoot').innerHTML = `
    <div class="modal-backdrop">
      <div class="modal">
        <h3>${esc(title)}</h3>
        <div class="error-box" style="white-space:pre-wrap;margin-top:8px">${esc(message)}</div>
        <div class="actions" style="border-top:0;padding-top:4px">
          <button class="ghost" id="errCopy">Copy message</button>
          <button class="primary" id="errClose">Close</button>
        </div>
      </div>
    </div>`;
  $('#errCopy').onclick = async () => {
    try { await navigator.clipboard.writeText(message); toast('Copied'); }
    catch { toast('Select the text and copy by hand','bad'); }
  };
  $('#errClose').onclick = closeModal;
}

function confirmAction(title, message, okLabel='Confirm'){
  return new Promise(resolve => {
    $('#modalRoot').innerHTML = `
      <div class="modal-backdrop">
        <div class="modal">
          <h3>${esc(title)}</h3>
          <p>${message}</p>
          <div class="actions">
            <button class="ghost" id="cNo">Cancel</button>
            <button class="danger" id="cYes">${esc(okLabel)}</button>
          </div>
        </div>
      </div>`;
    const done = v => { closeModal(); resolve(v); };
    $('#cNo').onclick = () => done(false);
    $('#cYes').onclick = () => done(true);
    $('.modal-backdrop').onclick = e => { if (e.target.classList.contains('modal-backdrop')) done(false); };
  });
}

/* Type-to-confirm. Always the single word DELETE — short, no spaces,
   nothing a phone keyboard can mangle. Case is ignored. */
async function confirmDelete(title, message, okLabel='Delete'){
  let ok = false;
  await openForm({
    title, intro: message, submitLabel: okLabel, danger: true,
    fields: [{ name:'confirm', label:'Type DELETE to confirm', required:true, placeholder:'DELETE' }],
    onSubmit: async d => {
      if (d.confirm.replace(/\s+/g,'').toUpperCase() !== 'DELETE')
        throw new Error('Type the word DELETE to confirm.');
      ok = true;
    }
  });
  return ok;
}

/* ============================================================
   RENDER HELPERS
   ============================================================ */
const head = (t,s) => `<div class="page-head"><h2>${esc(t)}</h2>${s?`<small>${esc(s)}</small>`:''}</div>`;
const skeletons = (n=3) => Array.from({length:n},()=>'<div class="skeleton"></div>').join('');
const empty = m => `<div class="empty">${esc(m)}</div>`;
const rowLine = (k,v) => `<div class="row"><span>${esc(k)}</span><span>${v}</span></div>`;

async function safeRender(fn){
  try { await fn(); }
  catch (err){
    view().innerHTML = `<div class="error-box"><b>Could not load this page.</b><br>${esc(errText(err))}</div>
      <button class="ghost block" data-act="reloadPage">Try again</button>`;
    bindActions();
  }
}

function bindActions(root = document){
  root.querySelectorAll('[data-act]').forEach(el => {
    if (el._bound) return;
    el._bound = true;
    el.onclick = async ev => {
      ev.preventDefault();
      const handler = ACTIONS[el.dataset.act];
      if (!handler) return;
      const label = el.textContent;
      el.disabled = true; el.textContent = '…';
      try { await handler(el.dataset); }
      catch (err){ toast(errText(err), 'bad'); }
      finally {
        if (el.isConnected){ el.disabled = false; el.textContent = label; }
      }
    };
  });
}

/* ============================================================
   DASHBOARD
   ============================================================ */
async function pageDashboard(){
  view().innerHTML = head('Dashboard','Live platform overview') + skeletons(2);

  const { data, error } = await sb.rpc('control_dashboard');
  if (error) throw error;
  const x = data || {};

  /* Every tile opens the matching screen. */
  const tile = (label, value, detail, go, warn) => `
    <button class="stat tile${warn?' attention':''}" data-act="${go}">
      <div class="n">${typeof value==='string'?esc(value):esc(num(value))}</div>
      <div class="l">${esc(label)}</div>
      <div class="d">${esc(detail)}</div>
    </button>`;

  view().innerHTML = head('Dashboard','Live platform overview') + `
    <div class="stats">
      ${tile('Companies', x.companies_total, `${num(x.companies_active)} active`, 'goCompanies')}
      ${tile('Accounts',  x.workers,         `${num(x.owners)} owners`,          'goAccounts')}
      ${tile('Awaiting approval', x.pending_requests ?? 0, 'signup enquiries', 'goRequests',
              Number(x.pending_requests)>0)}
      ${tile('Storage', bytes(x.storage_bytes), `${num(x.files)} files`, 'goFiles')}
    </div>

    <div class="section-title">Company status</div>
    <div class="card lifecycle">
      <button data-act="filterActive"><span>Active</span><b>${num(x.companies_active)}</b></button>
      <button data-act="filterTrial"><span>On trial</span><b>${num(x.companies_trial)}</b></button>
      <button data-act="filterPastDue"><span>Past due</span><b>${num(x.companies_past_due)}</b></button>
      <button data-act="filterSuspended"><span>Suspended</span><b>${num(x.companies_suspended)}</b></button>
      ${x.complimentary!=null?`<button data-act="goCompanies"><span>Free access</span><b>${num(x.complimentary)}</b></button>`:''}
    </div>

    <div class="section-title">Quick actions</div>
    <div class="card"><div class="actions tight">
      <button class="primary" data-act="inviteOwner">Invite an owner</button>
      <button data-act="goRequests">Approvals</button>
      <button data-act="goPlans">Packages</button>
    </div></div>

    <div class="section-title">Needs attention</div>
    <div class="card">
      <div class="card-body">
        ${rowLine('Open complaints', Number(x.open_tickets)>0
            ? `<b style="color:var(--warn)">${num(x.open_tickets)}</b>${x.critical_tickets?` (${num(x.critical_tickets)} critical)`:''}`
            : 'None')}
        ${rowLine('Open incidents', Number(x.open_incidents)>0
            ? `<b style="color:var(--warn)">${num(x.open_incidents)}</b>${x.critical_incidents?` (${num(x.critical_incidents)} critical)`:''}`
            : 'None')}
        ${rowLine('AI requests this month', num(x.ai_requests_month))}
      </div>
      <div class="actions"><button class="block" data-act="goSupport">Open complaints</button></div>
    </div>`;
  bindActions();
}

/* ============================================================
   COMPANIES
   ============================================================ */
function companiesToolbar(search, status){
  return `<div class="toolbar">
      <input id="coSearch" placeholder="Search companies" value="${esc(search)}"
             autocapitalize="off" autocorrect="off">
      <select id="coStatus">
        ${['','trial','active','past_due','suspended','cancelled','deletion_pending']
          .map(s=>`<option value="${s}" ${s===status?'selected':''}>${s?s.replace(/_/g,' '):'All statuses'}</option>`).join('')}
      </select>
    </div>`;
}

async function pageCompanies(search='', status=''){
  view().innerHTML = head('Companies','Plans, status and access') + companiesToolbar(search,status) + skeletons();

  const [{ data, error }, plans] = await Promise.all([
    sb.rpc('control_companies', { p_search: search||null, p_status: status||null }),
    loadPlans()
  ]);
  if (error) throw error;

  const rows = data || [];
  STORE.companies = {};
  rows.forEach(c => { STORE.companies[c.organization_id] = c; });

  const cards = rows.length ? rows.map(c => {
    const id = c.organization_id;
    return `<article class="card">
      <div class="card-head">
        <h3>${esc(c.name||'Unnamed')}</h3>
        ${badge(c.status)}
      </div>
      <div class="card-body">
        ${rowLine('Plan', esc(c.plan_name||c.plan_code||'No plan'))}
        ${rowLine('Owners', esc(c.owners??0))}
        ${rowLine('Workers', esc(c.workers??0))}
        ${rowLine('Plants', esc(c.plants??0))}
        ${rowLine('Files', esc(num(c.files)))}
        ${rowLine('Storage', bytes(c.storage_bytes))}
        ${rowLine('AI this month', esc(num(c.ai_requests_month)))}
        ${Number(c.open_tickets)>0 ? rowLine('Open complaints', `<b style="color:var(--warn)">${esc(c.open_tickets)}</b>`) : ''}
        ${Number(c.open_incidents)>0 ? rowLine('Open incidents', `<b style="color:var(--warn)">${esc(c.open_incidents)}</b>`) : ''}
        ${c.access_type && c.access_type!=='paid'
          ? rowLine('Access', `${badge(c.access_type)}${c.complimentary_ends_at?' until '+fmtDate(c.complimentary_ends_at):' (permanent)'}`) : ''}
        ${rowLine('Created', fmtDate(c.created_at))}
      </div>
      <div class="actions">
        <button class="primary" data-act="editCompanyPlan" data-id="${esc(id)}">Edit this company's package</button>
        <button data-act="changeStatus" data-id="${esc(id)}">Change status</button>
        <button data-act="freeAccess" data-id="${esc(id)}">Free access</button>
        <button class="danger" data-act="deleteCompany" data-id="${esc(id)}">Delete</button>
      </div>
    </article>`;
  }).join('') : empty('No companies found.');

  view().innerHTML = head('Companies','Plans, status and access') + companiesToolbar(search,status) +
    `<small style="display:block;margin-bottom:10px">${rows.length} ${rows.length===1?'company':'companies'}</small>` + cards;

  $('#coSearch').onchange = e => safeRender(()=>pageCompanies(e.target.value, $('#coStatus').value));
  $('#coStatus').onchange = e => safeRender(()=>pageCompanies($('#coSearch').value, e.target.value));
  bindActions();
}

async function loadPlans(force){
  if (plansCache.length && !force) return plansCache;
  const { data, error } = await sb.from('subscription_plans').select('*').order('price_monthly');
  if (error) throw error;
  plansCache = data || [];
  STORE.plans = {};
  plansCache.forEach(p => { STORE.plans[p.code] = p; });
  return plansCache;
}

/* ============================================================
   APPROVALS
   ============================================================ */
const PENDING_STATES = ['new','contacted','pending'];
const isPending = x => PENDING_STATES.includes(String(x.status||'').toLowerCase());

async function pageRequests(filter='pending'){
  view().innerHTML = head('Approvals','Enquiries from hsbfix.org. No account exists until you approve.') + skeletons();

  const { data, error } = await sb.from('signup_requests')
    .select('*').order('created_at',{ascending:false}).limit(300);
  if (error) throw error;

  const all = data || [];
  STORE.requests = {};
  all.forEach(x => { STORE.requests[x.id] = x; });

  const pendingCount = all.filter(isPending).length;
  const rows = filter==='pending' ? all.filter(isPending) : all;

  const cards = rows.length ? rows.map(x => {
    const wa = String(x.phone||'').replace(/\D/g,'').replace(/^0/,'92');
    const canAct = isPending(x);
    return `<article class="card">
      <div class="card-head"><h3>${esc(x.company_name||'—')}</h3>${badge(x.status)}</div>
      <div class="card-body">
        ${rowLine('Contact', esc(x.contact_name||'—'))}
        ${rowLine('Email', `<span class="break">${esc(x.email||'—')}</span>`)}
        ${rowLine('Phone', esc(x.phone||'—'))}
        ${x.plant_type?rowLine('Industry', esc(x.plant_type)):''}
        ${x.team_size?rowLine('Team', esc(x.team_size)):''}
        ${x.plan_interest?rowLine('Wants', esc(x.plan_interest)):''}
        ${rowLine('Received', fmtDateTime(x.created_at))}
        ${x.message?`<div style="margin-top:8px;font-style:italic;color:var(--muted)">${esc(x.message)}</div>`:''}
      </div>
      <div class="actions">
        ${canAct?`<button class="primary" data-act="approveRequest" data-id="${esc(x.id)}">Approve</button>
          <button data-act="rejectRequest" data-id="${esc(x.id)}">Reject</button>`:''}
        ${wa?`<a class="btn" style="text-align:center;line-height:22px" href="https://wa.me/${wa}" target="_blank" rel="noopener">WhatsApp</a>`:''}
        <a class="btn" style="text-align:center;line-height:22px" href="mailto:${esc(x.email||'')}">Email</a>
        <button class="danger" data-act="deleteRequest" data-id="${esc(x.id)}">Delete</button>
      </div>
    </article>`;
  }).join('') : empty(filter==='pending'
      ? 'Nothing waiting for approval. Tap All to see handled enquiries.'
      : 'No enquiries yet.');

  view().innerHTML = head('Approvals','Enquiries from hsbfix.org. No account exists until you approve.') + `
    <div class="toolbar">
      <button class="${filter==='pending'?'primary':''}" data-act="reqPending">Pending (${pendingCount})</button>
      <button class="${filter==='all'?'primary':''}" data-act="reqAll">All (${all.length})</button>
      <button class="danger" data-act="purgeRejected">Purge rejected</button>
    </div>${cards}`;
  bindActions();
}

/* ============================================================
   ACCOUNTS
   ============================================================ */
async function pageAccounts(search=''){
  view().innerHTML = head('Accounts','User logins, access and removal') + skeletons();

  const { data, error } = await sb.rpc('control_accounts', { p_search: search||null });
  if (error) throw error;
  const rows = data || [];
  STORE.accounts = {};
  rows.forEach(a => { STORE.accounts[a.user_id] = a; });

  const cards = rows.length ? rows.map(a => {
    const suspended = !!a.banned_until;
    const memberships = (a.companies||[]).length
      ? (a.companies||[]).map(c => rowLine(c.company, esc(String(c.role||'').replace(/_/g,' ')))).join('')
      : rowLine('Companies','None');
    return `<article class="card">
      <div class="card-head">
        <h3>${esc(a.full_name||a.email||'Unnamed')}</h3>
        ${badge(suspended?'suspended':'active')}
      </div>
      <div class="card-body">
        ${rowLine('Email', `<span class="break">${esc(a.email||'—')}</span>`)}
        ${memberships}
        ${rowLine('Created', fmtDate(a.created_at))}
        ${rowLine('Last seen', fmtDate(a.last_sign_in_at))}
      </div>
      <div class="actions">
        <button data-act="resetPassword" data-id="${esc(a.user_id)}">Reset password</button>
        ${suspended
          ? `<button data-act="unbanUser" data-id="${esc(a.user_id)}">Restore</button>`
          : `<button data-act="banUser" data-id="${esc(a.user_id)}">Suspend</button>`}
        <button class="danger" data-act="deleteUser" data-id="${esc(a.user_id)}">Delete</button>
      </div>
    </article>`;
  }).join('') : empty('No accounts found.');

  view().innerHTML = head('Accounts','User logins, access and removal') + `
    <div class="toolbar">
      <input id="acSearch" placeholder="Search email or name" value="${esc(search)}"
             autocapitalize="off" autocorrect="off">
      <button class="primary" data-act="inviteOwner">Invite owner</button>
    </div>
    <small style="display:block;margin-bottom:10px">${rows.length} ${rows.length===1?'account':'accounts'}</small>
    ${cards}`;

  $('#acSearch').onchange = e => safeRender(()=>pageAccounts(e.target.value));
  bindActions();
}

/* ============================================================
   INVITATIONS
   ============================================================ */
const inviteState = x => x.used_at ? 'used'
  : x.revoked_at ? 'revoked'
  : (x.expires_at && new Date(x.expires_at) < new Date()) ? 'expired'
  : 'live';

async function pageInvites(){
  view().innerHTML = head('Invitations','Approved companies waiting for their login') + skeletons();

  const { data, error } = await sb.from('owner_invitations')
    .select('*').order('created_at',{ascending:false}).limit(200);
  if (error) throw error;
  const rows = data || [];
  STORE.invites = {};
  rows.forEach(x => { STORE.invites[x.id] = x; });

  const cards = rows.length ? rows.map(x => {
    const s = inviteState(x);
    return `<article class="card">
      <div class="card-head"><h3>${esc(x.company_name||'—')}</h3>${badge(s)}</div>
      <div class="card-body">
        ${rowLine('Email', `<span class="break">${esc(x.email||'—')}</span>`)}
        ${rowLine('Plan', esc(x.plan_code||'—') + (x.trial_days?` · ${esc(x.trial_days)} day trial`:''))}
        ${x.plant_name?rowLine('Plant', esc(x.plant_name)):''}
        ${rowLine('Expires', fmtDate(x.expires_at))}
        ${x.used_at?rowLine('Login created', fmtDateTime(x.used_at)):''}
      </div>
      <div class="actions">
        ${s==='live'?`<button class="primary" data-act="createLogin" data-id="${esc(x.id)}">Create login &amp; password</button>`:''}
        ${s==='live'?`<button data-act="revokeInvite" data-id="${esc(x.id)}">Revoke</button>`:''}
        <button class="danger" data-act="deleteInvite" data-id="${esc(x.id)}">Delete</button>
      </div>
    </article>`;
  }).join('') : empty('No invitations yet.');

  view().innerHTML = head('Invitations','Approved companies waiting for their login') + `
    <div class="note-box">A <b>live</b> invitation means the company is approved but the owner has no login yet. Tap <b>Create login &amp; password</b> to generate it and get the details to send them.</div>
    <div class="toolbar">
      <button class="primary" data-act="inviteOwner">Invite an owner</button>
      <button data-act="cleanupInvites">Clear revoked &amp; expired</button>
    </div>${cards}`;
  bindActions();
}

/* ============================================================
   PLANS  (full create / edit)
   ============================================================ */
async function pagePlans(){
  view().innerHTML = head('Plans & packages','Create and edit the packages you sell') + skeletons();
  const plans = await loadPlans(true);

  const cards = plans.length ? plans.map(p => `
    <article class="card">
      <div class="card-head"><h3>${esc(p.name||p.code)}</h3>${badge(p.active===false?'inactive':'active')}</div>
      <div class="card-body">
        ${rowLine('Code', esc(p.code))}
        ${rowLine('Monthly', p.price_monthly!=null?'PKR '+num(p.price_monthly):'—')}
        ${rowLine('Yearly', p.price_yearly!=null?'PKR '+num(p.price_yearly):'—')}
        ${rowLine('Max workers', esc(num(p.max_workers)))}
        ${rowLine('Max plants', esc(num(p.max_plants)))}
        ${rowLine('Storage', bytes(p.max_storage_bytes))}
        ${rowLine('AI / month', esc(num(p.ai_requests_month)))}
        ${rowLine('Retention', esc(p.retention_days??0)+' days')}
      </div>
      <div class="actions">
        <button class="primary" data-act="editPlan" data-code="${esc(p.code)}">Edit</button>
        <button data-act="togglePlan" data-code="${esc(p.code)}">${p.active===false?'Activate':'Deactivate'}</button>
      </div>
    </article>`).join('') : empty('No plans yet. Tap New package to create your first one.');

  view().innerHTML = head('Plans & packages','Create and edit the packages you sell') + `
    <div class="toolbar"><button class="primary" data-act="newPlan">New package</button></div>
    <div class="note-box">Changing a price changes what every customer on that package pays. To move one company to a different package, use the Companies tab.</div>
    ${cards}`;
  bindActions();
}

/* Every module the customer app can switch on or off.
   Key = what gets stored in the plan's features JSON. */
const MODULES = [
  { key:'analytics',              label:'Advanced analytics & KPIs' },
  { key:'gemini',                 label:'Gemini AI assistant' },
  { key:'deep_search',            label:'AI deep search' },
  { key:'vision_scanner',         label:'QR / barcode scanner' },
  { key:'condition_analysis',     label:'Condition monitoring' },
  { key:'predictive_maintenance', label:'Predictive maintenance (meters)' },
  { key:'safety_loto',            label:'Safety & LOTO procedures' },
  { key:'work_orders',            label:'Work orders' },
  { key:'maintenance_plans',      label:'Preventive maintenance plans' },
  { key:'checklists',             label:'Checklists & inspections' },
  { key:'inventory',              label:'Spares & inventory' },
  { key:'procurement_requests',   label:'Procurement & material requests' },
  { key:'suppliers',              label:'Suppliers' },
  { key:'finance_labor',          label:'Financials (labour rates & costs)' },
  { key:'uploads',                label:'File uploads & manuals' },
  { key:'reports',                label:'Reports & exports' },
  { key:'people',                 label:'People, attendance & daily logs' },
  { key:'permits',                label:'Work permits' },
  { key:'incidents',              label:'Incident reporting' },
  { key:'support',                label:'In-app support & complaints' },
  { key:'white_label',            label:'Company profile & branding (own name, logo, colours, contact details)' }
];

function planFields(p = {}){
  const f = p.features || {};
  return [
    { heading:'Basics' },
    { name:'code', label:'Code (short, no spaces)', value:p.code||'', required:true, help:'Cannot be changed later. e.g. basic, pro, enterprise' },
    { name:'name', label:'Display name', value:p.name||'', required:true },
    { name:'description', label:'Description', type:'textarea', value:p.description||'' },

    { heading:'Price (PKR)' },
    { name:'monthly', label:'Monthly price', type:'number', step:'0.01', value:p.price_monthly??0 },
    { name:'yearly',  label:'Yearly price',  type:'number', step:'0.01', value:p.price_yearly??0 },

    { heading:'Limits' },
    { name:'workers',   label:'Max workers', type:'number', value:p.max_workers??0 },
    { name:'plants',    label:'Max plants',  type:'number', value:p.max_plants??0 },
    { name:'storage',   label:'Storage (GB)', type:'number', step:'0.1', value:+( (p.max_storage_bytes||0)/GB ).toFixed(2) },
    { name:'bandwidth', label:'Bandwidth per month (GB)', type:'number', step:'0.1', value:+( (p.max_bandwidth_bytes_month||0)/GB ).toFixed(2) },
    { name:'files',     label:'Max files', type:'number', value:p.max_files??0 },
    { name:'file_size', label:'Max single file size (MB)', type:'number', step:'0.1', value:+( (p.max_file_bytes||0)/MB ).toFixed(2) },
    { name:'retention', label:'Data retention (days)', type:'number', value:p.retention_days??0 },

    { heading:'AI limits' },
    { name:'ai_month',      label:'AI requests / month', type:'number', value:p.ai_requests_month??0 },
    { name:'ai_day',        label:'AI requests / day', type:'number', value:p.ai_requests_day??0 },
    { name:'ai_minute',     label:'AI requests / minute / user', type:'number', value:p.ai_requests_minute_user??0 },
    { name:'input_tokens',  label:'AI input tokens / month', type:'number', value:p.ai_input_tokens_month??0 },
    { name:'output_tokens', label:'AI output tokens / month', type:'number', value:p.ai_output_tokens_month??0 },

    { heading:'Modules included' },
    ...MODULES.map(m => ({ name:'mod_'+m.key, label:m.label, type:'checkbox', value:!!f[m.key] })),

    { heading:'Availability' },
    { name:'active', label:'Available to customers', type:'checkbox', value:p.active!==false }
  ];
}

async function savePlanFrom(d, existing = {}){
  const n = k => Number(d[k]) || 0;
  const features = Object.assign({}, existing.features || {});
  MODULES.forEach(m => { features[m.key] = !!d['mod_'+m.key]; });

  const { error } = await sb.rpc('control_save_plan', {
    p_code: d.code, p_name: d.name, p_description: d.description || '',
    p_price_monthly: n('monthly'), p_price_yearly: n('yearly'),
    p_max_workers: n('workers'), p_max_plants: n('plants'),
    p_storage: Math.round(n('storage') * GB),
    p_bandwidth: Math.round(n('bandwidth') * GB),
    p_max_files: n('files'),
    p_max_file: Math.round(n('file_size') * MB),
    p_ai_month: n('ai_month'), p_ai_day: n('ai_day'), p_ai_minute: n('ai_minute'),
    p_input_tokens: n('input_tokens'), p_output_tokens: n('output_tokens'),
    p_retention: n('retention'),
    p_features: features,
    p_active: d.active
  });
  if (error) throw error;
}

/* ============================================================
   FILES  (what the storage tile opens)
   ============================================================ */
async function pageFiles(orgId=''){
  view().innerHTML = head('Files','Everything customers have uploaded') + skeletons();

  const [{ data, error }, comps] = await Promise.all([
    sb.rpc('control_storage', { p_organization_id: orgId || null }),
    loadCompanyList()
  ]);
  if (error) throw error;
  const rows = data || [];
  const total = rows.reduce((s,f) => s + Number(f.size_bytes||0), 0);

  const byCompany = {};
  rows.forEach(f => {
    const k = f.company || 'Unknown';
    byCompany[k] = byCompany[k] || { n:0, b:0 };
    byCompany[k].n++; byCompany[k].b += Number(f.size_bytes||0);
  });

  const summary = Object.entries(byCompany)
    .sort((a,b) => b[1].b - a[1].b)
    .map(([name,v]) => rowLine(name, `${num(v.n)} files · ${bytes(v.b)}`)).join('');

  STORE.files = {};
  rows.forEach(f => { STORE.files[f.file_id] = f; });

  const list = rows.length ? rows.slice(0,150).map(f => `
    <article class="card">
      <div class="card-head"><h3 style="font-size:14.5px">${esc(f.file_name||'file')}</h3></div>
      <div class="card-body">
        ${rowLine('Company', esc(f.company||'—'))}
        ${rowLine('Size', bytes(f.size_bytes))}
        ${f.category?rowLine('Category', esc(f.category)):''}
        ${f.mime_type?rowLine('Type', esc(f.mime_type)):''}
        ${rowLine('Uploaded', fmtDate(f.created_at))}
        ${(f.uploader||f.uploaded_by)?rowLine('By', `<span class="break">${esc(f.uploader||f.uploaded_by)}</span>`):''}
      </div>
      <div class="actions">
        <button class="primary" data-act="openFile" data-id="${esc(f.file_id)}">Open</button>
        <button data-act="downloadFile" data-id="${esc(f.file_id)}">Download</button>
        <button class="danger" data-act="deleteFile" data-id="${esc(f.file_id)}">Delete</button>
      </div>
    </article>`).join('') : empty('No files uploaded yet.');

  view().innerHTML = head('Files','Everything customers have uploaded') + `
    <div class="toolbar">
      <select id="fileOrg">
        <option value="">All companies</option>
        ${comps.map(c=>`<option value="${esc(c.organization_id)}" ${c.organization_id===orgId?'selected':''}>${esc(c.name)}</option>`).join('')}
      </select>
    </div>
    <div class="stats" style="grid-template-columns:repeat(2,1fr)">
      <div class="stat"><div class="n">${num(rows.length)}</div><div class="l">Files</div></div>
      <div class="stat"><div class="n">${bytes(total)}</div><div class="l">Total size</div></div>
    </div>
    ${summary?`<div class="section-title">By company</div><div class="card"><div class="card-body">${summary}</div></div>`:''}
    <div class="section-title">Files${rows.length>150?' (newest 150)':''}</div>
    ${list}`;

  $('#fileOrg').onchange = e => safeRender(()=>pageFiles(e.target.value));
  bindActions();
}

/* The storage endpoints live in the platform-admin-api edge function,
   the same one the old panel used. */
async function adminApi(body){
  const r = await sb.functions.invoke('platform-admin-api', { body });
  if (r.error){
    let detail = '';
    try { detail = (await r.error.context?.json())?.error || ''; } catch {}
    throw new Error(detail || r.error.message);
  }
  if (r.data?.error) throw new Error(r.data.error);
  return r.data;
}

async function signedFileUrl(fileId){
  const r = await adminApi({ action:'storage_signed_url', file_id:fileId, reason:'' });
  const url = r?.url || r?.signed_url || r?.signedUrl;
  if (!url) throw new Error('The server did not return a link for this file.');
  return url;
}

function showFileLink(f, url, wantDownload){
  $('#modalRoot').innerHTML = `
    <div class="modal-backdrop">
      <div class="modal">
        <h3>${esc(f?.file_name || 'File')}</h3>
        <p>${esc(bytes(f?.size_bytes))}${f?.mime_type?' · '+esc(f.mime_type):''}</p>
        <p style="font-size:12.5px;color:var(--muted-2)">This preview window blocks automatic opening. Use the button below — press and hold it to choose “Download link”.</p>
        <div class="actions" style="border-top:0;padding-top:4px">
          <a class="btn primary" style="text-align:center;line-height:22px"
             href="${esc(url)}" target="_blank" rel="noopener"
             ${wantDownload?`download="${esc(f?.file_name||'file')}"`:''}>${wantDownload?'Download file':'Open file'}</a>
          <button class="ghost" id="flClose">Close</button>
        </div>
      </div>
    </div>`;
  $('#flClose').onclick = closeModal;
}

async function loadCompanyList(){
  if (Object.keys(STORE.companies).length) return Object.values(STORE.companies);
  const { data } = await sb.rpc('control_companies', { p_search:null, p_status:null });
  (data||[]).forEach(c => { STORE.companies[c.organization_id] = c; });
  return data || [];
}

/* ============================================================
   BACKUP  (download everything as PDF / CSV / Excel / Word)
   ============================================================ */
const BACKUP_SETS = [
  { key:'companies',    label:'Companies',        rpc:'control_companies', args:{p_search:null,p_status:null} },
  { key:'accounts',     label:'User accounts',    rpc:'control_accounts',  args:{p_search:null} },
  { key:'signup',       label:'Signup enquiries', table:'signup_requests' },
  { key:'invitations',  label:'Invitations',      table:'owner_invitations' },
  { key:'plans',        label:'Packages',         table:'subscription_plans' },
  { key:'tickets',      label:'Support tickets',  table:'platform_support_tickets' },
  { key:'audit',        label:'Admin activity log', table:'admin_action_logs' },
  { key:'files',        label:'File list',        rpc:'control_storage', args:{p_organization_id:null} }
];

function pageBackup(){
  view().innerHTML = head('Backup','Download a copy of your platform data') + `
    <div class="note-box">Everything is pulled live from Supabase and saved straight to your phone. Excel and Word open in Microsoft Office, Google Docs or WPS.</div>

    <div class="section-title">What to include</div>
    <div class="card" id="backupSets">
      ${BACKUP_SETS.map(s => `<label class="checkline">
        <input type="checkbox" name="set" value="${s.key}" checked><span>${esc(s.label)}</span></label>`).join('')}
    </div>

    <div class="section-title">Download as</div>
    <div class="card"><div class="actions tight">
      <button class="primary" data-act="backupExcel">Excel</button>
      <button data-act="backupCsv">CSV</button>
      <button data-act="backupWord">Word</button>
      <button data-act="backupPdf">PDF</button>
    </div></div>

    <div class="section-title">Full database copy</div>
    <div class="card">
      <div class="card-body">Supabase keeps automatic daily backups of the whole project, including customer files. Those are the ones to restore from if something serious goes wrong.</div>
      <div class="actions"><button class="block" data-act="openSupabaseBackups">Open Supabase backups</button></div>
    </div>`;
  bindActions();
}

function chosenSets(){
  const picked = $$('#backupSets input[name="set"]:checked').map(i => i.value);
  return BACKUP_SETS.filter(s => picked.includes(s.key));
}

async function collectBackup(){
  const sets = chosenSets();
  if (!sets.length){ toast('Tick at least one thing to include','bad'); return null; }
  toast('Collecting data…');
  const out = [];
  for (const s of sets){
    try {
      const r = s.rpc
        ? await sb.rpc(s.rpc, s.args)
        : await sb.from(s.table).select('*').limit(5000);
      if (r.error) throw r.error;
      out.push({ label:s.label, rows: r.data || [] });
    } catch (err){
      out.push({ label:s.label, rows:[], error: errText(err) });
    }
  }
  return out;
}

/* flatten nested values so a spreadsheet cell shows something useful */
const cell = v => {
  if (v == null) return '';
  if (Array.isArray(v)) return v.map(x =>
    typeof x === 'object' && x ? Object.values(x).join(' ') : String(x)).join('; ');
  if (typeof v === 'object') return JSON.stringify(v);
  return String(v);
};

function download(filename, content, mime){
  const blob = content instanceof Blob ? content : new Blob([content], { type: mime });
  const url = URL.createObjectURL(blob);

  const a = document.createElement('a');
  a.href = url; a.download = filename; a.rel = 'noopener';
  document.body.appendChild(a);
  a.click();
  a.remove();

  /* A sandboxed preview frame silently swallows the click above. Offer a
     visible link as well, so the file is always reachable. On the real
     site the download has already started and this is just a backup. */
  setTimeout(() => {
    $('#modalRoot').innerHTML = `
      <div class="modal-backdrop">
        <div class="modal">
          <h3>File ready</h3>
          <p><b>${esc(filename)}</b><br>${esc(bytes(blob.size))}</p>
          <p style="font-size:12.5px;color:var(--muted-2)">If your download did not start automatically, use the button below. Press and hold it to choose “Download link”.</p>
          <div class="actions" style="border-top:0;padding-top:4px">
            <a class="btn primary" style="text-align:center;line-height:22px"
               href="${url}" download="${esc(filename)}" id="dlLink">Download ${esc(filename.split('.').pop().toUpperCase())}</a>
            <button class="ghost" id="dlClose">Close</button>
          </div>
        </div>
      </div>`;
    $('#dlClose').onclick = () => { closeModal(); URL.revokeObjectURL(url); };
    $('#dlLink').onclick = () => setTimeout(closeModal, 1200);
  }, 350);
}

const stamp = () => new Date().toISOString().slice(0,10);

function toCsv(rows){
  if (!rows.length) return '';
  const cols = [...new Set(rows.flatMap(Object.keys))];
  const q = v => `"${cell(v).replace(/"/g,'""')}"`;
  return [cols.join(','), ...rows.map(r => cols.map(c => q(r[c])).join(','))].join('\r\n');
}

function tableHtml(rows){
  if (!rows.length) return '<p>No records.</p>';
  const cols = [...new Set(rows.flatMap(Object.keys))];
  return `<table border="1" cellspacing="0" cellpadding="5">
    <thead><tr>${cols.map(c=>`<th>${esc(c.replace(/_/g,' '))}</th>`).join('')}</tr></thead>
    <tbody>${rows.map(r=>`<tr>${cols.map(c=>`<td>${esc(cell(r[c]))}</td>`).join('')}</tr>`).join('')}</tbody>
  </table>`;
}

/* ============================================================
   SUPPORT / ACTIVITY
   ============================================================ */
const TICKET_OPEN = ['new','open','in_progress','pending','reopened'];
const ticketIsOpen = t => TICKET_OPEN.includes(String(t.status||'').toLowerCase());

async function pageSupport(filter='open'){
  view().innerHTML = head('Complaints','Tickets raised by customers') + skeletons();

  const { data, error } = await sb.from('platform_support_tickets')
    .select('*').order('created_at',{ascending:false}).limit(300);
  if (error) throw error;

  const all = data || [];
  STORE.tickets = {};
  all.forEach(t => { STORE.tickets[t.id] = t; });

  const openCount   = all.filter(ticketIsOpen).length;
  const closedCount = all.length - openCount;
  const rows = filter==='open'   ? all.filter(ticketIsOpen)
             : filter==='closed' ? all.filter(t => !ticketIsOpen(t))
             : all;

  const cards = rows.length ? rows.map(t => {
    const open = ticketIsOpen(t);
    return `<article class="card">
      <div class="card-head">
        <h3>${esc(t.subject||t.title||'Ticket')}</h3>
        ${badge(t.status)}
      </div>
      <div class="card-body">
        ${t.company_name?rowLine('Company', esc(t.company_name)):''}
        ${t.email?rowLine('From', `<span class="break">${esc(t.email)}</span>`):''}
        ${t.priority?rowLine('Priority', esc(t.priority)):''}
        ${rowLine('Opened', fmtDateTime(t.created_at))}
        ${(t.message||t.body)?`<div style="margin-top:8px;color:var(--muted)">${esc(t.message||t.body)}</div>`:''}
      </div>
      <div class="actions">
        ${open?`<button class="primary" data-act="resolveTicket" data-id="${esc(t.id)}">Mark resolved</button>`
              :`<button data-act="reopenTicket" data-id="${esc(t.id)}">Reopen</button>`}
        <button class="danger" data-act="deleteTicket" data-id="${esc(t.id)}">Delete</button>
      </div>
    </article>`;
  }).join('') : empty(filter==='open' ? 'No open complaints. Nice.' : 'Nothing here.');

  view().innerHTML = head('Complaints','Tickets raised by customers') + `
    <div class="toolbar">
      <button class="${filter==='open'?'primary':''}" data-act="ticketsOpen">Open (${openCount})</button>
      <button class="${filter==='closed'?'primary':''}" data-act="ticketsClosed">Closed (${closedCount})</button>
      <button class="${filter==='all'?'primary':''}" data-act="ticketsAll">All (${all.length})</button>
    </div>
    ${closedCount ? `<div class="card"><div class="actions tight">
        <button class="danger block" data-act="purgeTickets">Delete all ${closedCount} closed ${closedCount===1?'complaint':'complaints'}</button>
      </div></div>` : ''}
    ${cards}`;
  bindActions();
}

async function pageActivity(){
  view().innerHTML = head('Activity','Every administrative action, newest first') + skeletons();
  const { data, error } = await sb.from('admin_action_logs')
    .select('*').order('created_at',{ascending:false}).limit(100);
  if (error) throw error;
  const rows = data || [];
  view().innerHTML = head('Activity','Every administrative action, newest first') + (rows.length ? rows.map(l => `
    <article class="card">
      <div class="card-head"><h3 style="font-size:14.5px">${esc(String(l.action||'action').replace(/_/g,' '))}</h3></div>
      <div class="card-body">
        ${l.target_type?rowLine('Target', esc(l.target_type)):''}
        ${l.reason?rowLine('Reason', esc(l.reason)):''}
        ${rowLine('When', fmtDateTime(l.created_at))}
      </div>
    </article>`).join('') : empty('No activity recorded.'));
}

/* ============================================================
   MORE
   ============================================================ */
function pageMore(){
  view().innerHTML = head('More','Everything else') + `
    <div class="section-title">Manage</div>
    <div class="card"><div class="actions tight"><button class="block" data-act="goInvites">Invitations &amp; logins</button></div></div>
    <div class="card"><div class="actions tight"><button class="block" data-act="goPlans">Plans &amp; packages</button></div></div>
    <div class="card"><div class="actions tight"><button class="block" data-act="goFiles">Files &amp; storage</button></div></div>
    <div class="card"><div class="actions tight"><button class="block" data-act="goBackup">Backup &amp; download</button></div></div>
    <div class="card"><div class="actions tight"><button class="block" data-act="goSupport">Support tickets</button></div></div>
    <div class="card"><div class="actions tight"><button class="block" data-act="goActivity">Activity log</button></div></div>

    <div class="section-title">Your account</div>
    <div class="card">
      <div class="card-body">
        ${rowLine('Email', `<span class="break">${esc(user.email)}</span>`)}
        ${rowLine('Role', esc(admin.admin_role||'—'))}
        ${rowLine('Customer app', `<a href="${CUSTOMER_APP_URL}" target="_blank" rel="noopener">${esc(CUSTOMER_APP_URL.replace('https://',''))}</a>`)}
      </div>
      <div class="actions"><button class="block" data-act="changePassword">Change my password</button></div>
    </div>
    <div class="card"><div class="actions tight"><button class="danger block" data-act="logout">Sign out</button></div></div>`;
  bindActions();
}

/* ============================================================
   ACTIONS
   ============================================================ */
const ACTIONS = {
  reloadPage : () => navigate(route),
  goRequests : () => navigate('requests'),
  goCompanies: () => navigate('companies'),
  goAccounts : () => navigate('accounts'),
  goFiles    : () => navigate('files'),
  goBackup   : () => navigate('backup'),
  filterActive   : () => safeRender(()=>pageCompanies('','active')),
  filterTrial    : () => safeRender(()=>pageCompanies('','trial')),
  filterPastDue  : () => safeRender(()=>pageCompanies('','past_due')),
  filterSuspended: () => safeRender(()=>pageCompanies('','suspended')),
  goInvites  : () => navigate('invites'),
  goPlans    : () => navigate('plans'),
  goSupport  : () => navigate('support'),
  goActivity : () => navigate('activity'),
  reqPending : () => safeRender(()=>pageRequests('pending')),
  reqAll     : () => safeRender(()=>pageRequests('all')),

  /* ---------- approvals ---------- */
  async approveRequest(d){
    const r = STORE.requests[d.id];
    if (!r) return toast('Enquiry not found — pull to refresh','bad');
    const plans = await loadPlans();
    let created = false;

    await openForm({
      title: 'Approve and create login',
      intro: `Approves <b>${esc(r.company_name||'')}</b> and creates the owner login for <b>${esc(r.email||'')}</b> in one step.`,
      submitLabel: 'Approve & create login',
      fields: [
        { name:'email',   label:'Owner email', type:'email', value:r.email||'', required:true },
        { name:'company', label:'Company name', value:r.company_name||'', required:true },
        { name:'plant',   label:'First plant name', value:'Main Plant' },
        { name:'plan',    label:'Package', type:'select',
          value: plans.some(p=>p.code==='trial') ? 'trial' : (plans[0]?.code||''),
          options: plans.length ? plans.map(p=>({value:p.code,label:p.name||p.code})) : ['trial'] },
        { name:'days',    label:'Trial days (0 for none)', type:'number', value:'14' },
        { name:'notes',   label:'Notes', type:'textarea', placeholder:'What was agreed' }
      ],
      onSubmit: async f => {
        const { data:inv, error } = await sb.rpc('control_invite_owner', {
          p_email:f.email, p_company_name:f.company,
          p_plant_name:f.plant||'Main Plant', p_plan_code:f.plan,
          p_trial_days:Number(f.days||0), p_request_id:d.id, p_notes:f.notes||null
        });
        if (error) throw error;
        created = true;

        /* Mark the enquiry approved so it leaves the pending queue.
           control_invite_owner does not always do this, which is why an
           approved company kept showing as still waiting. */
        await sb.from('signup_requests')
          .update({ status:'approved', reviewed_at:new Date().toISOString() })
          .eq('id', d.id);

        const invId = inv?.id || (Array.isArray(inv) ? inv[0]?.id : null);
        try { await createOwnerLogin(f.email, invId); }
        catch (err){
          throw new Error(errText(err) +
            ' — the company WAS approved. Open More > Invitations and tap "Create login & password" to finish.');
        }
      }
    });
    if (created) await safeRender(()=>pageRequests('pending'));
  },

  async rejectRequest(d){
    if (!await confirmAction('Reject enquiry',
      'They will not be able to open an account. You can approve or delete it later.','Reject')) return;
    const { error } = await sb.from('signup_requests')
      .update({ status:'rejected', reviewed_at:new Date().toISOString() }).eq('id', d.id);
    if (error) throw error;
    toast('Enquiry rejected');
    await safeRender(()=>pageRequests('pending'));
  },

  async deleteRequest(d){
    const r = STORE.requests[d.id] || {};
    if (!await confirmDelete('Delete enquiry',
      `Permanently delete the enquiry from <b>${esc(r.company_name||'this company')}</b>.`)) return;
    const { data, error } = await sb.rpc('control_delete_signup_request', { p_id: d.id });
    if (error) throw error;
    if (data === false) throw new Error('The database refused the delete.');
    toast('Enquiry deleted');
    await safeRender(()=>pageRequests('all'));
  },

  async purgeRejected(){
    if (!await confirmDelete('Purge rejected','Permanently delete every rejected enquiry.','Delete all')) return;
    const { data, error } = await sb.rpc('control_purge_signup_requests', { p_status:'rejected' });
    if (error) throw error;
    toast(`Deleted ${data ?? 0} rejected ${Number(data)===1?'enquiry':'enquiries'}`);
    await safeRender(()=>pageRequests('all'));
  },

  /* ---------- invitations ---------- */
  async inviteOwner(){
    const plans = await loadPlans();
    let done = false;
    await openForm({
      title: 'Invite an owner',
      intro: 'Creates the invitation and the login together. Only this email can open this workspace, once.',
      submitLabel: 'Create invitation & login',
      fields: [
        { name:'email',   label:'Owner email', type:'email', required:true },
        { name:'company', label:'Company name', required:true },
        { name:'plant',   label:'First plant name', value:'Main Plant' },
        { name:'plan',    label:'Package', type:'select',
          value: plans.some(p=>p.code==='trial') ? 'trial' : (plans[0]?.code||''),
          options: plans.length ? plans.map(p=>({value:p.code,label:p.name||p.code})) : ['trial'] },
        { name:'days',    label:'Trial days (0 for none)', type:'number', value:'14' },
        { name:'notes',   label:'Notes', type:'textarea', placeholder:'Who they are, what was agreed' }
      ],
      onSubmit: async f => {
        const { data:inv, error } = await sb.rpc('control_invite_owner', {
          p_email:f.email, p_company_name:f.company,
          p_plant_name:f.plant||'Main Plant', p_plan_code:f.plan,
          p_trial_days:Number(f.days||0), p_request_id:null, p_notes:f.notes||null
        });
        if (error) throw error;
        done = true;
        const invId = inv?.id || (Array.isArray(inv) ? inv[0]?.id : null);
        try { await createOwnerLogin(f.email, invId); }
        catch (err){
          throw new Error(errText(err) +
            ' — the invitation WAS created. Tap "Create login & password" on it below to finish.');
        }
      }
    });
    if (done) await safeRender(()=>pageInvites());
  },

  /* Generate the Supabase login for an existing invitation. */
  async createLogin(d){
    const inv = STORE.invites[d.id];
    if (!inv) return toast('Invitation not found — refresh the page','bad');
    await createOwnerLogin(inv.email, inv.id);
    await safeRender(()=>pageInvites());
  },

  async revokeInvite(d){
    if (!await confirmAction('Revoke invitation',
      'They will no longer be able to open the workspace.','Revoke')) return;
    const { error } = await sb.rpc('control_revoke_owner_invitation', { p_id: d.id });
    if (error) throw error;
    toast('Invitation revoked');
    await safeRender(()=>pageInvites());
  },

  async deleteInvite(d){
    if (!await confirmDelete('Delete invitation','Removes this invitation record permanently.')) return;
    const { error } = await sb.rpc('control_delete_owner_invitation', { p_id: d.id });
    if (error) throw error;
    toast('Invitation deleted');
    await safeRender(()=>pageInvites());
  },

  async cleanupInvites(){
    const dead = Object.values(STORE.invites).filter(x => ['revoked','expired'].includes(inviteState(x)));
    if (!dead.length) return toast('Nothing to clean up');
    if (!await confirmDelete('Clear invitations',
      `Delete ${dead.length} revoked or expired ${dead.length===1?'invitation':'invitations'}.`,'Delete all')) return;
    let ok=0, bad=0;
    for (const x of dead){
      const { error } = await sb.rpc('control_delete_owner_invitation', { p_id: x.id });
      error ? bad++ : ok++;
    }
    toast(bad ? `Deleted ${ok}, ${bad} failed` : `Deleted ${ok}`, bad ? 'bad' : 'ok');
    await safeRender(()=>pageInvites());
  },

  /* ---------- companies ---------- */
  /* One company's package: switch package AND add extras for
     just them. Editing in Packages changes every customer;
     the extras here change only this one. */
  async editCompanyPlan(d){
    const c = STORE.companies[d.id];
    if (!c) return toast('Company not found — refresh','bad');
    const plans = await loadPlans();
    const base = plans.find(p => p.code === c.plan_code) || {};
    const baseFeat = base.features || {};

    const [{ data: ov }, { data: blocks }, grantsRes] = await Promise.all([
      sb.from('quota_overrides').select('*').eq('organization_id', d.id),
      sb.from('company_feature_blocks').select('*').eq('organization_id', d.id),
      sb.from('company_feature_grants').select('*').eq('organization_id', d.id)
    ]);
    /* Grants are the newer half. If script 10 has not been run the
       table is missing — carry on rather than break the editor. */
    const grantsMissing = !!grantsRes.error;
    const granted = {};
    (grantsRes.data||[]).forEach(g => { if (g.granted !== false) granted[g.feature] = true; });

    const extras = {};
    (ov||[]).forEach(o => {
      if (o.override_type === 'bonus') extras[o.metric] = (extras[o.metric]||0) + Number(o.value||0);
    });
    const blocked = {};
    (blocks||[]).forEach(b => { if (b.blocked) blocked[b.feature] = true; });

    const cur = (metric, planValue) => {
      const bonus = extras[metric] || 0;
      return bonus ? `${num(planValue)} + ${num(bonus)} extra` : num(planValue);
    };

    await openForm({
      title: `${c.name}`,
      intro: `Everything here affects <b>${esc(c.name)}</b> only. Changing a package in More &gt; Plans &amp; packages affects every customer on it.`
        + (grantsMissing ? `<br><b style="color:#f5a524">Run 10-COMPANY-FEATURES.sql in Supabase to enable adding modules per company. Until then you can only remove them.</b>` : ''),
      submitLabel: 'Save',
      fields: [
        { heading:'Package' },
        { name:'plan', label:'Package', type:'select', value:c.plan_code||'',
          options: plans.map(p => ({
            value:p.code,
            label:`${p.name||p.code}${p.price_monthly?` — PKR ${num(p.price_monthly)}/mo`:' — free'}`
          })),
          help:`Currently ${base.name||c.plan_code||'none'}` },

        { heading:'Extra allowance for this company' },
        { name:'x_workers', label:'Extra workers', type:'number', value:0,
          help:`Package gives ${cur('workers', base.max_workers||0)}` },
        { name:'x_plants', label:'Extra plants', type:'number', value:0,
          help:`Package gives ${cur('plants', base.max_plants||0)}` },
        { name:'x_storage', label:'Extra storage (GB)', type:'number', step:'0.1', value:0,
          help:`Package gives ${bytes(base.max_storage_bytes)}` },
        { name:'x_ai', label:'Extra AI requests / month', type:'number', value:0,
          help:`Package gives ${cur('ai_requests', base.ai_requests_month||0)}` },

        { heading:'Modules for this company' },
        { note:'Tick to give this company a module their package does not include. Untick to take away one it does. Either way it affects <b>this company only</b> — the package itself is unchanged.' },
        ...MODULES.map(m => ({
          name:'mod_'+m.key,
          label: m.label + (baseFeat[m.key] ? '' : (granted[m.key] ? '  — extra for this company' : '  — not in their package')),
          type:'checkbox',
          value: granted[m.key] ? true : (baseFeat[m.key] ? !blocked[m.key] : false)
        })),

        { heading:'Reason' },
        { name:'reason', label:'Saved to the audit log', required:true, value:'Agreed with customer' }
      ],
      onSubmit: async f => {
        if (f.plan && f.plan !== c.plan_code){
          const { error } = await sb.rpc('platform_set_company', {
            p_organization_id: d.id, p_status: c.status,
            p_plan_code: f.plan, p_reason: f.reason
          });
          if (error) throw error;
        }

        const adds = [
          ['workers',      Number(f.x_workers)||0],
          ['plants',       Number(f.x_plants)||0],
          ['storage_bytes',Math.round((Number(f.x_storage)||0) * GB)],
          ['ai_requests',  Number(f.x_ai)||0]
        ].filter(([,v]) => v > 0);

        for (const [metric, value] of adds){
          const { error } = await sb.from('quota_overrides').insert({
            organization_id: d.id, metric, override_type:'bonus',
            value, reason: f.reason, created_by: user.id
          });
          if (error) throw new Error(`Could not add extra ${metric}: ${errText(error)}`);
        }

        /* Four cases per module, for THIS company only:
             in package + unticked  -> write a block
             in package + re-ticked -> remove the block
             not in package + ticked   -> write a grant
             not in package + unticked -> remove the grant   */
        for (const m of MODULES){
          const wants     = !!f['mod_'+m.key];
          const inPlan    = !!baseFeat[m.key];
          const isBlocked = !!blocked[m.key];
          const isGranted = !!granted[m.key];

          if (inPlan){
            if (!wants && !isBlocked){
              const { error } = await sb.from('company_feature_blocks').upsert({
                organization_id: d.id, feature: m.key, blocked: true,
                reason: f.reason, blocked_by: user.id,
                updated_at: new Date().toISOString()
              });
              if (error) throw new Error(`Could not turn off ${m.label}: ${errText(error)}`);
            }
            if (wants && isBlocked){
              const { error } = await sb.from('company_feature_blocks')
                .delete().eq('organization_id', d.id).eq('feature', m.key);
              if (error) throw new Error(`Could not turn on ${m.label}: ${errText(error)}`);
            }
            /* A module back in the package no longer needs a grant. */
            if (isGranted && !grantsMissing){
              await sb.from('company_feature_grants')
                .delete().eq('organization_id', d.id).eq('feature', m.key);
            }
          } else {
            if (wants && !isGranted){
              if (grantsMissing) throw new Error('Run 10-COMPANY-FEATURES.sql in Supabase before adding modules per company.');
              const { error } = await sb.from('company_feature_grants').upsert({
                organization_id: d.id, feature: m.key, granted: true,
                reason: f.reason, granted_by: user.id,
                updated_at: new Date().toISOString()
              });
              if (error) throw new Error(`Could not add ${m.label}: ${errText(error)}`);
            }
            if (!wants && isGranted && !grantsMissing){
              const { error } = await sb.from('company_feature_grants')
                .delete().eq('organization_id', d.id).eq('feature', m.key);
              if (error) throw new Error(`Could not remove ${m.label}: ${errText(error)}`);
            }
          }
        }
      }
    });
    toast('Company updated');
    await safeRender(()=>pageCompanies());
  },

  async changeStatus(d){
    const c = STORE.companies[d.id];
    if (!c) return toast('Company not found — refresh','bad');

    await openForm({
      title: 'Change status',
      intro: `<b>${esc(c.name)}</b> is currently <b>${esc(c.status||'unknown')}</b>. Suspending blocks everyone in the company from signing in.`,
      submitLabel: 'Apply status',
      fields: [
        { name:'status', label:'New status', type:'select', value:c.status||'active',
          options:['trial','active','past_due','suspended','cancelled','deletion_pending']
            .map(s=>({value:s,label:s.replace(/_/g,' ')})) },
        { name:'reason', label:'Reason (saved to the audit log)', value:'Status changed by administrator' }
      ],
      onSubmit: async f => {
        const { error } = await sb.rpc('platform_set_company', {
          p_organization_id: d.id,
          p_status: f.status,
          p_plan_code: c.plan_code,
          p_reason: f.reason || 'Status changed by administrator'
        });
        if (error) throw error;
      }
    });
    toast('Status changed');
    await safeRender(()=>pageCompanies());
  },

  async freeAccess(d){
    const c = STORE.companies[d.id] || {};
    await openForm({
      title: 'Grant free access',
      intro: `Gives <b>${esc(c.name||'this company')}</b> complimentary access with no billing.`,
      submitLabel: 'Grant',
      fields: [
        { name:'type',   label:'Access type', type:'select', value:'complimentary',
          options:['complimentary','internal','partner'] },
        { name:'ends',   label:'Ends on (leave blank = permanent)', type:'date' },
        { name:'reason', label:'Reason', type:'textarea', required:true },
        { name:'never',  label:'Never auto-suspend for billing', type:'checkbox', value:true }
      ],
      onSubmit: async f => {
        const { error } = await sb.rpc('control_set_complimentary', {
          p_organization_id: d.id, p_access_type: f.type,
          p_ends_at: f.ends || null, p_reason: f.reason, p_never_suspend: f.never
        });
        if (error) throw error;
      }
    });
    toast('Free access granted');
    await safeRender(()=>pageCompanies());
  },

  async deleteCompany(d){
    const c = STORE.companies[d.id];
    if (!c) return toast('Company not found — refresh the page','bad');
    if (!await confirmDelete('Delete company',
      `This permanently deletes <b>${esc(c.name)}</b> and ALL of its assets, work orders, spares, purchase orders and files.`,
      'Delete company')) return;
    /* The exact stored name is sent, never anything retyped. */
    const { error } = await sb.rpc('control_delete_company', { p_org: d.id, p_confirmation: c.name });
    if (error) return showError(`Could not delete ${c.name}`, explainDbError(errText(error)));
    toast('Company deleted');
    plansCache = [];
    await safeRender(()=>pageCompanies());
  },

  /* ---------- accounts ---------- */
  async deleteUser(d){
    const a = STORE.accounts[d.id] || {};
    const owns = (a.companies||[]).filter(c => String(c.role||'').toLowerCase()==='owner');
    const warn = owns.length
      ? `<br><br><b style="color:var(--warn)">This person owns ${owns.map(c=>esc(c.company)).join(', ')}.</b> Deleting them does not delete the company — but a company with no owner cannot be managed by anyone.`
      : '';

    if (!await confirmDelete('Delete user account',
      `Permanently deletes the login for <b>${esc(a.email||'this user')}</b>.${warn}`,
      'Delete user')) return;

    const { error } = await sb.rpc('platform_delete_user', {
      p_user_id: d.id, p_reason: 'Platform Admin override'
    });

    if (error){
      const raw = errText(error);

      /* Last owner of a company: offer to remove the company too,
         rather than leaving you stuck at a dead end. */
      if (/last owner|only owner|owner of/i.test(raw) && owns.length){
        const go = await confirmAction('This person owns a company',
          `${esc(a.email)} is the only owner of <b>${owns.map(c=>esc(c.company)).join(', ')}</b>.<br><br>Delete the ${owns.length===1?'company':'companies'} as well? This removes all of their data, then removes the login.`,
          'Delete company and user');
        if (!go) return;

        for (const c of owns){
          const org = Object.values(STORE.companies).find(x => x.name === c.company);
          if (!org){
            return showError('Could not find the company',
              `Open the Companies tab, delete "${c.company}" there, then delete this user.`);
          }
          const r = await sb.rpc('control_delete_company',
            { p_org: org.organization_id, p_confirmation: org.name });
          if (r.error) return showError(`Could not delete ${c.company}`, explainDbError(errText(r.error)));
        }

        const again = await sb.rpc('platform_delete_user', {
          p_user_id: d.id, p_reason: 'Platform Admin override'
        });
        if (again.error) return showError('Could not delete user', explainDbError(errText(again.error)));

        toast('Company and user deleted');
        plansCache = [];
        await safeRender(()=>pageAccounts());
        return;
      }

      return showError('Could not delete user', explainDbError(raw));
    }

    toast('User permanently deleted');
    await safeRender(()=>pageAccounts());
  },

  async banUser(d){
    if (!await confirmAction('Suspend user',
      'They will be signed out and blocked from signing in.','Suspend')) return;
    const { error } = await sb.rpc('platform_ban_user', {
      p_user_id: d.id, p_reason:'Platform Admin override', p_ban:true
    });
    if (error) throw error;
    toast('User suspended');
    await safeRender(()=>pageAccounts());
  },

  async unbanUser(d){
    const { error } = await sb.rpc('platform_ban_user', {
      p_user_id: d.id, p_reason:'Platform Admin override', p_ban:false
    });
    if (error) throw error;
    toast('User access restored');
    await safeRender(()=>pageAccounts());
  },

  async resetPassword(d){
    const a = STORE.accounts[d.id] || {};
    if (!a.email) return toast('No email on this account','bad');
    const { error } = await sb.auth.resetPasswordForEmail(a.email, { redirectTo: CUSTOMER_APP_URL + '/index.html' });
    if (error) throw error;
    toast('Reset email sent to ' + a.email);
  },

  /* ---------- plans ---------- */
  async newPlan(){
    await openForm({
      title:'New package', submitLabel:'Create package',
      fields: planFields({ active:true }),
      onSubmit: d => savePlanFrom(d)
    });
    toast('Package created');
    await safeRender(pagePlans);
  },

  async editPlan(d){
    const p = STORE.plans[d.code];
    if (!p) return toast('Package not found — refresh','bad');
    await openForm({
      title:'Edit '+(p.name||p.code), submitLabel:'Save package',
      fields: planFields(p),
      onSubmit: x => savePlanFrom(x, p)
    });
    toast('Package saved');
    await safeRender(pagePlans);
  },

  async togglePlan(d){
    const p = STORE.plans[d.code];
    if (!p) return toast('Package not found','bad');
    const turningOff = p.active !== false;
    if (turningOff && !await confirmAction('Deactivate package',
      'New customers will not be offered this package. Existing customers keep it.','Deactivate')) return;
    const f = p.features || {};
    /* savePlanFrom rebuilds features from the mod_<key> fields, so we must
       supply one per module or every module is silently wiped when a package
       is toggled. Carry the plan's current features across unchanged; only
       `active` changes here. */
    const fields = {
      code:p.code, name:p.name, description:p.description||'',
      monthly:p.price_monthly, yearly:p.price_yearly,
      workers:p.max_workers, plants:p.max_plants,
      storage:(p.max_storage_bytes||0)/GB, bandwidth:(p.max_bandwidth_bytes_month||0)/GB,
      files:p.max_files, file_size:(p.max_file_bytes||0)/MB, retention:p.retention_days,
      ai_month:p.ai_requests_month, ai_day:p.ai_requests_day, ai_minute:p.ai_requests_minute_user,
      input_tokens:p.ai_input_tokens_month, output_tokens:p.ai_output_tokens_month,
      active: !turningOff
    };
    MODULES.forEach(m => { fields['mod_'+m.key] = !!f[m.key]; });
    await savePlanFrom(fields, p);
    toast(turningOff ? 'Package deactivated' : 'Package activated');
    await safeRender(pagePlans);
  },

  /* ---------- account ---------- */
  async changePassword(){
    await openForm({
      title:'Change your password', submitLabel:'Save password',
      fields:[{ name:'pw', label:'New password (min 8 characters)', type:'password', required:true }],
      onSubmit: async f => {
        if (f.pw.length < 8) throw new Error('Password must be at least 8 characters.');
        const { error } = await sb.auth.updateUser({ password: f.pw });
        if (error) throw error;
      }
    });
    toast('Password changed');
  },

  /* ---------- complaints ---------- */
  ticketsOpen  : () => safeRender(()=>pageSupport('open')),
  ticketsClosed: () => safeRender(()=>pageSupport('closed')),
  ticketsAll   : () => safeRender(()=>pageSupport('all')),

  async resolveTicket(d){
    const { error } = await sb.from('platform_support_tickets')
      .update({ status:'resolved', resolved_at:new Date().toISOString() }).eq('id', d.id);
    if (error) return showError('Could not update the complaint', explainDbError(errText(error)));
    toast('Marked resolved');
    await safeRender(()=>pageSupport('open'));
  },

  async reopenTicket(d){
    const { error } = await sb.from('platform_support_tickets')
      .update({ status:'open', resolved_at:null }).eq('id', d.id);
    if (error) return showError('Could not reopen the complaint', explainDbError(errText(error)));
    toast('Complaint reopened');
    await safeRender(()=>pageSupport('open'));
  },

  async deleteTicket(d){
    const t = STORE.tickets[d.id] || {};
    if (!await confirmDelete('Delete complaint',
      `Permanently deletes <b>${esc(t.subject||t.title||'this complaint')}</b> and its messages.`)) return;

    await deleteTicketMessages([d.id]);

    const { error } = await sb.from('platform_support_tickets').delete().eq('id', d.id);
    if (error) return showError('Could not delete the complaint', explainDbError(errText(error)));
    toast('Complaint deleted');
    await safeRender(()=>pageSupport('all'));
  },

  async purgeTickets(){
    const closed = Object.values(STORE.tickets).filter(t => !ticketIsOpen(t));
    if (!closed.length) return toast('Nothing to delete');
    if (!await confirmDelete('Delete closed complaints',
      `Permanently deletes all ${closed.length} closed ${closed.length===1?'complaint':'complaints'}. Open ones are kept.`,
      'Delete all')) return;

    const ids = closed.map(t => t.id);
    await deleteTicketMessages(ids);
    const { error } = await sb.from('platform_support_tickets').delete().in('id', ids);
    if (error) return showError('Could not delete the complaints', explainDbError(errText(error)));
    toast(`Deleted ${ids.length} complaints`);
    await safeRender(()=>pageSupport('all'));
  },

  /* ---------- files ---------- */
  async openFile(d){
    const url = await signedFileUrl(d.id);
    const w = window.open(url, '_blank', 'noopener');
    if (w) return;
    try { window.top.location.href = url; return; } catch {}
    showFileLink(STORE.files[d.id], url, false);
  },

  async downloadFile(d){
    const f = STORE.files[d.id] || {};
    const url = await signedFileUrl(d.id);
    /* Fetch through the app so the browser saves it with the right
       name instead of opening the PDF in a viewer tab. */
    try {
      const res = await fetch(url);
      if (!res.ok) throw new Error('download failed');
      download(f.file_name || 'file', await res.blob(), f.mime_type || 'application/octet-stream');
    } catch {
      showFileLink(f, url, true);
    }
  },

  async deleteFile(d){
    const f = STORE.files[d.id] || {};
    if (!await confirmDelete('Delete file',
      `Permanently removes <b>${esc(f.file_name||'this file')}</b> from storage.`)) return;
    await adminApi({ action:'storage_delete', file_id:d.id,
                     reason:'Platform administrator action', confirmation:'DELETE FILE' });
    toast('File deleted');
    await safeRender(()=>pageFiles());
  },

  /* ---------- backup exports ---------- */
  async backupCsv(){
    const data = await collectBackup();
    if (!data) return;
    /* One file per section, joined with a clear separator so a single
       download still opens cleanly in any spreadsheet. */
    const parts = data.map(s =>
      `"${s.label}"\r\n` + (s.error ? `"Could not read: ${s.error}"` : toCsv(s.rows)));
    download(`plantmaster-backup-${stamp()}.csv`, '\uFEFF' + parts.join('\r\n\r\n\r\n'), 'text/csv;charset=utf-8');
    toast('CSV saved to your downloads');
  },

  async backupExcel(){
    const data = await collectBackup();
    if (!data) return;
    /* Excel opens an HTML workbook with one worksheet per section. */
    const sheets = data.map(s => `
      <table><tr><td colspan="99"><b>${esc(s.label)}</b></td></tr></table>
      ${s.error ? `<p>Could not read: ${esc(s.error)}</p>` : tableHtml(s.rows)}
      <br><br>`).join('');
    const html = `<html xmlns:x="urn:schemas-microsoft-com:office:excel">
      <head><meta charset="utf-8">
      <style>table{border-collapse:collapse;font-family:Arial;font-size:11pt}
      th{background:#15181c;color:#fff;text-align:left}</style></head>
      <body><h2>PlantMaster backup — ${stamp()}</h2>${sheets}</body></html>`;
    download(`plantmaster-backup-${stamp()}.xls`, '\uFEFF'+html, 'application/vnd.ms-excel');
    toast('Excel file saved to your downloads');
  },

  async backupWord(){
    const data = await collectBackup();
    if (!data) return;
    const body = data.map(s => `
      <h2>${esc(s.label)}</h2>
      ${s.error ? `<p>Could not read: ${esc(s.error)}</p>`
                : `<p>${num(s.rows.length)} records</p>${tableHtml(s.rows)}`}
      <br style="page-break-after:always">`).join('');
    const html = `<html xmlns:w="urn:schemas-microsoft-com:office:word">
      <head><meta charset="utf-8"><title>PlantMaster backup</title>
      <style>body{font-family:Arial;font-size:10pt}
      table{border-collapse:collapse;width:100%;font-size:8pt}
      th{background:#eee;text-align:left}h1{font-size:16pt}h2{font-size:13pt}</style></head>
      <body><h1>PlantMaster Control Center backup</h1>
      <p>HSB Fix Services · ${new Date().toLocaleString('en-GB')}</p>${body}</body></html>`;
    download(`plantmaster-backup-${stamp()}.doc`, '\uFEFF'+html, 'application/msword');
    toast('Word file saved to your downloads');
  },

  async backupPdf(){
    const data = await collectBackup();
    if (!data) return;

    let jsPDF;
    try {
      toast('Building PDF…');
      const mod = await import('https://cdn.jsdelivr.net/npm/jspdf@2.5.2/+esm');
      jsPDF = mod.jsPDF || mod.default?.jsPDF || mod.default;
      if (!jsPDF) throw new Error('no export');
    } catch {
      return toast('Could not load the PDF builder — check your connection', 'bad');
    }

    const doc = new jsPDF({ orientation:'landscape', unit:'pt', format:'a4' });
    const W = doc.internal.pageSize.getWidth();
    const H = doc.internal.pageSize.getHeight();
    const M = 28;
    let y = M;

    const newPage = () => { doc.addPage(); y = M; };
    const room = need => { if (y + need > H - M) newPage(); };

    doc.setFontSize(17); doc.setFont(undefined,'bold');
    doc.text('PlantMaster Control Center — Backup', M, y); y += 19;
    doc.setFontSize(9.5); doc.setFont(undefined,'normal'); doc.setTextColor(90);
    doc.text(`HSB Fix Services · ${new Date().toLocaleString('en-GB')}`, M, y); y += 20;
    doc.setTextColor(0);

    for (const sec of data){
      room(56);
      doc.setFontSize(12.5); doc.setFont(undefined,'bold');
      doc.text(sec.label, M, y); y += 5;
      doc.setDrawColor(190); doc.line(M, y, W - M, y); y += 13;
      doc.setFont(undefined,'normal'); doc.setFontSize(8);

      if (sec.error){
        doc.setTextColor(180,40,40);
        doc.text(`Could not read: ${sec.error}`, M, y);
        doc.setTextColor(0); y += 22; continue;
      }
      if (!sec.rows.length){
        doc.setTextColor(120); doc.text('No records.', M, y);
        doc.setTextColor(0); y += 22; continue;
      }

      /* Up to 7 columns, skipping ones that are empty everywhere. */
      const all = [...new Set(sec.rows.flatMap(Object.keys))];
      const cols = all.filter(c => sec.rows.some(r => cell(r[c]) !== '')).slice(0, 7);
      const cw = (W - M*2) / cols.length;

      const fit = (txt, width) => {
        let t = String(txt).replace(/\s+/g,' ');
        while (t && doc.getTextWidth(t) > width - 6) t = t.slice(0, -2);
        return t;
      };

      const header = () => {
        doc.setFillColor(238); doc.rect(M, y - 9, W - M*2, 15, 'F');
        doc.setFont(undefined,'bold');
        cols.forEach((c,i) => doc.text(fit(c.replace(/_/g,' '), cw), M + i*cw + 3, y));
        doc.setFont(undefined,'normal'); y += 15;
      };
      header();

      for (const r of sec.rows){
        if (y > H - M - 12){ newPage(); doc.setFontSize(8); header(); }
        cols.forEach((c,i) => doc.text(fit(cell(r[c]), cw), M + i*cw + 3, y));
        y += 11.5;
      }
      y += 16;
    }

    const pages = doc.internal.getNumberOfPages();
    for (let i = 1; i <= pages; i++){
      doc.setPage(i); doc.setFontSize(7.5); doc.setTextColor(140);
      doc.text(`Page ${i} of ${pages}`, W - M, H - 14, { align:'right' });
    }

    download(`plantmaster-backup-${stamp()}.pdf`, doc.output('blob'), 'application/pdf');
    toast('PDF saved to your downloads');
  },

  openSupabaseBackups(){
    const url = 'https://supabase.com/dashboard/project/dpmmenwziplixrgylapy/database/backups/scheduled';
    const w = window.open(url, '_blank', 'noopener');
    if (!w) { try { window.top.location.href = url; } catch { location.href = url; } }
  },

  logout: () => sb.auth.signOut()
};

/* ============================================================
   CREATE OWNER LOGIN
   ============================================================ */
async function createOwnerLogin(email, invitationId){
  const { data:{ session } } = await sb.auth.getSession();
  const res = await fetch(`${SUPABASE_URL}/functions/v1/create-owner`, {
    method:'POST',
    headers:{ 'Content-Type':'application/json', apikey:SUPABASE_ANON_KEY,
              Authorization:`Bearer ${session?.access_token || ''}` },
    body: JSON.stringify({ email, invitation_id: invitationId || null })
  });
  const out = await res.json().catch(()=>({ error:`create-owner returned ${res.status}` }));
  if (!res.ok || out.error) throw new Error(out.error || `create-owner returned ${res.status}`);

  const appUrl = out.app_url || CUSTOMER_APP_URL;
  const mail   = out.email || email;
  const msg = out.password
    ? `Your PlantMaster account is ready.\n\nSign in: ${appUrl}\nEmail: ${mail}\nTemporary password: ${out.password}\n\nPlease change your password after signing in.`
    : `An account for ${mail} already exists. Sign in at ${appUrl}, or ask for a password reset.`;

  showCredentials(mail, out.password, appUrl, msg);
}

function showCredentials(email, password, appUrl, msg){
  $('#modalRoot').innerHTML = `
    <div class="modal-backdrop">
      <div class="modal">
        <h3>Login created</h3>
        <p>${password
          ? 'Send these details to the owner. <b>The password is shown only once</b> — save it now.'
          : 'This person already had an account.'}</p>
        <div class="card" style="margin-bottom:10px"><div class="card-body">
          ${rowLine('Sign in at', `<span class="break">${esc(appUrl)}</span>`)}
          ${rowLine('Email', `<span class="break">${esc(email||'')}</span>`)}
          ${rowLine('Password', `<b class="mono break" style="color:var(--brand);font-size:15px">${esc(password||'unchanged — use Reset password')}</b>`)}
        </div></div>

        <label class="field">
          <span>Message to send — tap to select all, then copy</span>
          <textarea id="credText" readonly style="min-height:132px;font-size:13px">${esc(msg)}</textarea>
        </label>

        <div class="actions" style="border-top:0;padding-top:0">
          <button class="primary" id="credCopy">Copy details</button>
          <button id="credWa">Send on WhatsApp</button>
          <button id="credMail">Send by email</button>
          <button class="ghost" id="credClose">Done</button>
        </div>
      </div>
    </div>`;

  const box = $('#credText');
  /* Tapping the box selects everything, so a manual copy is one action. */
  box.onclick = () => { box.focus(); box.select(); box.setSelectionRange(0, msg.length); };

  $('#credCopy').onclick = async () => {
    /* Clipboard API needs a secure context and permission; inside a
       sandboxed preview frame it is often blocked. Fall back to the
       old execCommand path, then to manual selection. */
    try {
      await navigator.clipboard.writeText(msg);
      return toast('Copied to clipboard');
    } catch {}
    try {
      box.focus(); box.select(); box.setSelectionRange(0, msg.length);
      if (document.execCommand('copy')) return toast('Copied to clipboard');
    } catch {}
    box.focus(); box.select();
    toast('Text selected — press and hold, then Copy', 'bad');
  };

  $('#credWa').onclick = () => {
    const url = 'https://wa.me/?text=' + encodeURIComponent(msg);
    /* Popups are blocked inside the preview frame; fall back to
       navigating the top window, then to manual copy. */
    const w = window.open(url, '_blank', 'noopener');
    if (w) return;
    try { window.top.location.href = url; return; } catch {}
    try { location.href = url; return; } catch {}
    box.focus(); box.select();
    toast('Could not open WhatsApp — copy the text instead', 'bad');
  };

  /* Send by email. Opens the phone's mail app with the owner's
     address, a subject and the same message already filled in. */
  $('#credMail').onclick = () => {
    const url = 'mailto:' + encodeURIComponent(email || '')
      + '?subject=' + encodeURIComponent('Your PlantMaster Pro account is ready')
      + '&body='    + encodeURIComponent(msg);
    const w = window.open(url, '_blank', 'noopener');
    if (w) return;
    try { window.top.location.href = url; return; } catch {}
    try { location.href = url; return; } catch {}
    box.focus(); box.select();
    toast('Could not open your mail app — copy the text instead', 'bad');
  };

  $('#credClose').onclick = closeModal;
}

/* ============================================================
   ROUTER
   ============================================================ */
const ROUTES = {
  dashboard:pageDashboard, companies:pageCompanies, requests:pageRequests,
  accounts:pageAccounts, invites:pageInvites, plans:pagePlans,
  files:pageFiles, backup:pageBackup,
  support:pageSupport, activity:pageActivity, more:pageMore
};
const TABS = ['dashboard','companies','requests','accounts','more'];

/* The phone's back button walks back through the panel instead of
   leaving it. A back press closes an open dialog first. */
let popping = false;

async function navigate(next, push = true){
  if (push && next !== route && !popping){
    history.pushState({ pm:true, route:next }, '');
  }
  route = next;
  $$('#tabbar button').forEach(b =>
    b.classList.toggle('active',
      b.dataset.route === route || (!TABS.includes(route) && b.dataset.route === 'more')));
  window.scrollTo(0,0);
  await safeRender(() => (ROUTES[route] || pageDashboard)());
}

window.addEventListener('popstate', e => {
  /* A dialog is open: back just closes it and stays put. */
  if ($('#modalRoot').innerHTML.trim()){
    closeModal();
    history.pushState({ pm:true, route }, '');
    return;
  }
  const next = e.state?.route;
  if (!next){
    /* Nothing left in our history. Go to the dashboard once, then
       let a second press leave the app as normal. */
    if (route !== 'dashboard'){
      history.pushState({ pm:true, route:'dashboard' }, '');
      popping = true; navigate('dashboard', false).finally(()=>{ popping = false; });
    }
    return;
  }
  popping = true;
  navigate(next, false).finally(()=>{ popping = false; });
});

$('#tabbar').addEventListener('click', e => {
  const btn = e.target.closest('button[data-route]');
  if (btn) navigate(btn.dataset.route);
});

/* ============================================================
   AUTH
   ============================================================ */
function showScreen(which){
  $('#authScreen').hidden  = which !== 'login';
  $('#resetScreen').hidden = which !== 'reset';
  $('#app').classList.toggle('ready', which === 'app');
}

$('#loginForm').onsubmit = async e => {
  e.preventDefault();
  const btn = $('#loginBtn'), err = $('#loginError');
  err.hidden = true; btn.disabled = true; btn.textContent = 'Signing in…';
  const { error } = await sb.auth.signInWithPassword({
    email: $('#loginEmail').value.trim(), password: $('#loginPassword').value
  });
  if (error){
    err.textContent = error.message; err.hidden = false;
    btn.disabled = false; btn.textContent = 'Sign in';
  }
};

function isRecoveryUrl(){
  try{
    const q = location.search || '', h = location.hash || '';
    return q.includes('type=recovery') || q.includes('code=')
        || h.includes('type=recovery') || (h.includes('access_token') && h.includes('recovery'));
  }catch(_){ return false }
}

$('#forgotBtn').onclick = async () => {
  const email = $('#loginEmail').value.trim(), err = $('#loginError');
  if (!email){ err.textContent='Type your email first, then tap Forgot password.'; err.hidden=false; return; }
  sessionStorage.setItem('pmRecovery','1');
  const { error } = await sb.auth.resetPasswordForEmail(email, { redirectTo: location.origin + location.pathname });
  err.textContent = error
    ? error.message
    : 'Reset link sent to ' + email + '. If nothing arrives within a few minutes, check spam — and see LOGIN-EMAILS.txt, the project may still be on Supabase\'s built-in mailer which only delivers to your own address.';
  err.hidden = false;
};

$('#resetForm').onsubmit = async e => {
  e.preventDefault();
  const err = $('#resetError'); err.hidden = true;
  const { error } = await sb.auth.updateUser({ password: $('#newPassword').value });
  if (error){ err.textContent = error.message; err.hidden = false; return; }
  sessionStorage.removeItem('pmRecovery');
  toast('Password updated');
  await boot();
};

$('#logoutBtn').onclick = () => sb.auth.signOut();

async function boot(){
  const { data:{ session } } = await sb.auth.getSession();
  if (!session){ user=null; admin=null; showScreen('login'); return; }
  /* Recovery can be flagged three ways. The sessionStorage flag only
     works if the link opens in the SAME browser that asked for it —
     on a phone the email often opens in a different one, so also read
     the URL, including the hash form. */
  if (sessionStorage.getItem('pmRecovery')==='1' || isRecoveryUrl()){ showScreen('reset'); return; }

  user = session.user;
  const { data:row, error } = await sb.from('platform_admins')
    .select('*').eq('user_id', user.id).eq('active', true).maybeSingle();

  if (error){
    $('#loginError').textContent = 'Could not verify your admin account: ' + errText(error);
    $('#loginError').hidden = false; showScreen('login'); return;
  }
  if (!row){
    await sb.auth.signOut();
    $('#loginError').textContent = 'This account is not an active platform administrator.';
    $('#loginError').hidden = false; showScreen('login'); return;
  }

  admin = row;
  /* Top bar stays branded. Your email is on the More tab instead
     of over every screenshot you take. */
  $('#adminRole').textContent =
    (row.admin_role || 'admin').replace(/_/g,' ').replace(/^./, c => c.toUpperCase());
  showScreen('app');

  sb.from('platform_admins').update({ last_login_at:new Date().toISOString() })
    .eq('user_id', user.id).then(()=>{}, ()=>{});

  history.replaceState({ pm:true, route:'dashboard' }, '');
  await navigate('dashboard', false);
}

sb.auth.onAuthStateChange(event => {
  if (event === 'PASSWORD_RECOVERY'){ sessionStorage.setItem('pmRecovery','1'); showScreen('reset'); return; }
  if (event === 'SIGNED_OUT'){ user=null; admin=null; plansCache=[]; showScreen('login'); return; }
  if (event === 'SIGNED_IN' && !admin) boot();
});

boot();
