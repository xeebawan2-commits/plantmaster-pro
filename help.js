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

  /* ================= SVG icon system (Lucide-style, 24px stroke) ================= */
  var P = {
    dashboard: '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/>',
    assets: '<path d="M2 20a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V8l-7 5V8l-7 5V4a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2z"/><path d="M7 18h.01M12 18h.01M17 18h.01"/>',
    work: '<path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/>',
    checklists: '<path d="m3 17 2 2 4-4"/><path d="m3 7 2 2 4-4"/><path d="M13 6h8"/><path d="M13 12h8"/><path d="M13 18h8"/>',
    maintenance: '<rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/><path d="M8 14h.01M12 14h.01M16 14h.01M8 18h.01M12 18h.01"/>',
    condition: '<path d="M22 12h-4l-3 9L9 3l-3 9H2"/>',
    solver: '<path d="M9 18h6"/><path d="M10 22h4"/><path d="M15.09 14c.18-.98.65-1.74 1.41-2.5A4.65 4.65 0 0 0 18 8 6 6 0 0 0 6 8c0 1 .23 2.23 1.5 3.5A4.61 4.61 0 0 1 8.91 14"/>',
    qr: '<path d="M3 7V5a2 2 0 0 1 2-2h2"/><path d="M17 3h2a2 2 0 0 1 2 2v2"/><path d="M21 17v2a2 2 0 0 1-2 2h-2"/><path d="M7 21H5a2 2 0 0 1-2-2v-2"/><path d="M7 12h10"/>',
    inventory: '<path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/><path d="m3.3 7 8.7 5 8.7-5"/><path d="M12 22V12"/><path d="m7.5 4.27 9 5.15"/>',
    procurement: '<circle cx="8" cy="21" r="1"/><circle cx="19" cy="21" r="1"/><path d="M2.05 2.05h2l2.66 12.42a2 2 0 0 0 2 1.58h9.78a2 2 0 0 0 1.95-1.57l1.65-7.43H5.12"/>',
    suppliers: '<path d="M14 18V6a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2v11a1 1 0 0 0 1 1h1"/><path d="M15 18H9"/><path d="M19 18h2a1 1 0 0 0 1-1v-3.65a1 1 0 0 0-.22-.62l-3.48-4.35A1 1 0 0 0 17.52 8H14"/><circle cx="17" cy="18" r="2"/><circle cx="7" cy="18" r="2"/>',
    people: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
    invites: '<rect x="2" y="4" width="20" height="16" rx="2"/><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"/>',
    manuals: '<path d="M12 7v14"/><path d="M3 18a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h5a4 4 0 0 1 4 4 4 4 0 0 1 4-4h5a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1h-6a3 3 0 0 0-3 3 3 3 0 0 0-3-3z"/>',
    files: '<path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/>',
    reports: '<path d="M3 3v18h18"/><path d="M18 17V9"/><path d="M13 17V5"/><path d="M8 17v-3"/>',
    analytics: '<path d="M16 7h6v6"/><path d="m22 7-8.5 8.5-5-5L2 17"/>',
    email: '<path d="M14.536 21.686a.5.5 0 0 0 .937-.024l6.5-19a.496.496 0 0 0-.635-.635l-19 6.5a.5.5 0 0 0-.024.937l7.93 3.18a2 2 0 0 1 1.112 1.11z"/><path d="m21.854 2.147-10.94 10.939"/>',
    profile: '<rect x="4" y="2" width="16" height="20" rx="2"/><path d="M9 22v-4h6v4"/><path d="M8 6h.01M16 6h.01M12 6h.01M12 10h.01M12 14h.01M16 10h.01M16 14h.01M8 10h.01M8 14h.01"/>',
    commercial: '<rect x="2" y="5" width="20" height="14" rx="2"/><path d="M2 10h20"/>',
    notifications: '<path d="M10.268 21a2 2 0 0 0 3.464 0"/><path d="M3.262 15.326A1 1 0 0 0 4 17h16a1 1 0 0 0 .74-1.673C19.41 13.956 18 12.499 18 8A6 6 0 0 0 6 8c0 4.499-1.411 5.956-2.738 7.326"/>',
    audit: '<path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/><path d="M12 7v5l4 2"/>',
    recovery: '<path d="M9 14 4 9l5-5"/><path d="M4 9h10.5a5.5 5.5 0 0 1 5.5 5.5 5.5 5.5 0 0 1-5.5 5.5H11"/>',
    appsupport: '<path d="M7.9 20A9 9 0 1 0 4 16.1L2 22Z"/>',
    support: '<circle cx="12" cy="12" r="10"/><path d="m4.93 4.93 4.24 4.24"/><path d="m14.83 9.17 4.24-4.24"/><path d="m14.83 14.83 4.24 4.24"/><path d="m9.17 14.83-4.24 4.24"/><circle cx="12" cy="12" r="4"/>',
    settings: '<path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/><circle cx="12" cy="12" r="3"/>',
    tour: '<path d="M21.42 10.922a1 1 0 0 0-.019-1.838L12.83 5.18a2 2 0 0 0-1.66 0L2.6 9.08a1 1 0 0 0 0 1.832l8.57 3.908a2 2 0 0 0 1.66 0z"/><path d="M22 10v6"/><path d="M6 12.5V16a6 3 0 0 0 12 0v-3.5"/>',
    logout: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5"/><path d="M21 12H9"/>',
    logs: '<rect x="8" y="2" width="8" height="4" rx="1"/><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/><path d="M9 12h6M9 16h6"/>',
    nameplate: '<path d="M12 2H2v10l9.29 9.29c.94.94 2.48.94 3.42 0l6.58-6.58c.94-.94.94-2.48 0-3.42L12 2Z"/><path d="M7 7h.01"/>',
    identify: '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>',
    sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41"/>',
    moon: '<path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/>'
  };
  function icon(name, size) {
    var d = P[name]; if (!d) return '';
    var s = size || 22;
    return '<svg class="pm-ico" width="' + s + '" height="' + s + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + d + '</svg>';
  }
  // map view -> icon name (a few views share/rename)
  var VIEW_ICON = { qr: 'qr', maintenance: 'maintenance' };
  function iconForView(v) { return P[VIEW_ICON[v] || v] ? (VIEW_ICON[v] || v) : 'dashboard'; }

  function hydrateNavIcons() {
    document.querySelectorAll('#drawer nav button[data-view]').forEach(function (b) {
      var v = b.dataset.view, i = b.querySelector('i');
      if (i && P[iconForView(v)]) i.outerHTML = icon(iconForView(v), 19);
    });
    var tour = document.querySelector('#drawer .nav-tour-btn i'); if (tour) tour.outerHTML = icon('tour', 19);
    var out = document.querySelector('#drawer .drawer-logout i'); if (out) out.outerHTML = icon('logout', 19);
  }

  /* ================= light / dark appearance toggle ================= */
  var THEME = {
    key: 'pmAppearance',
    get: function () { try { return localStorage.getItem(THEME.key) || ''; } catch (e) { return ''; } },
    set: function (v) { try { localStorage.setItem(THEME.key, v); } catch (e) {} },
    darkTheme: function () { // pick a dark company theme (never 'light')
      var t = document.body && document.body.dataset ? document.body.dataset.theme : '';
      return (t && t !== 'light') ? t : 'industrial';
    },
    apply: function () {
      var pref = THEME.get(); if (!pref) return; // no personal override -> follow company branding
      document.body.dataset.theme = (pref === 'light') ? 'light' : THEME.darkTheme();
      THEME.paintToggle();
    },
    isLight: function () { return (document.body.dataset.theme === 'light'); },
    toggle: function () {
      var next = THEME.isLight() ? 'dark' : 'light';
      THEME.set(next);
      document.body.dataset.theme = (next === 'light') ? 'light' : THEME.darkTheme();
      THEME.paintToggle();
    },
    paintToggle: function () {
      var btn = document.querySelector('#drawer .nav-theme-btn');
      if (!btn) return;
      var light = THEME.isLight();
      btn.innerHTML = icon(light ? 'moon' : 'sun', 19) + '<span>' + (light ? 'Dark mode' : 'Light mode') + '</span>';
    }
  };

  function init() { ensureButton(); hydrateNavIcons(); THEME.apply(); THEME.paintToggle(); }

  window.PMIcon = icon;
  window.PMTheme = THEME;
  window.PMHelp = {
    init: init,
    openHelp: openHelp,
    startTour: startTour,
    maybeStartTour: maybeStartTour,
    onNavigate: function (v) { if (v) window.currentView = v; }
  };
})();
