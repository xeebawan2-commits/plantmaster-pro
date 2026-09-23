# 09 activity and backups

_Audit/action log and Supabase backup shortcuts; report exports._

## 1. App section / UI
| File | Role |
|---|---|
| `app.js` | Activity log; backup CSV/Excel/Word/PDF; Supabase backups link |

## 2. Schema / SQL
Full DDL for this section is in **`schema.sql`** (extracted from the sources below).

**Tables:** `admin_action_logs`

**Defined in:** 05-tables-constraints-indexes.sql (LIVE snapshot)

## 3. Edge function
_None._

## 4. Keys / secrets
| Key | Where it lives | What it is |
|---|---|---|
| `SUPABASE_URL` | config.js (public) | Supabase project URL (public). Same for all three properties. |
| `SUPABASE_ANON_KEY` | config.js (public) | Supabase publishable/anon key (public, RLS-guarded). In config.js. |
| `CUSTOMER_APP_URL` | config.js (public) | URL of the customer PWA (https://app.hsbfix.org). In admin/config.js. |
| `FILE_BUCKET` | config.js (public) | Supabase Storage bucket name ('plant-files'). In config.js. |
| `WHATSAPP_NUMBER` | config.js (public) | Support WhatsApp number. In admin/config.js. |

