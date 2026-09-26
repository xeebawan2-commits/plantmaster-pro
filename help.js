/* =====================================================================
   PlantMaster Pro — Help & Guided Tour (Phase 1 discoverability)
   Pure front-end. Adds:
     • a floating "?" button that explains the CURRENT screen
     • a per-module Help dialog (what it is + how to use it)
     • a first-run guided tour that spotlights the main areas
   No backend/data changes. Exposes window.PMHelp.
   ===================================================================== */
(function () {
  'use strict';
  if (window.PMHelp) return;

  var esc = function (s) {
    return String(s == null ? '' : s).replace(/[&<>"]/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c];
    });
  };

  /* ---------------- per-module help content ---------------- */
  var HELP = {
    dashboard: { icon: '⌂', title: 'Dashboard', what: 'Your home screen. It shows key numbers for the current plant and quick links into every module.',
      steps: ['Read the KPI cards at the top for a fast health check of the plant.', 'Tap any tile or card to open that module.', 'Use the plant name in the header to confirm which plant you are viewing.', 'The search box on this screen searches across your records.'] },
    assets: { icon: '🏭', title: 'Assets', what: 'The register of all equipment and machines in this plant, each with its own state and QR code.',
      steps: ['Tap “＋ Add” to register a new machine or piece of equipment.', 'Open any asset to see its details, history and QR label.', 'Print the QR label and stick it on the machine.', 'Scan that QR later (Scanner module) to jump straight back to the asset.'] },
    work: { icon: '🧰', title: 'Work Orders', what: 'Corrective and repair jobs assigned to your team, tracked from open to done.',
      steps: ['Tap “＋ Add” to raise a new work order and assign it to a person.', 'Link it to the affected asset so the history stays together.', 'Add LOTO / permits where safety isolation is needed.', 'Mark the job complete when finished — it stays on record for reports.'] },
    checklists: { icon: '✅', title: 'Checklists', what: 'Reusable inspection templates and the completed runs your team fills in.',
      steps: ['Create a template listing the points to check.', 'Assign or run the checklist during rounds.', 'Each completed run is saved with who did it and when.', 'Use runs later as proof of inspection in reports.'] },
    maintenance: { icon: '🛠', title: 'Maintenance Plans', what: 'Planned (preventive) maintenance on weekly, monthly and yearly schedules.',
      steps: ['Create a plan and set how often it repeats.', 'Attach it to an asset or group of assets.', 'The plan generates due tasks automatically on schedule.', 'Complete tasks to keep the equipment on its service cycle.'] },
    condition: { icon: '∿', title: 'Condition Monitoring', what: 'Use the phone’s microphone and motion sensors to screen a running machine for abnormal sound and vibration.',
      steps: ['Hold the phone firmly against the machine housing near the bearing.', 'Start a vibration or sound capture and keep still for a few seconds.', 'Read the amplitude and dominant frequency it reports.', 'Trend readings over time — a rising number means growing trouble. This is a screening aid, not a certified ISO tester.'] },
    solver: { icon: '🧠', title: 'Problem Solver', what: 'AI troubleshooting that answers using YOUR uploaded equipment manuals, in English or Urdu.',
      steps: ['Describe the fault in plain words (you can use the voice button).', 'The assistant searches your manuals and gives grounded steps.', 'Upload the machine’s manual first (Manuals module) for best answers.', 'Follow the safety notes before acting on any suggestion.'] },
    qr: { icon: '📷', title: 'Scanner', what: 'One camera tool for four jobs: scan QR/barcodes, read nameplates, identify equipment, or analyse an imported image.',
      steps: ['QR & Barcode: scan a label to open the linked asset, tool or spare.', 'Nameplate: photograph a rating plate to extract its specs.', 'Identify: photograph a machine/part for an AI identification.', 'Import: analyse an existing photo or file. Save a scan to keep it on record.'] },
    inventory: { icon: '📦', title: 'Spares & Tools', what: 'Stock levels for spare parts, plus tool custody and calibration tracking.',
      steps: ['Add spare parts with minimum/maximum stock levels.', 'Record issues and receipts so stock stays accurate.', 'Track which tool is in whose custody.', 'Set calibration due dates so nothing lapses.'] },
    procurement: { icon: '🧾', title: 'Purchase Orders', what: 'Raise purchase requests, get them approved, and record goods received.',
      steps: ['Create a PO listing the items and supplier.', 'Send it for approval per your workflow.', 'When goods arrive, record the receipt against the PO.', 'Completed POs feed procurement reports.'] },
    suppliers: { icon: '🏷', title: 'Suppliers', what: 'Your vendor directory with tax details (NTN/STRN) and payment terms.',
      steps: ['Add a supplier with contact and tax information.', 'Set their payment terms.', 'Link suppliers to purchase orders.', 'Keep details current for clean procurement records.'] },
    people: { icon: '👷', title: 'Roster & Attendance', what: 'Your team roster, roles, daily logs and attendance.',
      steps: ['View everyone on this workspace and their role.', 'Record attendance and daily logs.', 'Roles control what each person can access.', 'Use Invitations to add new members.'] },
    invites: { icon: '✉️', title: 'Invitations', what: 'Invite new people to this company workspace and set their role.',
      steps: ['Create an invitation and choose the person’s role.', 'Share the invite link with them.', 'They accept and join this workspace.', 'Manage or revoke pending invites here.'] },
    manuals: { icon: '📚', title: 'Manuals & Drawings', what: 'Upload equipment manuals and drawings. They are indexed so Problem Solver can answer from them.',
      steps: ['Upload a PDF manual or drawing.', 'It is indexed automatically for AI search.', 'Link a manual to its asset for quick access.', 'Ask questions about it in Problem Solver.'] },
    files: { icon: '🗂', title: 'Files', what: 'General document storage for the whole company workspace.',
      steps: ['Tap “＋ Upload” to add a file.', 'Files are stored securely per company.', 'Open or download them anytime.', 'Deleted files can be restored from the Recovery Bin.'] },
    reports: { icon: '📊', title: 'Reports', what: 'Generate reports for any module and download them as CSV, Excel, Word or PDF.',
      steps: ['Choose the module and date range.', 'Tap “Generate Report”.', 'Preview it on screen.', 'View or Download in the format you need.'] },
    analytics: { icon: '📈', title: 'Analytics & KPIs', what: 'Charts and key metrics that summarise plant performance over time.',
      steps: ['Review the charts for trends.', 'Watch metrics move as your team logs work.', 'Use it to spot problem areas early.', 'Pair with Reports when you need to share the numbers.'] },
    email: { icon: '📧', title: 'Daily Email', what: 'Configure the automatic daily summary email for the company.',
      steps: ['Set the daily report time in Company Profile.', 'Choose what the summary includes.', 'It is sent automatically each day.', 'Check recipients and settings here.'] },
    profile: { icon: '🏢', title: 'Company Profile & Theme', what: 'Company name, logo, colours and document branding — applied across the app and reports.',
      steps: ['Upload your company logo.', 'Pick your primary and secondary colours.', 'Set address, contact and the document footer.', 'Save & Apply — branding updates everywhere instantly.'] },
    commercial: { icon: '◈', title: 'Plan & Usage', what: 'Your subscription plan, limits and current usage.',
      steps: ['See which plan you are on and its limits.', 'Track usage against those limits.', 'Upgrade if you need more capacity.', 'AI and storage usage count against the plan.'] },
    notifications: { icon: '🔔', title: 'Alerts', what: 'System alerts and reminders for the plant, plus push-notification settings.',
      steps: ['Review current alerts and reminders.', 'Enable push notifications to get them on your device.', 'Act on anything overdue.', 'Alerts also surface on the Dashboard.'] },
    audit: { icon: '📜', title: 'Audit Trail', what: 'A record of who changed what and when, for accountability.',
      steps: ['Browse recent changes across the workspace.', 'Filter by date to find an event.', 'Use it to answer “who did this?”.', 'Records are read-only and cannot be edited.'] },
    recovery: { icon: '♻️', title: 'Recovery Bin', what: 'Recently deleted records are kept here so you can restore them.',
      steps: ['Find a record that was deleted by mistake.', 'Restore it to bring it back.', 'Items here are removed permanently after a while.', 'Only allowed roles can restore.'] },
    appsupport: { icon: '◉', title: 'App Complaints', what: 'Raise application, account, billing or data issues directly to the PlantMaster platform (owner only).',
      steps: ['Tap “＋ New Complaint”.', 'Pick the category and describe the issue.', 'Track replies in the conversation.', 'For machine faults use Work Orders instead.'] },
    support: { icon: '💬', title: 'Support', what: 'In-company help and guidance.',
      steps: ['Open Support for help using the app.', 'Read the guidance provided.', 'Reach out through the channels shown.', 'For platform/billing issues, owners use App Complaints.'] },
    settings: { icon: '⚙️', title: 'Settings', what: 'Workspace and application preferences.',
      steps: ['Review the available options.', 'Adjust preferences to suit your team.', 'Some settings are limited to owners/managers.', 'Changes save to this workspace.'] },
    __default: { icon: '❔', title: 'PlantMaster Pro', what: 'This screen is part of your maintenance workspace.',
      steps: ['Use the menu on the left to move between modules.', 'Tap “Take the tour” for a quick walkthrough.', 'Open this Help on any screen with the “?” button.'] }
  };

  function currentView() {
    return window.currentView ||
      (document.querySelector('#drawer [data-view].active') || {}).dataset && document.querySelector('#drawer [data-view].active').dataset.view ||
      'dashboard';
  }

  /* ---------------- Help dialog ---------------- */
  function openHelp(view) {
    view = view || currentView();
    var h = HELP[view] || HELP.__default;
    var dlg = document.getElementById('pmHelpDialog');
    if (!dlg) { dlg = document.createElement('dialog'); dlg.id = 'pmHelpDialog'; document.body.appendChild(dlg); }
    dlg.innerHTML =
      '<div class="pmh-head"><span class="pmh-ico">' + esc(h.icon) + '</span>' +
      '<div><h2>' + esc(h.title) + '</h2><p>' + esc(h.what) + '</p></div>' +
      '<button class="pmh-x" type="button" aria-label="Close">✕</button></div>' +
      '<div class="pmh-body"><div class="pmh-sec-title">How to use it</div>' +
      '<ol class="pmh-steps">' + h.steps.map(function (s) { return '<li>' + esc(s) + '</li>'; }).join('') + '</ol></div>' +
      '<div class="pmh-foot"><button class="pmh-tour" type="button">🎓 Take the full tour</button>' +
      '<button class="pmh-open" type="button">Open ' + esc(h.title) + ' →</button></div>';
    dlg.querySelector('.pmh-x').onclick = function () { closeDlg(dlg); };
    dlg.querySelector('.pmh-tour').onclick = function () { closeDlg(dlg); startTour(); };
    dlg.querySelector('.pmh-open').onclick = function () { closeDlg(dlg); if (window.go) window.go(view); };
    if (typeof dlg.showModal === 'function') { try { dlg.showModal(); } catch (e) { dlg.setAttribute('open', ''); } }
    else dlg.setAttribute('open', '');
  }
  function closeDlg(d) { try { if (d.open && d.close) d.close(); else d.removeAttribute('open'); } catch (e) { d.removeAttribute('open'); } }

  /* ---------------- floating "?" button ---------------- */
  function ensureButton() {
    if (document.getElementById('pmHelpBtn')) return;
    var b = document.createElement('button');
    b.id = 'pmHelpBtn'; b.type = 'button'; b.textContent = '?';
    b.title = 'Help for this screen'; b.setAttribute('aria-label', 'Help for this screen');
    b.onclick = function () { openHelp(); };
    document.body.appendChild(b);
  }

  /* ---------------- guided tour ---------------- */
  var TOUR = [
    { sel: null, title: 'Welcome to PlantMaster Pro 👋',
      body: 'This is a quick 60-second tour. It shows where everything lives so you and your team can find features fast. You can skip anytime.' },
    { sel: '#drawer', pad: 6, openDrawer: true, title: 'Everything lives in this menu',
      body: 'The left menu is your map to the whole app. On a computer it stays open; on a phone tap the ☰ button to open it.' },
    { sel: '.nav-group', pad: 6, openDrawer: true, title: 'Grouped by job',
      body: 'Features are grouped — Operations, Maintenance & Monitoring, Inventory & Procurement, People, Documents & Reports, and Company & Admin — so you only look where you expect.' },
    { sel: '#content', pad: 6, goto: 'dashboard', title: 'Your Dashboard',
      body: 'The Dashboard shows plant health and quick links. The tiles jump straight into Assets, Work Orders, Scanner, Condition Monitoring and more.' },
    { sel: '#pmHelpBtn', pad: 8, title: 'Stuck? Tap “?” anywhere',
      body: 'This blue “?” button is always here. Tap it on any screen for a plain-language explanation of what that screen does and how to use it.' },
    { sel: null, title: 'You’re ready 🎉',
      body: 'That’s the whole layout. Re-open this tour anytime from the menu → “Take the tour”. Have a great day on PlantMaster Pro!' }
  ];
  var ti = 0, tourRoot = null, veil = null, card = null, reflow = null;

  function isDesktop() { return window.matchMedia('(min-width:1100px)').matches; }

  function startTour() {
    endTour(false);
    tourRoot = document.createElement('div'); tourRoot.id = 'pmTour';
    veil = document.createElement('div'); veil.className = 'pmt-veil';
    card = document.createElement('div'); card.className = 'pmt-card';
    tourRoot.appendChild(veil); tourRoot.appendChild(card);
    document.body.appendChild(tourRoot);
    ti = 0; showStep(0);
    reflow = function () { positionCurrent(); };
    window.addEventListener('resize', reflow);
    window.addEventListener('scroll', reflow, true);
  }

  function endTour(save) {
    if (reflow) { window.removeEventListener('resize', reflow); window.removeEventListener('scroll', reflow, true); reflow = null; }
    if (tourRoot && tourRoot.parentNode) tourRoot.parentNode.removeChild(tourRoot);
    tourRoot = veil = card = null;
    if (!isDesktop()) { var d = document.getElementById('drawer'); if (d) d.classList.remove('open'); if (window.renderNav) try { window.renderNav(); } catch (e) {} }
    if (save) { try { localStorage.setItem('pmTourDone', '1'); } catch (e) {} }
  }

  var _step = null;
  function showStep(i) {
    if (!tourRoot) return;
    i = Math.max(0, Math.min(TOUR.length - 1, i)); ti = i;
    var step = TOUR[i]; _step = step;
    var proceed = function () {
      // open/close drawer as the step needs (mobile)
      var d = document.getElementById('drawer');
      if (d && !isDesktop()) { if (step.openDrawer) d.classList.add('open'); else d.classList.remove('open'); if (window.renderNav) try { window.renderNav(); } catch (e) {} }
      renderCard(step);
      // let layout settle, then position
      setTimeout(positionCurrent, step.goto ? 420 : 90);
    };
    if (step.goto && window.go) { try { window.go(step.goto); } catch (e) {} }
    proceed();
  }

  function renderCard(step) {
    if (!card) return;
    var last = ti === TOUR.length - 1;
    card.innerHTML =
      '<div class="pmt-steps">Step ' + (ti + 1) + ' of ' + TOUR.length + '</div>' +
      '<h3>' + esc(step.title) + '</h3><p>' + esc(step.body) + '</p>' +
      '<div class="pmt-actions">' +
      '<button class="pmt-skip" type="button">Skip</button>' +
      (ti > 0 ? '<button class="pmt-back" type="button">Back</button>' : '') +
      '<button class="pmt-next" type="button">' + (last ? 'Finish' : 'Next') + '</button></div>';
    card.querySelector('.pmt-skip').onclick = function () { endTour(true); };
    var back = card.querySelector('.pmt-back'); if (back) back.onclick = function () { showStep(ti - 1); };
    card.querySelector('.pmt-next').onclick = function () { if (last) endTour(true); else showStep(ti + 1); };
  }

  function positionCurrent() {
    if (!tourRoot || !_step) return;
    var vw = window.innerWidth, vh = window.innerHeight;
    var target = _step.sel ? document.querySelector(_step.sel) : null;
    var rect = target ? target.getBoundingClientRect() : null;
    if (!rect || rect.width === 0 || rect.height === 0) {
      // no target -> hide the spotlight hole, center the card
      veil.style.opacity = '0';
      veil.style.width = veil.style.height = '0px';
      veil.style.top = (vh / 2) + 'px'; veil.style.left = (vw / 2) + 'px';
      centerCard();
      return;
    }
    veil.style.opacity = '1';
    var pad = _step.pad || 6;
    var top = Math.max(4, rect.top - pad), left = Math.max(4, rect.left - pad);
    var w = Math.min(vw - 8, rect.width + pad * 2), h = Math.min(vh - 8, rect.height + pad * 2);
    veil.style.top = top + 'px'; veil.style.left = left + 'px';
    veil.style.width = w + 'px'; veil.style.height = h + 'px';
    placeCard(rect);
  }

  function centerCard() {
    var cw = card.offsetWidth || 320, ch = card.offsetHeight || 160;
    card.style.left = Math.max(12, (window.innerWidth - cw) / 2) + 'px';
    card.style.top = Math.max(12, (window.innerHeight - ch) / 2) + 'px';
  }

  function placeCard(rect) {
    var vw = window.innerWidth, vh = window.innerHeight;
    var cw = card.offsetWidth || 320, ch = card.offsetHeight || 170, gap = 16;
    var top, left;
    // tall element (e.g. the sidebar): place beside it if room, else center
    if (rect.height > vh * 0.5) {
      if (rect.right + gap + cw < vw) { left = rect.right + gap; top = Math.min(vh - ch - 12, Math.max(12, rect.top)); }
      else { centerCard(); return; }
    } else if (rect.bottom + gap + ch < vh) { // below
      top = rect.bottom + gap; left = clamp(rect.left, 12, vw - cw - 12);
    } else if (rect.top - gap - ch > 12) { // above
      top = rect.top - gap - ch; left = clamp(rect.left, 12, vw - cw - 12);
    } else { centerCard(); return; }
    card.style.top = top + 'px'; card.style.left = left + 'px';
  }
  function clamp(v, a, b) { return Math.max(a, Math.min(b, v)); }

  function maybeStartTour() {
    try { if (localStorage.getItem('pmTourDone')) return; } catch (e) {}
    if (document.getElementById('app') && document.getElementById('app').hidden) return;
    setTimeout(function () { if (!document.getElementById('pmTour')) startTour(); }, 500);
  }

  function init() { ensureButton(); }

  window.PMHelp = {
    init: init,
    openHelp: openHelp,
    startTour: startTour,
    maybeStartTour: maybeStartTour,
    onNavigate: function (v) { if (v) window.currentView = v; }
  };
})();
