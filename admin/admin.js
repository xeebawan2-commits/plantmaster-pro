/**
 * PlantMaster Control Center — admin.hsbfix.org
 *
 * A separate front end for platform staff. It talks to the same Supabase
 * project as the customer app but only ever calls the platform_* RPCs, which
 * are gated on public.is_platform_admin() in the database. There is no
 * privileged key in this bundle: a customer who loads this page can sign in
 * but will be refused by Postgres, not merely hidden by the UI.
 */
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';
import { SUPABASE_URL, SUPABASE_ANON_KEY } from '/config.js';

const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, storageKey: 'pm-admin-auth' },
});

const $ = s => document.querySelector(s);
const $$ = s => [...document.querySelectorAll(s)];
const esc = v => String(v ?? '').replace(/[&<>"']/g,
  c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const STATUSES = ['trial', 'active', 'past_due', 'suspended', 'cancelled', 'deletion_pending'];
let plans = [], view = 'tenants', tenants = [];

function toast(msg, bad = false) {
  const t = $('#toast');
  t.textContent = msg;
  t.className = 'toast show' + (bad ? ' bad' : '');
  clearTimeout(t._t);
  t._t = setTimeout(() => { t.className = 'toast'; }, 3200);
}

const bytes = n => {
  n = Number(n) || 0;
  if (n < 1024) return n + ' B';
  const u = ['KB', 'MB', 'GB', 'TB'];
  let i = -1;
  do { n /= 1024; i++; } while (n >= 1024 && i < u.length - 1);
  return n.toFixed(n < 10 ? 1 : 0) + ' ' + u[i];
};
const when = d => d ? new Date(d).toLocaleString() : '—';
const day = d => d ? new Date(d).toLocaleDateString() : '—';

/* ── auth ──────────────────────────────────────────────────────────────── */
async function boot() {
  const { data } = await sb.auth.getSession();
  if (!data.session) return showGate();
  await afterLogin();
}

function showGate() {
  $('#auth').hidden = false;
  $('#denied').hidden = true;
  $('#app').hidden = true;
}

async function afterLogin() {
  const { data: admin, error } = await sb.rpc('is_platform_admin');
  if (error) { $('#authMsg').textContent = error.message; return showGate(); }
  if (!admin) {
    $('#auth').hidden = true; $('#app').hidden = true; $('#denied').hidden = false;
    return;
  }
  const { data: u } = await sb.auth.getUser();
  $('#who').textContent = u?.user?.email || '';
  $('#auth').hidden = true; $('#denied').hidden = true; $('#app').hidden = false;

  const p = await sb.from('subscription_plans').select('*').order('sort_order');
  plans = p.data || [];
  render();
}

$('#authForm').addEventListener('submit', async e => {
  e.preventDefault();
  const btn = e.target.querySelector('button');
  btn.disabled = true; $('#authMsg').textContent = 'Signing in…';
  const { error } = await sb.auth.signInWithPassword({
    email: $('#email').value.trim(), password: $('#password').value,
  });
  btn.disabled = false;
  if (error) { $('#authMsg').textContent = error.message; return; }
  $('#authMsg').textContent = '';
  await afterLogin();
});

const signOut = async () => { await sb.auth.signOut(); location.reload(); };
$('#signOut').addEventListener('click', signOut);
$('#denyOut').addEventListener('click', signOut);

/* ── navigation ────────────────────────────────────────────────────────── */
$$('.tab').forEach(b => b.addEventListener('click', () => {
  $$('.tab').forEach(x => x.classList.toggle('active', x === b));
  view = b.dataset.view;
  render();
}));

function render() {
  $('#main').innerHTML = '<div class="loading"><span class="spin"></span> Loading…</div>';
  ({ tenants: renderTenants, complaints: renderComplaints,
     incidents: renderIncidents, plans: renderPlans }[view] || renderTenants)();
}

/* ── companies ─────────────────────────────────────────────────────────── */
async function renderTenants() {
  const { data, error } = await sb.rpc('platform_tenant_overview');
  if (error) return fail(error.message);
  tenants = data || [];

  const totals = tenants.reduce((a, t) => ({
    workers: a.workers + Number(t.workers || 0),
    storage: a.storage + Number(t.storage_bytes || 0),
    ai: a.ai + Number(t.ai_requests_month || 0),
    active: a.active + (t.commercial_status === 'active' ? 1 : 0),
  }), { workers: 0, storage: 0, ai: 0, active: 0 });

  $('#main').innerHTML = `
    <div class="stats">
      ${stat('Companies', tenants.length)}
      ${stat('Active', totals.active)}
      ${stat('Users', totals.workers)}
      ${stat('Storage', bytes(totals.storage))}
      ${stat('AI this month', totals.ai)}
    </div>
    <div class="bar">
      <input id="q" type="search" placeholder="Search company, plan or status…">
      <button class="btn ghost tiny" id="refresh">Refresh</button>
    </div>
    <div class="grid" id="grid">
      ${tenants.map(tenantCard).join('') || '<div class="empty">No companies yet.</div>'}
    </div>`;

  $('#refresh').onclick = render;
  $('#q').oninput = e => {
    const q = e.target.value.toLowerCase();
    $$('#grid .card').forEach(c => { c.hidden = !c.dataset.s.includes(q); });
  };
  $$('[data-apply]').forEach(b => b.onclick = () => applyChanges(b.dataset.apply));
}

const stat = (label, value) =>
  `<div class="stat"><span>${esc(label)}</span><b>${esc(value)}</b></div>`;

function tenantCard(t) {
  const search = `${t.organization_name} ${t.plan_name} ${t.commercial_status}`.toLowerCase();
  const planOpts = plans.map(p =>
    `<option value="${esc(p.code)}"${p.code === t.plan_code ? ' selected' : ''}>${esc(p.name)}</option>`).join('');
  const statusOpts = STATUSES.map(s =>
    `<option${s === t.commercial_status ? ' selected' : ''}>${s}</option>`).join('');

  return `
  <article class="card" data-s="${esc(search)}">
    <div class="card-head">
      <div>
        <h3>${esc(t.organization_name)}</h3>
        <small>Since ${day(t.created_at)}</small>
      </div>
      <span class="pill ${esc(t.commercial_status)}">${esc(t.commercial_status.replace('_', ' '))}</span>
    </div>
    <dl class="metrics">
      <div><dt>Users</dt><dd>${esc(t.workers)}</dd></div>
      <div><dt>Plants</dt><dd>${esc(t.plants)}</dd></div>
      <div><dt>Files</dt><dd>${esc(t.files)}</dd></div>
      <div><dt>Storage</dt><dd>${bytes(t.storage_bytes)}</dd></div>
      <div><dt>AI / month</dt><dd>${esc(t.ai_requests_month)}</dd></div>
      <div><dt>Incidents</dt><dd>${esc(t.open_incidents)}</dd></div>
    </dl>
    <div class="controls">
      <label><span>Plan</span>
        <select id="plan-${t.organization_id}">${planOpts}</select></label>
      <label><span>Status</span>
        <select id="status-${t.organization_id}">${statusOpts}</select></label>
      <label class="wide"><span>Reason / note</span>
        <input id="reason-${t.organization_id}" value="${esc(t.status_reason || '')}"
               placeholder="Visible in the audit log"></label>
      <button class="btn tiny" data-apply="${t.organization_id}">Apply</button>
    </div>
  </article>`;
}

async function applyChanges(id) {
  const status = $(`#status-${id}`).value;
  const plan = $(`#plan-${id}`).value;
  const reason = $(`#reason-${id}`).value.trim();
  const t = tenants.find(x => x.organization_id === id);

  // Destructive states need the company name typed back — the old app used a
  // generic "type SUSPENDED" prompt, which is easy to confirm on the wrong row.
  if (['suspended', 'cancelled', 'deletion_pending'].includes(status)
      && status !== t.commercial_status) {
    const typed = prompt(
      `This will set "${t.organization_name}" to ${status.toUpperCase()}.\n` +
      `Type the company name exactly to confirm:`);
    if (typed !== t.organization_name) return toast('Cancelled — name did not match', true);
  }
  if (!reason && status !== t.commercial_status) {
    return toast('A reason is required when changing status', true);
  }

  const { error } = await sb.rpc('platform_set_company', {
    p_organization_id: id, p_status: status,
    p_plan_code: plan, p_reason: reason || null,
  });
  if (error) return toast(error.message, true);
  toast(`${t.organization_name} updated`);
  render();
}

/* ── complaints ────────────────────────────────────────────────────────── */
async function renderComplaints() {
  const { data, error } = await sb.from('app_complaints')
    .select('*').order('updated_at', { ascending: false }).limit(200);
  if (error) return fail(error.message);
  const rows = data || [];
  const open = rows.filter(r => r.status !== 'closed');

  $('#main').innerHTML = `
    <div class="stats">
      ${stat('Total', rows.length)}
      ${stat('Open', open.length)}
      ${stat('Critical', rows.filter(r => r.priority === 'critical').length)}
    </div>
    <div class="list">
      ${rows.map(r => `
        <article class="row" data-id="${esc(r.id)}">
          <div class="row-main">
            <div class="row-title">
              <b>#${esc(r.ticket_number)} ${esc(r.subject)}</b>
              <span class="pill ${esc(r.status)}">${esc(r.status)}</span>
              <span class="pill p-${esc(r.priority)}">${esc(r.priority)}</span>
            </div>
            <small>${esc(r.category)} · ${when(r.updated_at)}</small>
            <p>${esc(String(r.description).slice(0, 260))}</p>
          </div>
          <div class="row-side">
            <button class="btn ghost tiny" data-open="${esc(r.id)}">Conversation</button>
            <select data-status="${esc(r.id)}">
              ${['open','in_progress','waiting','resolved','closed']
                .map(s => `<option${s === r.status ? ' selected' : ''}>${s}</option>`).join('')}
            </select>
          </div>
        </article>`).join('') || '<div class="empty">No complaints.</div>'}
    </div>
    <div id="thread"></div>`;

  $$('[data-open]').forEach(b => b.onclick = () => openThread(b.dataset.open));
  $$('[data-status]').forEach(s => s.onchange = async () => {
    const { error } = await sb.from('app_complaints')
      .update({ status: s.value, updated_at: new Date().toISOString() })
      .eq('id', s.dataset.status);
    toast(error ? error.message : 'Status updated', !!error);
  });
}

async function openThread(id) {
  const { data, error } = await sb.rpc('owner_app_complaint_messages', { p_ticket_id: id });
  if (error) return toast(error.message, true);
  const box = $('#thread');
  box.innerHTML = `
    <div class="thread">
      <h3>Conversation</h3>
      <div class="msgs">
        ${(data || []).map(m => `
          <div class="msg ${m.is_staff ? 'staff' : ''}">
            <p>${esc(m.message)}</p>
            <small>${m.is_staff ? 'Platform' : 'Customer'} · ${when(m.created_at)}</small>
          </div>`).join('') || '<p class="empty">No replies yet.</p>'}
      </div>
      <form id="replyForm">
        <textarea id="reply" required placeholder="Reply to the customer…"></textarea>
        <button class="btn tiny" type="submit">Send reply</button>
      </form>
    </div>`;
  box.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  $('#replyForm').onsubmit = async e => {
    e.preventDefault();
    const { error: err } = await sb.rpc('reply_app_complaint',
      { p_ticket_id: id, p_message: $('#reply').value });
    if (err) return toast(err.message, true);
    toast('Reply sent');
    openThread(id);
  };
}

/* ── incidents ─────────────────────────────────────────────────────────── */
async function renderIncidents() {
  const { data, error } = await sb.from('system_incidents')
    .select('*').order('last_seen_at', { ascending: false }).limit(200);
  if (error) return fail(error.message);
  const rows = data || [];

  $('#main').innerHTML = `
    <div class="bar">
      <b>System incidents</b>
      <button class="btn tiny" id="newInc">＋ Raise incident</button>
    </div>
    <div class="list">
      ${rows.map(r => `
        <article class="row">
          <div class="row-main">
            <div class="row-title">
              <b>${esc(r.title)}</b>
              <span class="pill ${esc(r.status)}">${esc(r.status)}</span>
              <span class="pill p-${esc(r.severity)}">${esc(r.severity)}</span>
            </div>
            <small>${esc(r.component || 'platform')} · last seen ${when(r.last_seen_at)}</small>
            <p>${esc(r.description || '')}</p>
          </div>
          <div class="row-side">
            <button class="btn ghost tiny" data-resolve="${esc(r.id)}"
              ${r.status === 'resolved' ? 'disabled' : ''}>Resolve</button>
          </div>
        </article>`).join('') || '<div class="empty">No incidents. Good.</div>'}
    </div>`;

  $('#newInc').onclick = async () => {
    const title = prompt('Incident title:');
    if (!title) return;
    const severity = prompt('Severity (minor / major / critical):', 'minor') || 'minor';
    const { error: err } = await sb.from('system_incidents')
      .insert({ title, severity, description: '', status: 'open' });
    toast(err ? err.message : 'Incident raised', !!err);
    if (!err) render();
  };
  $$('[data-resolve]').forEach(b => b.onclick = async () => {
    const { error: err } = await sb.from('system_incidents')
      .update({ status: 'resolved', resolved_at: new Date().toISOString(), active: false })
      .eq('id', b.dataset.resolve);
    toast(err ? err.message : 'Resolved', !!err);
    if (!err) render();
  });
}

/* ── plans ─────────────────────────────────────────────────────────────── */
async function renderPlans() {
  const { data, error } = await sb.from('subscription_plans').select('*').order('sort_order');
  if (error) return fail(error.message);
  plans = data || [];
  $('#main').innerHTML = `
    <div class="bar"><b>Subscription plans</b>
      <small class="hint">Changes apply to every company on the plan.</small></div>
    <div class="grid">
      ${plans.map(p => `
        <article class="card">
          <div class="card-head">
            <div><h3>${esc(p.name)}</h3><small>${esc(p.code)}</small></div>
            <span class="pill ${p.active ? 'active' : 'cancelled'}">${p.active ? 'active' : 'hidden'}</span>
          </div>
          <dl class="metrics">
            <div><dt>Price</dt><dd>${Number(p.price_monthly).toLocaleString()} ${esc(p.currency)}</dd></div>
            <div><dt>Users</dt><dd>${p.max_users ?? '∞'}</dd></div>
            <div><dt>Plants</dt><dd>${p.max_plants ?? '∞'}</dd></div>
            <div><dt>Assets</dt><dd>${p.max_assets ?? '∞'}</dd></div>
            <div><dt>Storage</dt><dd>${p.storage_gb} GB</dd></div>
            <div><dt>AI / month</dt><dd>${p.ai_requests_month}</dd></div>
          </dl>
          <div class="features">
            ${Object.entries(p.features || {}).map(([k, v]) =>
              `<span class="feat ${v ? 'on' : 'off'}">${esc(k.replace(/_/g, ' '))}</span>`).join('')}
          </div>
        </article>`).join('')}
    </div>`;
}

function fail(message) {
  $('#main').innerHTML =
    `<div class="empty"><b>Could not load</b><p>${esc(message)}</p>
     <button class="btn ghost tiny" onclick="location.reload()">Retry</button></div>`;
}

boot();
