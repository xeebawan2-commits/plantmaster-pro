# Keys & Secrets — master list

Two kinds of value are used across the product:

- **Public config** — shipped in the browser (`config.js`, `admin/config.js`). Safe to expose because Row-Level Security guards the database. Anyone can read these in page source; that is by design.
- **Server secrets** — set only in **Supabase → Project → Edge Functions → Secrets**. Never appear in the browser or the repo. Rotating one only requires updating it in Supabase and redeploying the function.

## Public config

| Key | File | Value / note |
|---|---|---|
| `SUPABASE_URL` | `config.js`, `admin/config.js` | `https://dpmmenwziplixrgylapy.supabase.co` |
| `SUPABASE_ANON_KEY` | `config.js`, `admin/config.js` | `sb_publishable_TlKlrk7ulAG8G7EptLCllA_Rbgt7YXY` (publishable) |
| `FILE_BUCKET` | `config.js`, `admin/config.js` | `plant-files` |
| `CUSTOMER_APP_URL` | `admin/config.js` | `https://app.hsbfix.org` |
| `WHATSAPP_NUMBER` | `admin/config.js` | `923162364074` |
| VAPID **public** key | `push-client.js` line 11 | Web-push public key (public half; safe in browser) |

## Server secrets (Supabase Edge Function secrets)

| Secret | Used by (edge functions) | Purpose | Status |
|---|---|---|---|
| `SUPABASE_SERVICE_ROLE_KEY` | web-push, daily-reports, create-owner, platform-admin-api, + all guard-based fns | Full DB access, server-side only | set |
| `GEMINI_API_KEY` | smart-responder, condition-analyzer, vision-scanner, voice-translate, ingest-manual (via `_shared/guard.ts`) | Google Gemini AI | set |
| `RESEND_API_KEY` | daily-reports, signup-notify | Transactional email | set |
| `VAPID_PUBLIC_KEY` | web-push | Web-push (public half) | set |
| `VAPID_PRIVATE_KEY` | web-push | Web-push signing (private) | set |
| `VAPID_SUBJECT` | web-push | Web-push subject (mailto:) | set |
| `PUSH_INTERNAL_TOKEN` | web-push | Guards the push endpoint | set — **rotate** (was in git history at 6c367eb) |
| `DAILY_REPORTS_TOKEN` | daily-reports | Guards the daily-report cron | **MISSING — must be set** |
| `REPORT_FROM` | daily-reports | From-address for the daily email | **MISSING — must be set** |
| `HEALTH_MONITOR_TOKEN` | (health check) | Guards a health endpoint | set |
| `PLANTMASTER_SECRET_KEY` | (internal) | App-internal signing | set |
| `SIGNUP_FROM` | signup-notify | From-address for signup alerts | set |
| `SIGNUP_ALERT_TO` | signup-notify | Where enquiry alerts are sent | set |
| `CLOUDFLARE_API_TOKEN` | (deploy, GitHub Actions) | Deploys the three Workers | GitHub secret |
| `CLOUDFLARE_ACCOUNT_ID` | (deploy, GitHub Actions) | Cloudflare account | GitHub secret |

### At handover, rotate every server secret
When the asset changes hands, regenerate: the Supabase service-role key, `GEMINI_API_KEY`, `RESEND_API_KEY`, all three VAPID values, `PUSH_INTERNAL_TOKEN`, and the Cloudflare token. The public config values change only if the buyer moves to a new Supabase project or domain.
