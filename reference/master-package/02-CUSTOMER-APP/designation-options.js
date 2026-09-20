// PlantMaster Pro v4.13.2 — Designation options (job titles)
// Attaches a dropdown of plant designations to EVERY "Designation" field in the app
// (Add Worker, Edit Worker, Work Done, and anything else that uses it).
// It's a datalist: the dropdown shows all options, but workers can still type
// any custom title — nothing is restricted.
(() => {
  const DESIGNATIONS = [
    'Worker',
    'Operator',
    'Assistant Operator',
    'Senior Operator',
    'Technician',
    'Senior Technician',
    'Checker',
    'Quality Control Officer',
    'Technical Officer',
    'Senior Technical Officer',
    'Engineer',
    'Mechanical Engineer',
    'Electrical Engineer',
    'Production Engineer',
    'Utility Engineer',
    'Power House Engineer',
    'Supervisor',
    'Assistant Manager',
    'Deputy Manager',
    'Manager',
    'Admin Officer',
    'Time Officer'
  ];

  const LIST_ID = 'pm-designations';

  if (!document.getElementById(LIST_ID)) {
    const dl = document.createElement('datalist');
    dl.id = LIST_ID;
    dl.innerHTML = DESIGNATIONS.map((d) => `<option value="${d}">`).join('');
    document.body.appendChild(dl);
  }

  const attach = (el) => {
    if (el.getAttribute('list') === LIST_ID) return;
    el.setAttribute('list', LIST_ID);
    if (!el.placeholder) el.placeholder = 'Tap for options or type';
  };

  // bind now + bind any designation field the app renders later (dialogs are dynamic)
  document.querySelectorAll('input[name="designation"]').forEach(attach);
  const obs = new MutationObserver((muts) => {
    for (const m of muts) {
      for (const n of m.addedNodes) {
        if (n.nodeType !== 1) continue;
        if (n.matches && n.matches('input[name="designation"]')) attach(n);
        if (n.querySelectorAll) n.querySelectorAll('input[name="designation"]').forEach(attach);
      }
    }
  });
  obs.observe(document.documentElement, { childList: true, subtree: true });
})();
