# 16 billing and entitlements

_Subscription, plan limits and per-company feature entitlements the app enforces._

## 1. App section / UI
| File | Role |
|---|---|
| `app.js` | Reads effective features to gate modules |

## 2. Schema / SQL
Full DDL for this section is in **`schema.sql`** (extracted from the sources below).

**Tables:** `organization_subscriptions`, `subscription_plans`, `company_feature_grants`, `company_feature_blocks`, `quota_overrides`

**RPCs / functions:** `organization_effective_features()`, `organization_plan_summary()`

**Defined in:** 0005_platform_commercial.sql, 0006_rpc.sql, 05-tables-constraints-indexes.sql (LIVE snapshot), R4-company-features.sql

## 3. Edge function
_None._

## 4. Keys / secrets
| Key | Where it lives | What it is |
|---|---|---|
| `SUPABASE_URL` | config.js (public) | Supabase project URL (public). Same for all three properties. |
| `SUPABASE_ANON_KEY` | config.js (public) | Supabase publishable/anon key (public, RLS-guarded). In config.js. |
| `FILE_BUCKET` | config.js (public) | Supabase Storage bucket name ('plant-files'). In config.js. |

