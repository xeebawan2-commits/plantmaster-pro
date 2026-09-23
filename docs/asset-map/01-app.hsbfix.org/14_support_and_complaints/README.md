# 14 support and complaints

_In-app support threads and complaints to the platform owner._

## 1. App section / UI
| File | Role |
|---|---|
| `app.js` | Support / complaints UI |

## 2. Schema / SQL
Full DDL for this section is in **`schema.sql`** (extracted from the sources below).

**Tables:** `support_threads`, `support_messages`, `system_incidents`

**RPCs / functions:** `submit_app_complaint()`, `reply_app_complaint()`, `owner_app_complaints()`, `owner_app_complaint_messages()`

**Defined in:** 0005_platform_commercial.sql, 0006_rpc.sql

## 3. Edge function
_None._

## 4. Keys / secrets
| Key | Where it lives | What it is |
|---|---|---|
| `SUPABASE_URL` | config.js (public) | Supabase project URL (public). Same for all three properties. |
| `SUPABASE_ANON_KEY` | config.js (public) | Supabase publishable/anon key (public, RLS-guarded). In config.js. |
| `FILE_BUCKET` | config.js (public) | Supabase Storage bucket name ('plant-files'). In config.js. |

