# 05 ai problem solver

_Plain-language fault search across manuals, experience and verified cases; confidence + sources._

## 1. App section / UI
| File | Role |
|---|---|
| `solver.js` | Problem solver UI, deep search, save case |
| `voice-input.js` | Voice capture -> voice-translate |
| `app.js` | Case history |

## 2. Schema / SQL
Full DDL for this section is in **`schema.sql`** (extracted from the sources below).

**Tables:** `problem_cases`, `manuals`, `document_chunks`, `technical_experiences`

**Defined in:** 0004_knowledge_files.sql

## 3. Edge function
See **`edge-function.md`**. Functions: `smart-responder`, `voice-translate`

## 4. Keys / secrets
| Key | Where it lives | What it is |
|---|---|---|
| `SUPABASE_URL` | config.js (public) | Supabase project URL (public). Same for all three properties. |
| `SUPABASE_ANON_KEY` | config.js (public) | Supabase publishable/anon key (public, RLS-guarded). In config.js. |
| `FILE_BUCKET` | config.js (public) | Supabase Storage bucket name ('plant-files'). In config.js. |
| `GEMINI_API_KEY` | Edge Function secret (server-only) | Google Gemini API key. Edge Function secret. |
| `SUPABASE_SERVICE_ROLE_KEY` | Edge Function secret (server-only) | Supabase service-role secret. SERVER-ONLY, set in Edge Function secrets. Never in the browser. |

