# Read this first

Last updated 20 September 2026, after your master package arrived.

Everything below has been checked against the live schema snapshot in
`reference/master-package/05-DATABASE/03-live-schema-snapshot/`
(83 tables, 73 functions, 135 policies, captured 13 September 2026 from
project `dpmmenwziplixrgylapy`).

---

## Why "create organization" fails

Proven, not guessed. The live `create_organization()` runs four inserts:

```
organizations        ok
organization_members ok
plants               FAILS
plant_members        never reached
```

`plants` carries a trigger, `enforce_plant_plan_limit`, whose first act is
to look up the company's subscription:

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

`create_organization` never inserts into `organization_subscriptions`. So
the lookup always returns nothing, the trigger always raises, and the whole
function rolls back. **No organization can ever be created.** It is a
deadlock: no plant without a subscription, and nothing creates one.

I reproduced this on a real Postgres before writing the fix, and the test
is kept so it can never silently regress:

```
node tools/db-verify/repair-test.mjs
  ✓ live version fails exactly as reported: "Active subscription required"
  ✓ nothing was created — the whole transaction rolled back
```

---

## What you need to run, in order

Four files in `supabase/repairs/`. Open each in the Supabase **SQL Editor**,
set the row-limit dropdown beside Run to **No limit**, and run it.

| Order | File | What it does |
|---|---|---|
| 1 | `R1-fix-organization-creation.sql` | Inserts the subscription **before** the plant. Signup works again. |
| 2 | `R2-control-center.sql` | Adds `owner_invitations` + `signup_requests` and the six missing control RPCs. Your Control Center buttons start working. |
| 3 | `R4-company-features.sql` | Lets you give one company a module the others do not get, from the Control Center. |
| 4 | `R3-verify.sql` | Read-only. 19 checks; every row tells you what it should say. |

All three are idempotent — safe to run twice. They only **add**; nothing is
dropped or renamed.

R4 is optional but you asked to control everything from admin: without it the
per-company module editor can only take features away, never add them.

**R1 alone restores open signup. R2 then closes it**, so a workspace can only
be created by someone you invited from the Control Center. Run R1 first even
though R2 supersedes it: if anything goes wrong at step 2 you are still in a
working state.

After R3, look at row 13, *"companies with NO subscription"*. Any company
created before the fix is in that broken state. The bottom of R3 has a
commented-out block that attaches the trial plan to them — read the list
first, then uncomment and run it.

---

## Why the Control Center buttons did nothing

`admin.hsbfix.org` calls 15 RPCs. Six did not exist in your database:

| RPC | Written in | Was it ever run? |
|---|---|---|
| `control_invite_owner` | `30--01-GATEKEEPER.sql` | no |
| `control_revoke_owner_invitation` | `30--01-GATEKEEPER.sql` | no |
| `control_delete_company` | `32--03-DELETE-AND-FIXES.sql` | no |
| `control_delete_owner_invitation` | `32--03-DELETE-AND-FIXES.sql` | no |
| `control_delete_signup_request` | `32--03-DELETE-AND-FIXES.sql` | no |
| `control_purge_signup_requests` | `32--03-DELETE-AND-FIXES.sql` | no |

Proof they never ran: both scripts create `owner_invitations` and
`signup_requests`, and neither table exists in the live snapshot.

The last three SQL scripts in your build order were written but never
applied. That single fact explains the create-organization failure *and* the
dead Control Center buttons.

**One correction I made.** The packaged `control_delete_company` deleted from
a hand-written list of 20 tables, but 61 live tables carry an
`organization_id`. I checked every foreign key in your constraint export:
56 already have `ON DELETE CASCADE`, 4 are `SET NULL`, and only `ai_usage`
genuinely blocks the delete. So R2 clears the five real blockers and lets
the database cascade the rest — shorter, and actually complete. Testing also
caught `owner_invitations.created_org_id` blocking the delete; R2 makes it
`ON DELETE SET NULL`.

---

## What is safe to run right now

| Command | Safe? | Notes |
|---|---|---|
| `npm run deploy` | **yes** | app.hsbfix.org. Carries the push fix and the rewritten service worker. |
| `npm run deploy:admin` | **yes** | admin.hsbfix.org. Needs R1+R2 first, or the buttons still fail. |
| `npm run deploy:site` | **yes, now** | `site/` is your real 24-file site again. It was a 6-file reconstruction; deploying that would have destroyed hsbfix.org. |
| `npm run db:push` | **NO — blocked** | Would create 5 duplicate tables. Use the R-scripts instead. |
| `npm run functions:deploy` | **NO — blocked** | Would overwrite 7 live functions, including ones whose source you no longer have. |

The last two are blocked by `scripts/confirm-schema.mjs` and will refuse to
run. That guard stays.

---

## Still yours to do

1. **Rotate `PUSH_INTERNAL_TOKEN`.** It was committed in plain text at
   `6c367eb` and is still in git history. Change it in Supabase Secrets and
   in the GitHub Actions secrets.
2. **Set `DAILY_REPORTS_TOKEN` and `REPORT_FROM`** in Supabase Secrets.
   `daily-reports` reads both and neither is set, so it cannot send.
3. **Paste the VAPID public key** into `push-client.js` line 11, or push
   delivery fails silently. Generate with `npx web-push generate-vapid-keys`.
4. **Two PDFs** into `site/docs/`, named exactly as
   `site/docs/PUT-YOUR-PDFS-HERE.txt` says, or the resources page 404s.
5. **Recover the lost function sources** when you next have a laptop:
   `npx supabase functions download create-owner` (also
   `platform-admin-api` and `signup-notify`). They run live but their code
   is not in any repo, so right now they cannot be changed or restored.

---

## The thing I got wrong earlier

Before your package arrived I reconstructed `supabase/migrations/0001`–`0009`
and said they were safe to apply because 66 tests passed. Those tests only
proved the migrations were consistent *with each other*. Measured against
your real database they would have created five duplicate tables
(`ai_usage_events` beside `ai_usage`, `app_complaints` beside
`platform_support_tickets`, and three more) and split your data in two.

They are kept as a reference model only. Your live schema is the source of
truth, and it is considerably richer than my reconstruction.
