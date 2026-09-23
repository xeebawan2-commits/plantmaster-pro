# 03 asset register

_Equipment recorded with code, type, department and running state._

## 1. App section / UI
| File | Role |
|---|---|
| `app.js` | Asset list, add/edit, status |

## 2. Schema / SQL
Full DDL for this section is in **`schema.sql`** (extracted from the sources below).

**Tables:** `assets`, `code_registry`

**Defined in:** 0002_operations.sql, 0003_inventory_procurement.sql

## 3. Edge function
_None._

## 4. Keys / secrets
| Key | Where it lives | What it is |
|---|---|---|
| `SUPABASE_URL` | config.js (public) | Supabase project URL (public). Same for all three properties. |
| `SUPABASE_ANON_KEY` | config.js (public) | Supabase publishable/anon key (public, RLS-guarded). In config.js. |
| `FILE_BUCKET` | config.js (public) | Supabase Storage bucket name ('plant-files'). In config.js. |

