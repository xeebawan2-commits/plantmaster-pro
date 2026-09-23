# PlantMaster Pro — Asset Map

A folder-by-folder map of how every part of the product connects to its **database (schema/SQL)**, its **edge functions**, and its **keys/secrets** — one folder per section, for all three properties.

## What each section folder contains

| File | Purpose |
|---|---|
| `README.md` | The four items tied together: (1) app section/UI files, (2) schema/SQL, (3) edge function, (4) keys/secrets. |
| `schema.sql` | The **actual DDL** (tables + functions) this section uses, extracted from the migrations, repair scripts, or the live schema snapshot. Source of each block is noted in a comment. |
| `edge-function.md` | Which edge functions this section calls. Vendored ones are copied into `edge-functions/<name>/`; live-only ones list the `supabase functions download` command. |
| `edge-functions/` | Present only when the section calls a vendored edge function — the real function source. |

## The three properties

### app.hsbfix.org — the PWA (customer app)
The product itself: a mobile-first PWA (installable, offline-capable) for plant maintenance. Signed-in, multi-tenant.

| Section | What it does | Schema | Edge fn |
|---|---|:--:|:--:|
| [`01_dashboard_and_shell`](01-app.hsbfix.org/01_dashboard_and_shell/) | Module dashboard, navigation shell, auth session, org/plant context. | ✓ | — |
| [`02_work_orders`](01-app.hsbfix.org/02_work_orders/) | Create and track jobs against a specific asset with priority and status. | ✓ | — |
| [`03_asset_register`](01-app.hsbfix.org/03_asset_register/) | Equipment recorded with code, type, department and running state. | ✓ | — |
| [`04_reliability_analytics`](01-app.hsbfix.org/04_reliability_analytics/) | MTTR, MTBF, total downtime, work-order and asset-state breakdowns. | ✓ | — |
| [`05_ai_problem_solver`](01-app.hsbfix.org/05_ai_problem_solver/) | Plain-language fault search across manuals, experience and verified cases; confidence + sources. | ✓ | ✓ |
| [`06_condition_monitoring`](01-app.hsbfix.org/06_condition_monitoring/) | Phone microphone + accelerometer capture machine sound/vibration for screening & trending. | ✓ | ✓ |
| [`07_unified_scanner`](01-app.hsbfix.org/07_unified_scanner/) | QR/barcode/document/nameplate scanning linking a machine to its record & manuals. | ✓ | ✓ |
| [`08_manuals_and_files`](01-app.hsbfix.org/08_manuals_and_files/) | Upload equipment manuals; chunk + embed for AI search; storage accounting. | ✓ | ✓ |
| [`09_operations_daily_logs`](01-app.hsbfix.org/09_operations_daily_logs/) | Daily logs, attendance, shift handovers, checklists, PM plans. | ✓ | — |
| [`10_inventory_and_spares`](01-app.hsbfix.org/10_inventory_and_spares/) | Spares and tools with append-only stock ledgers. | ✓ | — |
| [`11_procurement`](01-app.hsbfix.org/11_procurement/) | Material requests, purchase orders and supplier records. | ✓ | — |
| [`12_reports_export`](01-app.hsbfix.org/12_reports_export/) | Export any module for a date range as CSV, Excel, Word or PDF. | ✓ | — |
| [`13_daily_plant_report`](01-app.hsbfix.org/13_daily_plant_report/) | Auto-generated plain-text daily summary, reviewed then emailed. | ✓ | ✓ |
| [`14_support_and_complaints`](01-app.hsbfix.org/14_support_and_complaints/) | In-app support threads and complaints to the platform owner. | ✓ | — |
| [`15_push_notifications`](01-app.hsbfix.org/15_push_notifications/) | Web-push alerts for work orders and alarms when the app is closed. | ✓ | ✓ |
| [`16_billing_and_entitlements`](01-app.hsbfix.org/16_billing_and_entitlements/) | Subscription, plan limits and per-company feature entitlements the app enforces. | ✓ | — |

