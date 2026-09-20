# ⛔ STOP — do not run `npm run db:push` or `npm run functions:deploy`

Your screenshots changed the picture. I built the migrations by reading your
application's code, because the live database was unreachable from my
environment. I said at the time that they were written to "merge safely."

**Now that I can see the real database, that claim was wrong.** Running
`db:push` today would damage your project. Here is exactly why, and what to do
instead.

---

## What I assumed vs. what is actually there

| | I assumed | Reality (from your screenshots) |
|---|---|---|
| Tables | 55 | **87** |
| Edge functions | 8 | **14** |
| AI usage table | `ai_usage_events` | **`ai_usage`** — 25 rows of real data |
| Complaints | `app_complaints` | **`platform_support_tickets`** |
| Complaint messages | `app_complaint_messages` | **`platform_support_messages`** |
| Feature flags | `organization_features` | **`organization_entitlements`** + `company_feature_grants` |
| Report log | `daily_report_runs` | **`report_dispatches`** |
| AI solver function | `smart-responder` | **`gemini-problem-solver`** |

Your live database is **substantially larger and more developed** than what the
application code revealed. It has whole subsystems I never saw: QA tooling
(`qa_test_runs`, `qa_manual_checks`, `qa_test_results`), billing
(`billing_events`, `organization_subscriptions`, `usage_counters`,
`quota_overrides`), operations (`backup_jobs`, `restore_drills`,
`health-monitor`), a public API (`api_keys`, `public-api`), signup flow
(`signup_requests`, `signup-notify`, `create-owner`), and sensors
(`sensor_devices`, `measurement_points`, `condition_alarms`).

---

## What `db:push` would actually do

**It would not overwrite your tables** — every statement is `if not exists`,
so your 87 tables and their data survive. The damage is subtler and worse:

### 1. Five duplicate tables, splitting your data in two

It would create `ai_usage_events` **alongside** your existing `ai_usage`.
Same for complaints, entitlements and report logs. You would end up with two
tables for the same job. New writes go to one, your 25 existing AI-usage rows
and all your support tickets stay in the other. Reports silently disagree, and
quota counting reads the empty one.

### 2. It would re-grant permissions across every table

`0008_grants_hardening.sql` runs `revoke all ... on all tables in schema public
from anon`, then re-grants only what *my* 55-table model expects. Your other
32 tables — billing, QA, API keys, sensors — are not in that model. Their
carefully-set permissions get rewritten by a script that does not know they
exist.

### 3. It would collide with your existing policies

Your screenshots show policies named `pm_block_viewer_insert`,
`pm_block_viewer_update`, `pm_block_viewer_delete` applied to `public` — a
naming scheme my `pm_standard_policies()` also uses. Overlapping policy names
on the same tables is how you get a silent authorization change.

---

## What `functions:deploy` would do

It would **overwrite 7 of your 14 live functions** with my versions:

`condition-analyzer` · `daily-reports` · `delete-manual` · `ingest-manual` ·
`vision-scanner` · `voice-translate` · `web-push`

Mine were written against my 55-table model. `delete-manual` writes to
`file_metadata` and `audit_logs`; `ingest-manual` writes `chunk_count` and
`heading` columns that **may not exist** in your live `manuals` /
`document_chunks`. `daily-reports` reads `DAILY_REPORTS_TOKEN` and
`REPORT_FROM`, and your screenshot shows **neither secret is set** — that
function would fail on first run.

It would also add `smart-responder` as a 15th function while your app keeps
calling `gemini-problem-solver`.

---

## What is safe right now

| Action | Safe? | Why |
|---|---|---|
| `npm run deploy` (app) | ✅ **Yes** | Static files only. Does not touch the database. |
| `npm run deploy:admin` | ⚠️ **Not yet** | The console calls RPCs named for tables you do not have. |
| `npm run deploy:site` | ❌ **No** | Would delete your `demo`/`guide`/`pricing`/`resources` pages. |
| `npm run db:push` | ❌ **No** | Creates 5 duplicate tables, rewrites grants on 32 unknown tables. |
| `npm run functions:deploy` | ❌ **No** | Overwrites 7 working functions with schema-mismatched versions. |
| The **app-layer fixes** | ✅ **Yes** | See below — these are the real, safe wins. |

