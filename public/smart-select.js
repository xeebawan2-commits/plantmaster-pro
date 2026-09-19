// PlantMaster Pro v4.41.0 — Smart Select
// Turns every dropdown in the app into "pick from the list OR type your own".
//
// WHY
// A plain <select> can only ever offer what the developer hard-coded. Plants use
// words we never anticipated — a designation, a spare category, a permit type.
// This converts each <select> into an <input list="…"> backed by a <datalist>:
//   • tap the arrow / the field  -> the full list drops down, same as before
//   • tap and type               -> any custom value is accepted
// The input keeps the original name/id, so every existing form handler that reads
// FormData or .value keeps working untouched.
//
// Applies to selects rendered at any time (dialogs are built dynamically), and is
// idempotent — re-running never double-converts.
(() => {
  'use strict';

  // Selects that must stay strict. These drive queries, not free text:
  // a typed value would silently break them.
  const SKIP_IDS = new Set([
    'reportModule',   // must match a real table name
    'auditAction',    // must match a stored action string
    'setTheme',       // fixed theme keys
    'setPattern',     // fixed pattern keys
    'conditionAsset', // must be a real asset uuid
    'conditionShift'  // fixed shift keys
  ]);
  const SKIP_NAMES = new Set([
    'asset_id',       // uuid foreign key
    'spare_id',
    'supplier_id',
    'work_order_id',
    'plant_id',
    'user_id',
    'role',           // RLS depends on exact role strings
    'status',         // state machines rely on exact values
    'transaction_type'
  ]);

  const idOf = (sel) => 'pmdl-' + sel.replace(/[^a-z0-9]+/gi, '-').toLowerCase();

  const ensureList = (key, values) => {
    const id = idOf(key);
    let dl = document.getElementById(id);
    if (!dl) {
      dl = document.createElement('datalist');
      dl.id = id;
      document.body.appendChild(dl);
    }
    const html = values.map(v => `<option value="${String(v).replace(/"/g, '&quot;')}">`).join('');
    if (dl.innerHTML !== html) dl.innerHTML = html;
    return id;
  };

  const convert = (sel) => {
    if (!sel || sel.dataset.pmSmart === '1') return;
    if (sel.multiple) return;
    if (sel.id && SKIP_IDS.has(sel.id)) return;
    if (sel.name && SKIP_NAMES.has(sel.name)) return;

    const opts = [...sel.options]
      .map(o => ({ v: o.value, t: (o.textContent || '').trim() }))
      .filter(o => o.v !== '' || o.t !== '');
    if (!opts.length) return;

    // If option values differ from their labels they are codes, not words —
    // typing a label would submit something the backend does not expect.
    const labelled = opts.every(o => o.v === o.t);
    if (!labelled) return;

    const key = sel.name || sel.id || 'list';
    const listId = ensureList(key, opts.map(o => o.v));

    const input = document.createElement('input');
    input.type = 'text';
    input.setAttribute('list', listId);
    if (sel.name) input.name = sel.name;
    if (sel.id) input.id = sel.id;
    if (sel.required) input.required = true;
    if (sel.disabled) input.disabled = true;
    if (sel.className) input.className = sel.className;
    input.value = sel.value || '';
    input.autocomplete = 'off';
    input.placeholder = sel.getAttribute('data-placeholder') || 'Choose or type your own';
    input.dataset.pmSmart = '1';

    // carry over inline handlers so existing wiring keeps working
    if (sel.getAttribute('onchange')) input.setAttribute('onchange', sel.getAttribute('onchange'));
    if (sel.getAttribute('oninput'))  input.setAttribute('oninput',  sel.getAttribute('oninput'));

    sel.replaceWith(input);
  };

  const scan = (root) => {
    if (!root || !root.querySelectorAll) return;
    root.querySelectorAll('select').forEach(convert);
  };

  const boot = () => scan(document);
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot, { once: true });
  } else {
    boot();
  }

  // dialogs and views are rendered after load, so keep watching
  const obs = new MutationObserver((muts) => {
    for (const m of muts) {
      for (const n of m.addedNodes) {
        if (n.nodeType !== 1) continue;
        if (n.tagName === 'SELECT') convert(n);
        else scan(n);
      }
    }
  });
  obs.observe(document.documentElement, { childList: true, subtree: true });
})();
