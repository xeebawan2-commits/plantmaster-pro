# 09 operations daily logs

_Daily logs, attendance, shift handovers, checklists, PM plans._

## 1. App section / UI
| File | Role |
|---|---|
| `operations.js` | Daily logs, attendance, checklists, PM |
| `designation-options.js` | Role/designation lists |
| `smart-select.js` | Searchable selects |

## 2. Schema / SQL
Full DDL for this section is in **`schema.sql`** (extracted from the sources below).

**Tables:** `daily_logs`, `attendance`, `shift_assignments`, `shift_handovers`, `checklist_templates`, `checklist_items`, `checklist_runs`, `checklist_values`, `maintenance_plans`, `maintenance_completions`

**Defined in:** 0002_operations.sql

## 3. Edge function
_None._

## 4. Keys / secrets
| Key | Where it lives | What it is |
|---|---|---|
| `SUPABASE_URL` | config.js (public) | Supabase project URL (public). Same for all three properties. |
| `SUPABASE_ANON_KEY` | config.js (public) | Supabase publishable/anon key (public, RLS-guarded). In config.js. |
| `FILE_BUCKET` | config.js (public) | Supabase Storage bucket name ('plant-files'). In config.js. |

