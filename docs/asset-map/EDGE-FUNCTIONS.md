# Edge Functions — master list

All 11 functions run on Supabase at `https://dpmmenwziplixrgylapy.supabase.co/functions/v1/<name>`.
Shared helpers live in `supabase/functions/_shared/` (`guard.ts` = auth + CORS + the `gemini()` helper; `webpush.ts` = web-push signing).

| Function | Called by | Vendored? | Secrets it reads | What it does |
|---|---|---|---|---|
| `smart-responder` | app (solver.js, app.js) | ✓ | GEMINI_API_KEY, SUPABASE_* (via guard) | AI problem-solver deep search |
| `condition-analyzer` | app (condition.js) | ✓ | GEMINI_API_KEY, SUPABASE_* | Analyses machine sound/vibration recordings |
| `vision-scanner` | app (scanner.js) | ✓ | GEMINI_API_KEY, SUPABASE_* | OCR / nameplate / document understanding |
| `voice-translate` | app (voice-input.js) | ✓ | GEMINI_API_KEY, SUPABASE_* | Voice → text, English/Urdu |
| `ingest-manual` | app (app.js) | ✓ | GEMINI_API_KEY, SUPABASE_* | Chunks + embeds an uploaded manual |
| `delete-manual` | app (app.js) | ✓ | SUPABASE_* (via guard) | Removes a manual and its chunks |
| `web-push` | app (push-client.js) | ✓ | VAPID_*, PUSH_INTERNAL_TOKEN, SUPABASE_* | Sends web-push notifications |
| `daily-reports` | cron / backend | ✓ | DAILY_REPORTS_TOKEN, REPORT_FROM, RESEND_API_KEY, SUPABASE_* | Builds + emails the daily plant report |
| `create-owner` | admin (app.js) | ✗ live-only | SUPABASE_SERVICE_ROLE_KEY | Creates an owner auth user + login |
| `platform-admin-api` | admin (app.js) | ✗ live-only | SUPABASE_SERVICE_ROLE_KEY | Signed storage URLs + admin storage delete |
| `signup-notify` | site (signup.html) | ✗ live-only | RESEND_API_KEY, SIGNUP_FROM, SIGNUP_ALERT_TO | Emails the owner when someone enquires |

## Vendored vs live-only

- **Vendored (8):** source is in `supabase/functions/` and copied into the relevant section folders under `edge-functions/`. Safe to read and redeploy from the repo.
- **Live-only (3):** `create-owner`, `platform-admin-api`, `signup-notify` run in production but their source is **not** in the repo. Before editing any of them, pull the current source first:

```
npx supabase functions download create-owner
npx supabase functions download platform-admin-api
npx supabase functions download signup-notify
```

## Deploying a function

```
npx supabase functions deploy <name> --project-ref dpmmenwziplixrgylapy
```
Secrets are managed in the Supabase dashboard (Edge Functions → Secrets), not in code.
