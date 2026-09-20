# Database backup — 13 September 2026

Captured from the live Supabase project `dpmmenwziplixrgylapy`.

## The important files — runnable SQL

These three can rebuild the database from nothing.

| File | Contents |
|---|---|
| `05-tables-constraints-indexes.sql` | **83 tables**, 381 constraints, 37 indexes, 61 triggers |
| `02-function-source.sql` | **73 database functions** |
| `06-rls-policies.sql` | **135 row-level-security policies** across 79 tables |

### Run order

1. `05-tables-constraints-indexes.sql` — stop before the TRIGGERS section
2. `02-function-source.sql`
3. `06-rls-policies.sql`
4. the TRIGGERS section at the bottom of file 05

Triggers come last because they reference functions that must already exist.

## The raw exports

The CSVs the SQL above was built from. Kept so nothing is lost in
translation, and so you can check anything by hand.

| File | Rows |
|---|---|
| `01-table-columns.csv` | 1,000 column definitions |
| `02-function-source.csv` | 187 functions (73 yours, 114 from extensions) |
| `03-rls-policies.csv` | 135 policies |
| `04-triggers-indexes-constraints.csv` | 581 rows: 381 constraints, 140 indexes, 61 triggers |

## Two notes on the reconstruction

**Indexes: 37 in the SQL, 140 in the CSV.** That is correct, not a loss.
Of the 140, **83 are primary-key indexes** and **21 back UNIQUE
constraints** — Postgres creates all 104 automatically when the constraint
is created. Only the 37 standalone indexes need explicit statements. Each
one was checked against the constraint list before being skipped.

**Four columns could not be typed exactly.** The catalog export reports
`ARRAY` and `USER-DEFINED` without the element type, so they are marked
`-- CHECK TYPE` in file 05:

- `api_keys.scopes` → `text[]`
- `organization_settings.report_recipients` → `text[]`
- `profiles.skills` → `text[]`
- `document_chunks.embedding` → set to `vector(768)`

The three `text[]` columns are certain — their defaults (`'{read}'::text[]`)
prove it. **`document_chunks.embedding` is the one to verify**: it is a
pgvector column and the dimension must match whatever your Gemini embedding
model produces. If AI manual search misbehaves after a rebuild, check this
first.

## What is still NOT here

**Your data.** This is structure only — no assets, work orders, purchase
orders or suppliers. Use Table Editor → Export → CSV per table.

**Edge function secrets.** `GEMINI_API_KEY`, `HEALTH_MONITOR_TOKEN`, the
VAPID keys, the Resend key. They live in Supabase Secrets and cannot be
read back out. Write them down separately — the functions will not work
without them.

**Auth users.** Accounts in `auth.users` are managed by Supabase and are
not part of the public schema.

**Storage files.** The contents of the `plant-files` bucket.

## Honest limitation

This is a faithful **reconstruction**, not a native dump. It was rebuilt
from catalog exports and verified table by table, but a real
`supabase db dump` — which needs a computer — remains the gold standard.
Run one when you next have access to a laptop.
