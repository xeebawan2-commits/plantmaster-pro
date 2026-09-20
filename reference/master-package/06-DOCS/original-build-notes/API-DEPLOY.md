# Public REST API — deploy guide

Closes the **integrations gap (2/10)**. Read-only v1, API-key authenticated.

---

## Step 1 — Run the SQL

Supabase → SQL Editor → new query → paste **`02-schema-api-keys.sql`** → Run.

Creates `api_keys` plus `pm_create_api_key()` and `pm_revoke_api_key()`.
Prefixed `pm_` so it cannot collide with your existing `is_org_member`.

---

## Step 2 — Deploy the function

The Edge Function needs the Supabase CLI. On your laptop, not the phone:

```bash
npm install -g supabase
supabase login
supabase link --project-ref dpmmenwziplixrgylapy

mkdir -p supabase/functions/public-api
cp index.ts supabase/functions/public-api/index.ts

supabase functions deploy public-api --no-verify-jwt
```

`--no-verify-jwt` is **required** — clients authenticate with `X-API-Key`, not a
Supabase JWT. Without the flag every request returns 401.

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically.

---

## Step 3 — Create a key

SQL Editor:

```sql
select * from public.pm_create_api_key(
  '<your-organization-uuid>',
  'ERP integration'
);
```

Returns something like:

```
id                                   | api_key                                      | key_prefix
-------------------------------------+----------------------------------------------+------------------
9f3c…                                | pm_live_7a2f9c1e…                            | pm_live_7a2f9c1e
```

**Copy `api_key` now.** Only its SHA-256 hash is stored — it cannot be shown again.

To get your org UUID: `select id, name from public.organizations;`

Optional — restrict a key to one plant, or expire it:

```sql
select * from public.pm_create_api_key(
  '<org-uuid>', 'Vendor read-only', '<plant-uuid>', now() + interval '90 days'
);
```

---

## Step 4 — Test

```bash
curl -H "X-API-Key: pm_live_7a2f9c1e…" \
  "https://dpmmenwziplixrgylapy.supabase.co/functions/v1/public-api/v1/meta"
```

Expected: org name, plants, asset/work-order counts.

---

## Endpoints

Base: `https://dpmmenwziplixrgylapy.supabase.co/functions/v1/public-api/v1/`

| Endpoint | Filters |
|---|---|
| `meta` | — |
| `assets` | `status`, `running_state` |
| `work-orders` | `status`, `priority`, `asset_id` |
| `spares` | `low_stock=true` |
| `tools` | — |
| `maintenance-plans` | `status`, `overdue=true` |
| `purchase-orders` | `status` (includes line items) |
| `suppliers` | — |

All accept `limit` (default 50, max 200) and `offset`.

```bash
# What needs reordering
curl -H "X-API-Key: $KEY" ".../v1/spares?low_stock=true"

# Overdue PMs
curl -H "X-API-Key: $KEY" ".../v1/maintenance-plans?overdue=true"

# Open work orders, page 2
curl -H "X-API-Key: $KEY" ".../v1/work-orders?status=open&limit=50&offset=50"
```

Response shape:

```json
{ "data": [ … ], "limit": 50, "offset": 0, "count": 12 }
```

Errors return `{ "error": "...", "code": "...", "hint": "..." }` with the
PostgREST detail included — that detail is the difference between a two-minute
fix and an afternoon of guessing.

---

## Security

- Keys are **SHA-256 hashed**; plaintext is never stored
- **Owner-only** creation and revocation — managers deliberately excluded, since a key grants tenant-wide read
- Optional per-plant scoping and expiry
- `revoked_at` / `expires_at` are checked on every request
- **GET only.** No write path exists in v1, so a leaked key cannot alter data
- The function uses the service-role key and therefore **bypasses RLS** — isolation is enforced in code by scoping every query to the key's org/plant. If you add an endpoint, it must go through `scope()`

Revoke: `select public.pm_revoke_api_key('<key-uuid>');`

---

## Verified against your real schema

Every column was cross-checked against `app.js` and `operations.js` before writing, not assumed. This matters — the earlier draft of this file referenced `assets.make`, `assets.model`, `assets.serial_number`, `assets.criticality`, `spares.code` and `spares.minimum`, **none of which exist in your database**. All corrected.

Two scoping bugs were also caught and fixed during review:
- `suppliers.plant_id` is nullable, so plant-scoped keys would have hidden org-level suppliers → suppliers are now scoped by organization
- `meta` listed every plant regardless of key scope → now respects plant-scoped keys

Two things I could not verify without database access: whether your `tools` table carries `organization_id` (only `plant_id` usage appears in the client), and the exact `work_orders` soft-delete behaviour on older rows. If `/v1/tools` returns a column error, tell me and it's a one-line fix.

---

## Not built yet

- **Write endpoints** (POST work orders, PATCH status) — deliberate. Read-only is the safe first release
- **Webhooks** (fix-list #17) — outbound push on work-order status change
- **Rate limiting** — `last_used_at` is stamped, but nothing throttles yet
- **Key management UI** — keys are created via SQL today. A Settings screen is roughly 2 hours if you want it
