# 07 storage files

_View/download/delete customer-uploaded files across companies._

## 1. App section / UI
| File | Role |
|---|---|
| `app.js` | Files browser; storage_signed_url / storage_delete via platform-admin-api |

## 2. Schema / SQL
Full DDL for this section is in **`schema.sql`** (extracted from the sources below).

**RPCs / functions:** `control_storage()`

**Defined in:** 02-function-source.sql (LIVE snapshot)

## 3. Edge function
See **`edge-function.md`**. Functions: `platform-admin-api`

## 4. Keys / secrets
| Key | Where it lives | What it is |
|---|---|---|
| `SUPABASE_URL` | config.js (public) | Supabase project URL (public). Same for all three properties. |
| `SUPABASE_ANON_KEY` | config.js (public) | Supabase publishable/anon key (public, RLS-guarded). In config.js. |
| `CUSTOMER_APP_URL` | config.js (public) | URL of the customer PWA (https://app.hsbfix.org). In admin/config.js. |
| `FILE_BUCKET` | config.js (public) | Supabase Storage bucket name ('plant-files'). In config.js. |
| `WHATSAPP_NUMBER` | config.js (public) | Support WhatsApp number. In admin/config.js. |
| `SUPABASE_SERVICE_ROLE_KEY` | Edge Function secret (server-only) | Supabase service-role secret. SERVER-ONLY, set in Edge Function secrets. Never in the browser. |

