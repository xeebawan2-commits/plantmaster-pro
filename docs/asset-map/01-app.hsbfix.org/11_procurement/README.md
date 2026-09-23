# 11 procurement

_Material requests, purchase orders and supplier records._

## 1. App section / UI
| File | Role |
|---|---|
| `procurement.js` | Material requests, POs, receiving |

## 2. Schema / SQL
Full DDL for this section is in **`schema.sql`** (extracted from the sources below).

**Tables:** `material_requests`, `purchase_orders`, `purchase_order_lines`, `suppliers`, `spares`

**RPCs / functions:** `next_po_number()`, `receive_po_line()`

**Defined in:** 0003_inventory_procurement.sql

## 3. Edge function
_None._

## 4. Keys / secrets
| Key | Where it lives | What it is |
|---|---|---|
| `SUPABASE_URL` | config.js (public) | Supabase project URL (public). Same for all three properties. |
| `SUPABASE_ANON_KEY` | config.js (public) | Supabase publishable/anon key (public, RLS-guarded). In config.js. |
| `FILE_BUCKET` | config.js (public) | Supabase Storage bucket name ('plant-files'). In config.js. |