---

## What you should actually take

The genuinely valuable work does **not** require the database at all. These
are fixes to bugs in your live application, and they deploy with
`npm run deploy`:

1. **Push notifications never worked.** `push-client.js` called
   `alreadyDismissed()`, a function that was never defined. The
   ReferenceError aborted setup, so **no device ever subscribed**. It also
   read `sessionId` as an auth token, which was never a token, and used the
   supabase-js v1 session shape. All fixed.

2. **The service worker precached URLs it could never match** (`?v=` query
   strings), so the offline cache was largely dead, and there was no
   navigation fallback. Rewritten with `ignoreSearch` matching, navigation
   preload, a runtime cache cap and a real offline page.

3. **A secret token was committed in plain text** to your public repo. Removed
   from the code — **but still in your git history at `6c367eb`. Rotate it.**

4. **`public/` was missing 7 files** that the app referenced, and duplicated
   the source tree. Now generated by a build with content-hash cache busting.

5. The PWA is now installable and Play-ready: real icon dimensions,
   screenshots, manifest, asset links, security headers.

That is a working push system, a working offline mode and a Play-ready app —
none of which needs a single database change.

---

## The three options for the database work

### Option A — Take the app fixes only (recommended)

```bash
npm run deploy          # the PWA, with all the fixes above
```

Leave the database and functions exactly as they are. You get every safe
improvement today, with zero risk. The migrations stay in the repo as
documentation of an intended design.

### Option B — Adapt the migrations to your real schema

I rename my tables to match yours (`ai_usage_events` → `ai_usage`,
`app_complaints` → `platform_support_tickets`, and so on), drop the tables you
already cover, and narrow `0008` so it only touches tables it owns.

For this I need, from the SQL Editor:

```sql
-- 1. exact columns of the tables I would touch
select table_name, column_name, data_type
from information_schema.columns
where table_schema='public'
  and table_name in ('ai_usage','manuals','document_chunks','notifications',
                     'push_subscriptions','organizations','organization_members',
                     'platform_support_tickets','platform_support_messages',
                     'organization_entitlements','report_dispatches',
                     'subscription_plans','file_metadata','audit_logs')
order by table_name, ordinal_position;

-- 2. existing policies, so I do not collide with them
select tablename, policyname, cmd, roles
from pg_policies where schemaname='public' order by tablename, policyname;

-- 3. existing functions
select routine_name from information_schema.routines
where routine_schema='public' order by routine_name;
```

Paste the results back and I will rework the migrations against reality, then
re-run the 66 tests with your actual column names.

### Option C — Keep the migrations as a greenfield reference

Use them only if you ever rebuild the project from scratch. Your live database
already does more than they describe.

---

## Two things to fix regardless of which option you choose

1. **Rotate `PUSH_INTERNAL_TOKEN`.** It is readable in your public git history
   at commit `6c367eb`. Your Supabase secret is already set, so just generate
   a new value, update it in Supabase → Edge Functions → Secrets, and update
   the matching GitHub Actions secret.

2. **Add a delete-account page.** Google Play will not approve the app without
   a publicly reachable one. Your `hsbfix.org` does not have it. Copy
   `site/delete-account.html` from this package into your `hsbfix-org`
   repository.

---

## My mistake, plainly

I described the migrations as safe to apply to your live database. They were
verified against a *reconstruction* of your schema, not the schema itself —
and 66 passing tests against the wrong model proves only that the model is
self-consistent. I should have been clearer that "idempotent" protects against
re-running the same script, **not** against a schema that differs from the
assumption. Your screenshots caught it before any damage; thank you for
sending them.
