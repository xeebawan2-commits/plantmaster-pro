# Database & API audit

> # ⚠️ Read `STOP-READ-FIRST.md` first
>
> **Your database needs three scripts run by hand before anything works.**
> `create_organization` is broken on the live database — it inserts a plant
> before creating the subscription that the plant's own trigger requires, so
> every signup fails with *"Active subscription required"*. And six of the
> RPCs your Control Center calls do not exist.
>
> Fix: run `supabase/repairs/R1`, `R2`, then `R3` in the Supabase SQL Editor.
>
> All three deploy commands (`deploy`, `deploy:site`, `deploy:admin`) are
> safe. `db:push` and `functions:deploy` remain blocked and should stay that
> way — use the R-scripts instead.

This was the priority of the renewal. The live schema had no migration
history in the repository at all — it existed only inside the hosted Supabase
project, which meant nobody could review the policies, reproduce the database,
or tell whether a given table was protected.

The schema is now reconstructed as **9 versioned, idempotent migrations**
(~3,600 lines) covering **55 tables**, **68 RLS policies** and **53
functions**, and it is verified by **66 automated assertions** that run against
a real Postgres on every `npm run verify`.

> Because the live database was unreachable from the build environment, the
> schema was reconstructed from the application's own queries and every
> statement was written to be idempotent (`if not exists`, `create or replace`,
> guarded `do $$` blocks). Applying it to the existing project converges it
> rather than recreating it. Take a backup first regardless.

---

## Running the checks

```bash
npm run verify:db
```

This boots a real PostgreSQL (PGlite / PG 18 WASM), applies all 9 migrations
in order, then runs the assertions in `tools/db-verify/tests.mjs` as six
different impersonated users across two tenants.

Impersonation is real, not simulated: the harness sets the JWT claim and
switches to the `authenticated` role, so policies are evaluated exactly as
PostgREST would evaluate them.

---

## The tenancy model

Every business table carries `organization_id`, and most also carry
`plant_id`. Both are enforced:

- **`organization_id`** is the tenant boundary. Every policy filters on it via
  `is_org_member()`.
- **`plant_id`** is checked by the `enforce_plant_org()` trigger, which
  rejects a row whose plant belongs to a *different* organization. Without
  this, a caller who legitimately belongs to org A could attach a record to a
  plant in org B and the RLS check on `organization_id` alone would pass.

The auth helpers (`is_org_member`, `org_role`, `has_org_role`, `can_write`)
are `SECURITY DEFINER`. That is deliberate: a policy on
`organization_members` that queries `organization_members` recurses
infinitely. Routing through a definer function breaks the cycle.

### Role gradient

`pm_standard_policies(table, min_write)` applies a consistent policy set using
ranked roles, so a table's access rules are one line rather than four
hand-written policies that can silently drift apart:

| Role | Rank |
|---|---|
| owner | 60 |
| manager | 50 |
| supervisor | 40 |
| engineer | 30 |
| technician | 20 |
| operator | 10 |
| viewer | 0 |

`viewer` is the read-only demo role; `can_write()` returns false for it
everywhere.

---

## What the tests actually assert

A representative selection of the 66:

**Isolation** — a second tenant cannot read, update or delete the first
tenant's assets, work orders, manuals, chunks, complaints, profiles, storage
paths or report history.

**Immutability** — audit logs, the stock ledger and complaint messages are
append-only, defended *twice*: no `UPDATE`/`DELETE` policy **and** a revoked
grant. The test accepts either `permission denied` or zero rows affected.

**Business rules that money depends on**

- `next_po_number` is advisory-locked and produces `PO-YYYY-0001` per tenant
  per year, with no gaps or collisions under concurrency.
- Stock moves only through `transact_spare` / `transact_tool` /
  `receive_po_line`, each taking `FOR UPDATE` and guarded by a
  `stock >= 0` CHECK. Direct writes to the ledger are refused.
