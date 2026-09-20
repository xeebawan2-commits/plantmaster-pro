# Database, API routes and edge functions — the real plan

Written after reading the live schema snapshot you sent
(`reference/master-package/05-DATABASE/03-live-schema-snapshot/`, captured
13 September 2026 from project `dpmmenwziplixrgylapy`).

This replaces guesswork with measurement. Every claim below is checked
against that snapshot, and against the 17 dashboard screenshots you sent
earlier. Where the two disagree I say so.

---

## 1. Why "create organization" fails — proven, not guessed

This is the bug you just confirmed. Here is the exact mechanism.

The live `create_organization(org_name, plant_name)` does four inserts:

```sql
insert into organizations(...)        -- ok
insert into organization_members(...) -- ok
insert into plants(organization_id,name) values(o,plant_name)  -- FAILS HERE
insert into plant_members(...)        -- never reached
```

There is a trigger on `plants` called `enforce_plant_plan_limit`:

```sql
select p.max_plants into base_limit
  from organization_subscriptions s
  join subscription_plans p on p.id = s.plan_id
 where s.organization_id = new.organization_id
   and s.status in ('active','trial');

if base_limit is null then
  raise exception 'Active subscription required';
end if;
```

`create_organization` **never inserts a row into `organization_subscriptions`.**
So `base_limit` is always null, the trigger always raises, the whole
function rolls back, and no organization is ever created.

It is a deadlock in the logic: you cannot create a plant without a
subscription, and nothing creates the subscription.

**The fix already exists in your own files** — `05-DATABASE/01-schema-build-order/30--01-GATEKEEPER.sql`
rewrites `create_organization` to insert the subscription *before* the
plant, with the comment:

> Subscription FIRST: enforce_plant_plan_limit refuses to create a plant
> when no active subscription exists.

**That script was written but never run.** Proof: it creates
`owner_invitations` and `signup_requests`, and neither table exists in the
13 Sep live snapshot.

---

## 2. What else never got run

The admin control centre calls 15 RPCs. Six of them do not exist live:

| RPC the admin panel calls | Defined in | Live? |
|---|---|---|
| `control_invite_owner` | `30--01-GATEKEEPER.sql` | **missing** |
| `control_revoke_owner_invitation` | `30--01-GATEKEEPER.sql` | **missing** |
| `control_delete_company` | `32--03-DELETE-AND-FIXES.sql` | **missing** |
| `control_delete_owner_invitation` | `32--03-DELETE-AND-FIXES.sql` | **missing** |
| `control_delete_signup_request` | `32--03-DELETE-AND-FIXES.sql` | **missing** |
| `control_purge_signup_requests` | `32--03-DELETE-AND-FIXES.sql` | **missing** |

The other nine exist and work.

So the Control Center's **Invite Owner**, **Approve**, **Delete company**
and **signup queue** buttons are all calling functions that are not there.
That is the same root cause as the create-organization failure: the last
three SQL scripts in the build order were never applied.

This is why "everything has to be managed from admin" does not work today.

---

## 3. The mismatch between my migrations and your database

My `supabase/migrations/0001`–`0009` were reconstructed before I had the
snapshot. Measured against it:

- live: **83 tables**, 73 functions, 135 policies
- my migrations: **56 tables**
- overlap: **51**
- my migrations would **create 5 duplicates** under different names
- **32 live tables** my migrations never model

The five duplicates, confirmed by both the snapshot and your screenshots:

| My migration creates | Live already has |
|---|---|
| `ai_usage_events` | `ai_usage` |
| `app_complaints` | `platform_support_tickets` |
| `app_complaint_messages` | `platform_support_messages` |
| `organization_features` | `organization_entitlements` |
| `daily_report_runs` | `report_dispatches` |

Running them would split your data across two sets of tables.

**Decision: I am not going to push my reconstructed migrations at your
database.** They stay in the repo as a reference model. The live schema is
the source of truth, and it is richer than my reconstruction.

Instead I will write a small number of **targeted, idempotent repair
migrations** that do only what is actually missing, against the real table
and column names.

---

## 4. What I will actually change

### 4.1 Database — three repair scripts, nothing more

**R1 — fix organization creation.** Rewrite `create_organization` so the
subscription is inserted before the plant. This alone unblocks signup.

**R2 — add the gatekeeper tables and the six missing control RPCs**, so
the Control Center's buttons work: `owner_invitations`, `signup_requests`,
`control_invite_owner`, `control_revoke_owner_invitation`,
`control_delete_company`, `control_delete_owner_invitation`,
`control_delete_signup_request`, `control_purge_signup_requests`.

**R3 — verification queries** you can paste into the SQL Editor to confirm
each object now exists.

All three written against real column names taken from the snapshot, all
idempotent, all safe to re-run. They **add**; they do not drop or rename
anything that exists.

### 4.2 Edge functions — do not mass-deploy

Live has 14 functions. My repo has 8. Seven overlap, and deploying would
overwrite live code I have never seen, including `create-owner`, whose
source your own notes say was lost:

> Recover the create-owner edge function source:
> `npx supabase functions download create-owner`

I will not overwrite those. `functions:deploy` stays blocked. If a specific
function needs a change we do it one at a time, after downloading the live
source first.

Also unchanged from my earlier finding: `daily-reports` reads
`DAILY_REPORTS_TOKEN` and `REPORT_FROM`, and **neither secret is set** on
the project.

### 4.3 The three properties, properly synced

Your package showed me the real site and the real admin panel, which are
both bigger than what my repo had:

| Property | Repo had | Package has |
|---|---|---|
| site | 6 files | 24 — incl. `demo.html`, `guide.html`, `pricing.html`, `resources.html`, `sitemap.xml`, `robots.txt`, `img/` |
| admin | small console | real 90 KB `app.js` driving 15 RPCs |
| app | full PWA | full PWA + `operations.js`, `procurement.js`, `condition.js`, `scanner.js` |

Sync means one shared contract across all three: same Supabase project,
same table names, same RPC names, same role vocabulary. I will make the
repo's copies agree with the live schema rather than with my
reconstruction.

---

## 5. Order of work

1. R1 — `create_organization` fix (unblocks signup)
2. R2 — gatekeeper tables + 6 control RPCs (unblocks the Control Center)
3. Reconcile the admin console against the 15 real RPCs
4. Reconcile the site with the package's full page set
5. R3 — verification queries, then re-run all five verify gates

Nothing in steps 1–2 runs itself. Both produce SQL you paste into the
Supabase SQL Editor, because I have no network path to your database.
