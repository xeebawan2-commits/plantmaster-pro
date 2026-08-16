# PlantMaster Pro v4.4.0 — Operations Build

This is an integrated update to the existing PlantMaster v4 application. It does not create a separate app and does not intentionally delete existing Supabase records.

## Required deployment order

1. In the existing Supabase project SQL Editor, run `schema-phase5-operations.sql` once.
2. Upload the runtime files from this folder to the existing GitHub Pages repository root.
3. Keep the same `config.js` and Supabase project.
4. Reload the HTTPS GitHub Pages URL. If an older cached version appears, close all installed-PWA/browser tabs and reopen once.

The SQL migration is additive/idempotent where practical. It adds columns, tables, policies, indexes, an owner hard-delete guard, and the invitation-acceptance RPC. It does not truncate or drop business tables.

## Implemented in this build

- Removed the on-screen Back button.
- Browser/Android Back navigates app history; double Back from Home leaves the app.
- New responsive operational UI and module toolbar.
- Worker directory fields: employee ID, designation, skills, contact, default shift.
- Owner worker editor, action permissions, deactivate and recover.
- Invitation worker metadata and secure invitation acceptance workflow.
- Duty roster, attendance, shift handover and daily operational logs.
- Worker name, designation, shift and timestamp attribution on new operational completion records.
- Checklist template builder with all requested field families.
- Required checklist items, units, minimum/maximum limits and automatic failed-item alarms.
- Checklist execution log and supervisor approval.
- Maintenance plans, Work Done workflow and separate completion history.
- Work-order Work Done and Reopen workflow with tools, parts, measurements, root cause, corrective action and downtime.
- Spare receive/issue/adjust transactions and stock validation.
- Tool checkout, return, inspection and calibration transaction history.
- Owner soft-remove, Recovery Bin, restore and owner-only permanent erase.
- Audit entries for the new operational actions.
- Contextual Guides for the upgraded operational modules.
- Voice-to-text controls on upgraded text/search fields where browser HTTPS speech recognition is available.
- CSV export for people/roster tabs.
- Updated service-worker cache to v4.4.0.

## Validation completed

- JavaScript syntax checks passed for `app.js`, `operations.js`, and `offline.js`.
- HTML parser check passed for `index.html`.
- Local static HTTP loading returned 200.
- Service-worker asset list includes the new operations module.

## Still in active development

This build is not labelled as the final complete release. Remaining master-checklist work includes deeper report formats (Excel/Word/PDF), document letterhead editor, complete daily-email delivery/retry backend, full support/experience approval workflow, manual extraction/chunking, secure Gemini Edge Function execution and citations, printable QR label layouts, attachment/signature capture across every completion form, complete permission enforcement for every non-destructive action, and full authenticated browser/device regression testing against staging.
