# 02 companies

_List/manage companies: status, plan, complimentary access, delete._

## 1. App section / UI
| File | Role |
|---|---|
| `app.js` | Companies list, status/plan editor, delete |

## 2. Schema / SQL
Full DDL for this section is in **`schema.sql`** (extracted from the sources below).

**Tables:** `company_feature_grants`, `company_feature_blocks`, `quota_overrides`, `subscription_plans`

**RPCs / functions:** `control_companies()`, `platform_set_company()`, `control_set_complimentary()`, `control_delete_company()`

**Defined in:** 0005_platform_commercial.sql, 0006_rpc.sql, 02-function-source.sql (LIVE snapshot), 05-tables-constraints-indexes.sql (LIVE snapshot), R2-control-center.sql, R4-company-features.sql

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

