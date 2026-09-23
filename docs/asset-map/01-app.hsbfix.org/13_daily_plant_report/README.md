# 13 daily plant report

_Auto-generated plain-text daily summary, reviewed then emailed._

## 1. App section / UI
| File | Role |
|---|---|
| `app.js` | Daily report screen, recipient, send |

## 2. Schema / SQL
Full DDL for this section is in **`schema.sql`** (extracted from the sources below).

**Tables:** `work_orders`, `checklist_runs`, `attendance`, `assets`, `daily_logs`

**Defined in:** 0002_operations.sql

## 3. Edge function
See **`edge-function.md`**. Functions: `daily-reports`

## 4. Keys / secrets
| Key | Where it lives | What it is |
|---|---|---|
| `SUPABASE_URL` | config.js (public) | Supabase project URL (public). Same for all three properties. |
| `SUPABASE_SERVICE_ROLE_KEY` | Edge Function secret (server-only) | Supabase service-role secret. SERVER-ONLY, set in Edge Function secrets. Never in the browser. |
| `RESEND_API_KEY` | Edge Function secret (server-only) | Resend email API key. Edge Function secret. |
| `DAILY_REPORTS_TOKEN` | Edge Function secret (server-only) | Shared secret protecting the daily-reports cron function. Edge Function secret. (MISSING in live — must be set.) |
| `REPORT_FROM` | Edge Function secret (server-only) | From-address for the daily report email. Edge Function secret. (MISSING in live — must be set.) |

