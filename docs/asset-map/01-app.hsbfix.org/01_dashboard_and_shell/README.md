# 01 dashboard and shell

_Module dashboard, navigation shell, auth session, org/plant context._

## 1. App section / UI
| File | Role |
|---|---|
| `index.html` | App shell + module tiles |
| `app.js` | Core: auth, routing, org/plant context, most modules |
| `config.js` | Supabase URL, anon key, bucket |
| `service-worker.js` | Offline cache / PWA |
| `offline.js` | Offline queue |

## 2. Schema / SQL
Full DDL for this section is in **`schema.sql`** (extracted from the sources below).

**Tables:** `organizations`, `organization_members`, `plants`, `profiles`, `organization_settings`, `subscription_plans`, `notifications`

**RPCs / functions:** `create_organization()`, `accept_invitation()`, `is_platform_admin()`, `organization_effective_features()`, `organization_plan_summary()`, `pending_legal_documents()`, `accept_legal_document()`

**Defined in:** 0001_foundation.sql, 0004_knowledge_files.sql, 0005_platform_commercial.sql, 0006_rpc.sql, R1-fix-organization-creation.sql, R4-company-features.sql

## 3. Edge function
_None._

## 4. Keys / secrets
| Key | Where it lives | What it is |
|---|---|---|
| `SUPABASE_URL` | config.js (public) | Supabase project URL (public). Same for all three properties. |
| `SUPABASE_ANON_KEY` | config.js (public) | Supabase publishable/anon key (public, RLS-guarded). In config.js. |
| `FILE_BUCKET` | config.js (public) | Supabase Storage bucket name ('plant-files'). In config.js. |