- A PO line cannot be over-received.
- PO totals are recalculated by trigger, not by the client.
- A permit cannot be approved by the person who requested it.
- Storage follows reserve → finalize/cancel, reservations expire after an
  hour, and exceeding the plan quota raises SQLSTATE `53100`.
- A suspended workspace cannot upload at all.

**Platform separation** — a tenant owner cannot change their own commercial
status or plan; only a `platform_admins` row can. `platform_tenant_overview`
returns every tenant for staff and nothing for a customer.

**Recovery** — soft delete via `removed_at`; `restore_record` accepts only
whitelisted table names (the test tries an arbitrary one and is rejected), and
a technician cannot restore.

### Two real bugs this caught

1. `pm_attach_tenant_guards()` attached `enforce_plant_org()` to
   `data_retention_policies`, which has no `plant_id` column. Every call to
   `create_organization()` failed. Fixed in `0002`.
2. `manuals.status` had no CHECK constraint, so the ingest function's
   vocabulary (`stored`/`indexing`/`indexed`/`failed`/`deleted`) was a
   convention rather than a guarantee. Constrained in `0009`.

---

## A note on how RLS denies writes

Postgres does not raise an error when a policy excludes a row from an
`UPDATE` or `DELETE` — it simply matches zero rows. A test that only asserts
"no exception was thrown" therefore passes even when the data leaked.

Cross-tenant write tests here assert **zero rows affected *and* the target
row's values are unchanged**, read back as the owning tenant.

---

## API surface

The client never issues raw writes for anything consequential. Sensitive
operations are `SECURITY DEFINER` RPCs that validate first:

| RPC | Guards |
|---|---|
| `create_organization` | One workspace per user (unique violation 23505) |
| `accept_invitation` | Single-use, expiry-checked, email must match |
| `transact_spare` / `transact_tool` | Row lock, non-negative stock |
| `receive_po_line` | Cannot exceed ordered quantity |
| `reserve_storage_upload` | Plan quota, tenant status, writable role |
| `restore_record` | Table-name whitelist, role ≥ supervisor |
| `platform_set_company` | `is_platform_admin()` only |
| `submit_app_complaint` | Owner only |
| `transfer_organization_ownership` | Current owner only |

Tables the client must never write directly have their grants revoked in
`0008`, so PostgREST does not even expose a writable route: `audit_logs`,
`inventory_transactions`, `tool_transactions`, `ai_usage_events`,
`daily_report_runs`, `storage_usage_events`.

### Edge functions

All eight verify membership **server-side** against the database. The
`organization_id` in a request body is treated as a claim to be checked, never
as authorization. See `supabase/functions/_shared/guard.ts`.

The previous `index.ts` at the repo root — unmapped to any function — had
`Access-Control-Allow-Origin: *` and no authentication whatsoever. Anyone who
found the URL could spend the project's Gemini quota. It is now
`smart-responder`, behind the shared guard.

---

## Indexes added for the hot paths

`0009` indexes the queries the edge functions run on every request, which
would otherwise be sequential scans that get slower as tenants grow:

- `ai_usage_events(organization_id, created_at desc)` — the monthly quota
  count, executed on *every* AI call.
- `document_chunks` GIN trigram on `content` — manual retrieval.
- `notifications(created_at) where pushed_at is null and user_id is not null`
  — exactly the push poller's predicate.
- `condition_recordings` partial indexes for baseline and recent-history
  lookup.

---

## Things you must still do

1. **Rotate the push token.** A `PUSH_INTERNAL_TOKEN` was committed in plain
   text in this public repository and remains in git history at `6c367eb`.
   Removing it from the working tree does not remove it from history. Generate
   a new one, set it as both a function secret and a GitHub Actions secret.
2. **Seed `platform_admins`** before using `admin.hsbfix.org`, or it will
   refuse you too (see `docs/DEPLOYMENT.md`).
3. **Take a backup before the first `db push`**, since the migrations are
   converging an existing database rather than building an empty one.
4. **Keep plan limits in sync.** The `subscription_plans` rows seeded by the
   migrations must match the pricing published on `site/index.html`.
