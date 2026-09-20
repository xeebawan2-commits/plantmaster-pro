# PlantMaster Pro — deployment runbook

> # ⛔ STOP — read `STOP-READ-FIRST.md` before running any deploy command
>
> Your live database has **87 tables and 14 edge functions**, not the 55 and 8
> these migrations assume. `npm run db:push` would create **5 duplicate
> tables** and rewrite permissions on 32 tables it does not know about.
> `npm run functions:deploy` would overwrite **7 working functions**.
>
> **`npm run deploy` (the app) is safe and carries all the real fixes.**
> Everything else is on hold until the migrations are adapted.

Three properties ship from this one repository.

| Property | Source | Build output | Pages project |
|---|---|---|---|
| `hsbfix.org` | `site/` | `dist/site` | `plantmaster-site` |
| `app.hsbfix.org` | repo root | `public/` | `plantmaster-pro` |
| `admin.hsbfix.org` | `admin/` | `dist/admin` | `plantmaster-admin` |

`public/` and `dist/` are build artefacts and are git-ignored. Never edit them
by hand — `scripts/build.mjs` regenerates them and your change will vanish.

---

## 0. Before anything else

```bash
npm install
npm run verify      # must be green before you deploy
```

`npm run verify` runs five independent gates:

| Gate | What it proves |
|---|---|
| `verify:db` | All 9 migrations apply to a real Postgres, and 66 RLS / RPC / tenant-isolation assertions hold |
| `verify:fn` | Every edge function the client calls exists, type-checks, is declared in `config.toml`, and contains no hard-coded secret |
| `verify:push` | The hand-written RFC 8291 / 8292 web-push implementation encrypts a payload a real browser can decrypt, and the VAPID JWT verifies |
| `verify:pwa` | Manifest, real icon dimensions, screenshots, service worker, asset links and security headers |
| `verify:links` | Every `src`, `href` and local import in all three builds resolves to a file that exists |

---

## 1. Database

The migration suite is idempotent, so it converges an existing live database
rather than assuming an empty one.

```bash
supabase link --project-ref <your-project-ref>
supabase db push            # or: npm run db:push
```

Apply order is fixed by filename:

| File | Contents |
|---|---|
| `0001_foundation.sql` | Enums, `organizations`/`plants`/`members`, auth helper functions, `pm_standard_policies` |
| `0002_operations.sql` | Assets, work orders, checklists, permits, LOTO, attendance, shifts |
| `0003_inventory_procurement.sql` | Spares, tools, stock ledger, suppliers, purchase orders |
| `0004_knowledge_files.sql` | Manuals, document chunks, files, notifications, push subscriptions |
| `0005_platform_commercial.sql` | Plans, features, complaints, incidents, platform admins |
| `0006_rpc.sql` | Client-callable RPCs |
| `0007_storage_recovery.sql` | Storage reserve/finalize, quota, soft delete, restore |
| `0008_grants_hardening.sql` | Revokes, grants, default privileges |
| `0009_edge_function_support.sql` | Columns, indexes and helpers the edge functions need |

> **`0009` needs `pg_trgm`.** It is present on Supabase. The migration degrades
> gracefully if the extension cannot be created (the local PGlite test harness
> has no contrib modules) — only the ILIKE index is skipped.

### Seeding the platform operator

Platform staff are not tenant members; they are rows in `platform_admins`.
Until at least one exists, `admin.hsbfix.org` will refuse **everyone**,
including you. Run once, in the SQL editor:

```sql
insert into public.platform_admins (user_id, email)
select id, email from auth.users where email = 'you@hsbfix.org'
on conflict do nothing;
```

---

## 2. Edge functions

```bash
supabase functions deploy smart-responder condition-analyzer vision-scanner \
  ingest-manual delete-manual voice-translate web-push daily-reports
# or: npm run functions:deploy
```

### Required secrets

