# 02 work orders

_Create and track jobs against a specific asset with priority and status._

## 1. App section / UI
| File | Role |
|---|---|
| `app.js` | Work-order list, create, start/complete, safety |
| `analytics.js` | Feeds MTTR/MTBF from completed work orders |

## 2. Schema / SQL
Full DDL for this section is in **`schema.sql`** (extracted from the sources below).

**Tables:** `work_orders`, `assets`, `audit_logs`

**Defined in:** 0002_operations.sql, 0004_knowledge_files.sql

## 3. Edge function
_None._

## 4. Keys / secrets
| Key | Where it lives | What it is |
|---|---|---|
| `SUPABASE_URL` | config.js (public) | Supabase project URL (public). Same for all three properties. |
| `SUPABASE_ANON_KEY` | config.js (public) | Supabase publishable/anon key (public, RLS-guarded). In config.js. |
| `FILE_BUCKET` | config.js (public) | Supabase Storage bucket name ('plant-files'). In config.js. |

