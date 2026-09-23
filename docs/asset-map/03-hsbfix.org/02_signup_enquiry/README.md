# 02 signup enquiry

_Prospect submits an enquiry; owner is emailed; row lands in signup_requests._

## 1. App section / UI
| File | Role |
|---|---|
| `signup.html` | Enquiry form -> REST insert into signup_requests + signup-notify |

## 2. Schema / SQL
Full DDL for this section is in **`schema.sql`** (extracted from the sources below).

**Tables:** `signup_requests`

**Defined in:** R2-control-center.sql

## 3. Edge function
See **`edge-function.md`**. Functions: `signup-notify`

## 4. Keys / secrets
| Key | Where it lives | What it is |
|---|---|---|
| `SUPABASE_URL` | config.js (public) | Supabase project URL (public). Same for all three properties. |
| `SUPABASE_ANON_KEY` | config.js (public) | Supabase publishable/anon key (public, RLS-guarded). In config.js. |

