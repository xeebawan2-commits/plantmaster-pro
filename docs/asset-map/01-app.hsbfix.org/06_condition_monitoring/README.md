# 06 condition monitoring

_Phone microphone + accelerometer capture machine sound/vibration for screening & trending._

## 1. App section / UI
| File | Role |
|---|---|
| `condition.js` | Sound/vibration tester, capture, trend |
| `condition-v4.9.css` | Styling |

## 2. Schema / SQL
Full DDL for this section is in **`schema.sql`** (extracted from the sources below).

**Tables:** `condition_recordings`, `assets`, `file_metadata`, `manuals`, `document_chunks`

**RPCs / functions:** `reserve_storage_upload()`, `finalize_storage_upload()`, `cancel_storage_reservation()`, `record_storage_download()`

**Defined in:** 0002_operations.sql, 0004_knowledge_files.sql, 0006_rpc.sql

## 3. Edge function
See **`edge-function.md`**. Functions: `condition-analyzer`

## 4. Keys / secrets
| Key | Where it lives | What it is |
|---|---|---|
| `SUPABASE_URL` | config.js (public) | Supabase project URL (public). Same for all three properties. |
| `SUPABASE_ANON_KEY` | config.js (public) | Supabase publishable/anon key (public, RLS-guarded). In config.js. |
| `FILE_BUCKET` | config.js (public) | Supabase Storage bucket name ('plant-files'). In config.js. |
| `SUPABASE_SERVICE_ROLE_KEY` | Edge Function secret (server-only) | Supabase service-role secret. SERVER-ONLY, set in Edge Function secrets. Never in the browser. |
| `GEMINI_API_KEY` | Edge Function secret (server-only) | Google Gemini API key. Edge Function secret. |

