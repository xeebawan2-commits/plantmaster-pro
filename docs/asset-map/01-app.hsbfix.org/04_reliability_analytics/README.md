# 04 reliability analytics

_MTTR, MTBF, total downtime, work-order and asset-state breakdowns._

## 1. App section / UI
| File | Role |
|---|---|
| `analytics.js` | KPI calculations and charts |

## 2. Schema / SQL
Full DDL for this section is in **`schema.sql`** (extracted from the sources below).

**Tables:** `work_orders`, `assets`

**Defined in:** 0002_operations.sql

## 3. Edge function
_None._

## 4. Keys / secrets
| Key | Where it lives | What it is |
|---|---|---|
| `SUPABASE_URL` | config.js (public) | Supabase project URL (public). Same for all three properties. |
| `SUPABASE_ANON_KEY` | config.js (public) | Supabase publishable/anon key (public, RLS-guarded). In config.js. |
| `FILE_BUCKET` | config.js (public) | Supabase Storage bucket name ('plant-files'). In config.js. |

