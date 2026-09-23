# 10 inventory and spares

_Spares and tools with append-only stock ledgers._

## 1. App section / UI
| File | Role |
|---|---|
| `operations.js` | Spares / tools issue & receive |

## 2. Schema / SQL
Full DDL for this section is in **`schema.sql`** (extracted from the sources below).

**Tables:** `spares`, `tools`, `inventory_transactions`, `tool_transactions`

**RPCs / functions:** `transact_spare()`, `transact_tool()`

**Defined in:** 0003_inventory_procurement.sql

## 3. Edge function
_None._

## 4. Keys / secrets
| Key | Where it lives | What it is |
|---|---|---|
| `SUPABASE_URL` | config.js (public) | Supabase project URL (public). Same for all three properties. |
| `SUPABASE_ANON_KEY` | config.js (public) | Supabase publishable/anon key (public, RLS-guarded). In config.js. |
| `FILE_BUCKET` | config.js (public) | Supabase Storage bucket name ('plant-files'). In config.js. |