```bash
supabase secrets set \
  GEMINI_API_KEY=...          \
  VAPID_PUBLIC_KEY=...        \
  VAPID_PRIVATE_KEY=...       \
  VAPID_SUBJECT=mailto:support@hsbfix.org \
  PUSH_INTERNAL_TOKEN=...     \
  DAILY_REPORTS_TOKEN=...     \
  RESEND_API_KEY=...          \
  REPORT_FROM="PlantMaster Pro <reports@hsbfix.org>"
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are
injected by the platform — do not set them yourself.

Generate a VAPID pair (any machine with Node):

```bash
npx web-push generate-vapid-keys
```

The **public** key must also be pasted into `push-client.js`
(`VAPID_PUBLIC_KEY`). If the two disagree, subscriptions are created but every
delivery fails with a 403 from the push service.

Generate the two shared tokens with `openssl rand -base64 32`.

### JWT gate

`supabase/config.toml` sets `verify_jwt = false` for `web-push` and
`daily-reports` only, because the scheduler has no user JWT. Both compare
their own shared token in constant time before doing any work. Every other
function keeps `verify_jwt = true` **and** re-checks organization membership
against the database — the `organization_id` in a request body is never
trusted.

### GitHub Actions secrets

`.github/workflows/push-poller.yml` (every 5 min) and `daily-reports.yml`
(05:30 UTC = 11:00 PKT) need repository secrets:

| Secret | Value |
|---|---|
| `PUSH_FN_URL` | `https://<ref>.supabase.co/functions/v1/web-push` |
| `PUSH_INTERNAL_TOKEN` | same as the function secret |
| `SUPABASE_ANON_KEY` | publishable key from `config.js` |
| `DAILY_REPORTS_FN_URL` | `https://<ref>.supabase.co/functions/v1/daily-reports` |
| `DAILY_REPORTS_TOKEN` | same as the function secret |

---

## 3. Storage

One private bucket, `plant-files`. Object paths are
`<organization_id>/<plant_id>/...` and the storage policies parse that prefix,
so **any** other layout is unreadable by design.

Uploads go through `reserve_upload` → `finalize_upload` / `cancel_upload`.
Reservations expire after an hour; exceeding the plan quota raises SQLSTATE
`53100`.

---

## 4. Front ends

```bash
npm run deploy         # app   -> plantmaster-pro
npm run deploy:site    # site  -> plantmaster-site
npm run deploy:admin   # admin -> plantmaster-admin
npm run deploy:all     # all three
```

Each build stamps a content hash onto local `src`/`href` references and writes
the same hash into the service worker's `VERSION`, so a deploy always
invalidates the previous cache.

### DNS

| Host | Target |
|---|---|
| `hsbfix.org`, `www` | `plantmaster-site.pages.dev` |
| `app` | `plantmaster-pro.pages.dev` |
| `admin` | `plantmaster-admin.pages.dev` |

### Supabase Auth redirect URLs

Add all three origins under **Authentication → URL configuration**, matching
`supabase/config.toml`. A missing entry breaks password reset and magic links
with a redirect error that does not say why.

---

## 5. Local preview

```bash
npm run dev
```

Serves app on `:8080`, site on `:8081`, admin on `:8082` with SPA fallback and
`no-store`.

---

## 6. Post-deploy smoke test

1. `https://app.hsbfix.org` loads and installs (address bar shows the install icon).
2. Sign in, open the dashboard, create a work order.
3. Enable alerts, then run the **Push poller** workflow manually — the phone buzzes.
4. Upload a small PDF manual; status reaches `indexed` with a chunk count.
5. Ask the Problem Solver something answerable from that manual; the reply cites it.
6. `https://admin.hsbfix.org` — a normal customer account must be refused.
7. `curl -I https://app.hsbfix.org/.well-known/assetlinks.json` → `200`, `application/json`.
8. Install the Play internal-test build: **no URL bar** means asset links verified.

---

## 7. Rollback

Cloudflare Pages keeps every deployment; promote the previous one from the
dashboard. Migrations are forward-only — write a new `00NN_*.sql` that undoes
the change rather than editing a file that has already been applied.
