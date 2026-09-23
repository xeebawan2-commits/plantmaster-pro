# 15 push notifications

_Web-push alerts for work orders and alarms when the app is closed._

## 1. App section / UI
| File | Role |
|---|---|
| `push-client.js` | Subscribe / VAPID public key (line 11) |
| `service-worker.js` | Receives + shows push |

## 2. Schema / SQL
Full DDL for this section is in **`schema.sql`** (extracted from the sources below).

**Tables:** `notifications`

**Defined in:** 0004_knowledge_files.sql

## 3. Edge function
See **`edge-function.md`**. Functions: `web-push`

## 4. Keys / secrets
| Key | Where it lives | What it is |
|---|---|---|
| `SUPABASE_URL` | config.js (public) | Supabase project URL (public). Same for all three properties. |
| `SUPABASE_ANON_KEY` | config.js (public) | Supabase publishable/anon key (public, RLS-guarded). In config.js. |
| `SUPABASE_SERVICE_ROLE_KEY` | Edge Function secret (server-only) | Supabase service-role secret. SERVER-ONLY, set in Edge Function secrets. Never in the browser. |
| `VAPID_PUBLIC_KEY` | Edge Function secret (server-only) | Web-push VAPID public key. Also hard-coded in push-client.js line 11. |
| `VAPID_PRIVATE_KEY` | Edge Function secret (server-only) | Web-push VAPID private key. Edge Function secret. |
| `VAPID_SUBJECT` | Edge Function secret (server-only) | Web-push VAPID subject (mailto:). Edge Function secret. |
| `PUSH_INTERNAL_TOKEN` | Edge Function secret (server-only) | Shared secret protecting the web-push function. Edge Function secret. |

