# 06 plans and packages

_Create/edit subscription packages, prices, limits, modules; activate/deactivate._

## 1. App section / UI
| File | Role |
|---|---|
| `app.js` | Plan editor, savePlanFrom(), togglePlan() [fixed v1.9.1] |

## 2. Schema / SQL
Full DDL for this section is in **`schema.sql`** (extracted from the sources below).

**Tables:** `subscription_plans`

**RPCs / functions:** `control_save_plan()`

**Defined in:** 0005_platform_commercial.sql, 02-function-source.sql (LIVE snapshot)

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