### admin.hsbfix.org — Control Center
The platform owner console: manage companies, users, plans, invitations, storage, support. Super-admin only.

| Section | What it does | Schema | Edge fn |
|---|---|:--:|:--:|
| [`01_dashboard`](02-admin.hsbfix.org/01_dashboard/) | Platform overview: counts of companies, accounts, requests, storage. | ✓ | — |
| [`02_companies`](02-admin.hsbfix.org/02_companies/) | List/manage companies: status, plan, complimentary access, delete. | ✓ | — |
| [`03_accounts_and_users`](02-admin.hsbfix.org/03_accounts_and_users/) | User accounts: create login, reset password, ban/unban, delete. | ✓ | ✓ |
| [`04_signup_requests`](02-admin.hsbfix.org/04_signup_requests/) | Incoming enquiries: approve (+create login), reject, delete, purge. | ✓ | ✓ |
| [`05_owner_invitations`](02-admin.hsbfix.org/05_owner_invitations/) | Invite owners; create login; revoke; delete; cleanup. | ✓ | ✓ |
| [`06_plans_and_packages`](02-admin.hsbfix.org/06_plans_and_packages/) | Create/edit subscription packages, prices, limits, modules; activate/deactivate. | ✓ | — |
| [`07_storage_files`](02-admin.hsbfix.org/07_storage_files/) | View/download/delete customer-uploaded files across companies. | ✓ | ✓ |
| [`08_support_tickets`](02-admin.hsbfix.org/08_support_tickets/) | Platform support tickets: resolve, reopen, delete, purge. | ✓ | — |
| [`09_activity_and_backups`](02-admin.hsbfix.org/09_activity_and_backups/) | Audit/action log and Supabase backup shortcuts; report exports. | ✓ | — |

### hsbfix.org — marketing site
Public static site: features, pricing, screenshots, demo, legal, and the signup enquiry form.

| Section | What it does | Schema | Edge fn |
|---|---|:--:|:--:|
| [`01_marketing_pages`](03-hsbfix.org/01_marketing_pages/) | Static marketing: home, pricing, guide, demo, screenshots, resources, FAQ, legal. | — | — |
| [`02_signup_enquiry`](03-hsbfix.org/02_signup_enquiry/) | Prospect submits an enquiry; owner is emailed; row lands in signup_requests. | ✓ | ✓ |

## Shared backbone (all three properties)

- **Supabase project** `dpmmenwziplixrgylapy` — one Postgres DB + Auth + Storage + Edge Functions, shared by all three.
- **Anon/publishable key** `sb_publishable_TlKlrk7ulAG8G7EptLCllA_Rbgt7YXY` — public, safe in the browser because Row-Level Security guards every table.
- **Storage bucket** `plant-files`.
- Public config lives in `config.js` (app) and `admin/config.js`. Server secrets live only in **Supabase → Edge Functions → Secrets**, never in the browser.

## Keys & secrets — master list

See [`KEYS.md`](KEYS.md) for every key, where it lives, and which sections use it.

## Edge functions — master list

See [`EDGE-FUNCTIONS.md`](EDGE-FUNCTIONS.md) for all 11 functions, vendored vs live-only, and their secrets.

## Database sources

- `supabase/migrations/0001–0009` — the versioned schema (foundation → operations → inventory → knowledge/files → commercial → RPCs → storage → grants → edge support).
- `supabase/repairs/R1–R5` — idempotent fixes applied to the live DB (org creation, control center, verify, company features, final pricing).
- `reference/master-package/05-DATABASE/03-live-schema-snapshot/` — a dump of the **actual production** schema (83 tables / 73 functions), used here as the source for anything not modelled in the repo migrations.

> Note: the repo migrations model a subset of the live schema. Where a section uses a table/function that only exists live, `schema.sql` says `(LIVE snapshot)` in the source comment. The live database is the source of truth; do not run the repo migrations against it.
