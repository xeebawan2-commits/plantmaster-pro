# Edge functions — 13 September 2026

All 11 Supabase Edge Functions, downloaded from the live project
`dpmmenwziplixrgylapy`.

The files arrived with scrambled names (`eb.txt`, `kg.txt` and so on) to get
past the upload filter. Each was identified by reading its code — the tables
it queries, the environment variables it reads and the routes it serves —
and renamed to the real function name.

| File | Function | What it does |
|---|---|---|
| `public-api.ts` | `public-api` | Read-only REST API for integrations. API-key auth, 8 endpoint groups |
| `web-push.ts` | `web-push` | Push notifications: subscribe, unsubscribe, send |
| `voice-translate.ts` | `voice-translate` | Converts spoken Urdu dictation into technical English |
| `condition-analyzer.ts` | `condition-analyzer` | Audio and vibration analysis of equipment recordings |
| `vision-scanner.ts` | `vision-scanner` | Camera scanning, writes to `file_metadata` |
| `ingest-manual.ts` | `ingest-manual` | Indexes equipment manuals for AI search (PDFs to Gemini, v5 FAST) |
| `delete-manual.ts` | `delete-manual` | Deletes a manual, its storage file and AI chunks. Owner/manager only |
| `smart-responder.ts` | `smart-responder` | AI troubleshooting grounded in indexed manual chunks |
| `platform-admin-api.ts` | `platform-admin-api` | Control Center backend — 27 tables, QA runs, billing, support |
| `daily-reports.ts` | `daily-reports` | Daily maintenance summary by email via Resend, GitHub Actions cron |
| `health-monitor.ts` | *(see note)* | Health checks on database, storage and Gemini; writes `system_incidents` |

## Note on the last one

`health-monitor.ts` was downloaded as the `qa-runner` function, but its code
is a health monitor: it authenticates with `HEALTH_MONITOR_TOKEN` and checks
that the database, storage bucket and Gemini API are responding, recording
failures in `system_incidents`.

The actual QA test-run logic (`qa_test_runs`, `qa_environments`,
`qa_manual_checks`) lives inside `platform-admin-api.ts`.

So either the function named `qa-runner` in the dashboard contains health
monitoring code, or a file was downloaded from the wrong function. Worth a
quick look when convenient. It does not affect anything running today —
both are backed up either way.

## Security check

Every file was scanned for hardcoded credentials before archiving:
JWTs (`eyJ...`), Supabase secret keys, Google API keys (`AIza...`) and
Resend keys (`re_...`).

**Nothing was found.** All eleven read their secrets from `Deno.env.get(...)`,
which is correct. These files can be stored or shared without exposing
access to your project.

## Environment variables these functions expect

Set under Dashboard → Edge Functions → Secrets. They are **not** in this
backup and would need re-entering on a rebuild:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY` (some also accept `SUPABASE_SECRET_KEY`)
- `GEMINI_API_KEY`
- `HEALTH_MONITOR_TOKEN`
- `DAILY_REPORT_TOKEN` and a Resend API key for `daily-reports`
- VAPID keys for `web-push`
- `PLANTMASTER_SECRET_KEY` / `SUPABASE_SECRET_KEYS` for `platform-admin-api`

Write these down somewhere safe. Losing them breaks the functions even if
the code survives.

## Redeploying

Dashboard → Edge Functions → select the function → **Edit** → paste the file
contents → **Deploy**.

For `public-api`, check afterwards that **"Verify JWT with legacy secret"**
is still **OFF**. It switches itself back on after an update — a known
Supabase bug — and when on, the gateway rejects every request before your
code runs.
