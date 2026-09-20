# Locking down signups — what to do, in order

**The problem:** anyone who finds `app.hsbfix.org` can create an account and a full workspace. I proved this against your live system. This closes it.

**Time: about 20 minutes, all from your phone.**

---

## What I found when I looked properly

Your Control Center is **not** wasted work. Most of the enforcement you wanted is already built and working at the database level:

| Limit | Already enforced? | How |
|---|---|---|
| Users per company | **Yes** | `enforce_worker_plan_limit` trigger on `organization_members` and `invitations` — counts active members *plus* pending invites |
| Plants per company | **Yes** | `enforce_plant_plan_limit` trigger |
| Storage bytes | **Yes** | `reserve_storage_upload()` refuses the upload |
| File count and file size | **Yes** | same function |
| Suspend a company | **Yes** | `require_commercial_write_access` on **31 tables** |
| Block a single feature | **Yes** | `company_feature_blocks` + `company_feature_allowed()` |
| Give one customer extra headroom | **Yes** | `quota_overrides` — absolute, bonus or block |
| **AI request limits** | **No** | the columns exist in `subscription_plans`, nothing checked them |
| **Who may create a company** | **No** | ← this is the hole |

**Why none of it was firing:** every one of those checks starts by looking up the company's subscription. `create_organization()` never created one. So a self-signed-up company had no plan, and the limits either errored or never applied. Fixing signup fixes the whole chain.

---

## Step 1 — Turn off public signup (2 minutes, do this now)

Supabase Dashboard → **Authentication** → **Sign In / Providers** → **Email**.

**This panel has TWO switches. Getting them the wrong way round locks everyone out.**

```
  [ ON  ]   Email                        <-- MASTER. Must stay ON.
              Allow new users to sign up   [ OFF ]   <-- turn THIS off
              Confirm email                [ ON  ]   <-- leave on
```

- The **top switch** is the provider itself. Turning it off disables **all** email sign-in, including yours.
- **"Allow new users to sign up"** is the one that stops strangers.

Verify with this URL in any browser — you want `"email": true` and `"disable_signup": true`:

`https://dpmmenwziplixrgylapy.supabase.co/auth/v1/settings?apikey=sb_publishable_TlKlrk7ulAG8G7EptLCllA_Rbgt7YXY`

> Existing users keep working. The approval flow below invites the people you choose.

## Step 2 — Delete my two test accounts

Authentication → Users → search `mailinator` → delete both `pmtest.*` accounts I created while proving the hole was real.

---

## Step 3 — Run the gatekeeper SQL (5 minutes)

SQL Editor → New query → paste all of **`01-GATEKEEPER.sql`** → set the dropdown beside **Run** to **"No limit"** → Run.

It prints a verification table at the end. You want to see:

```
create_organization gated    YES — locked
signup_requests table        yes
owner_invitations table      yes
plans seeded                 4
```

**What it does:**

1. **Seeds your four real plans** — Trial, Essential (10 users), Professional (25 users), Enterprise — with the user, plant, storage and AI caps you actually sell.
2. **Rewrites `create_organization()`** so it refuses unless the caller's own email matches a live invitation *you* issued. Strangers get: *"Accounts are approved by HSB Fix Services."*
3. **Creates `signup_requests`** — the website writes enquiries here. Anyone can insert, **only platform admins can read**. It grants nothing.
4. **Creates `owner_invitations`** — your approvals. One live invitation per email, 14-day expiry, single use.
5. **Attaches a subscription automatically when you approve** — which is what switches on every existing limit.
6. **Adds `check_ai_quota()`** — the missing AI enforcement (per minute, per day, per month).
7. **Adds `control_company_overview`** — one view showing every company's usage against its limits.

---

## Step 4 — Upload the website and Control Center changes

**Website** (`hsbfix-site` repo): upload the new `signup.html` from `hsbfix-site-v1.6.zip`. The form now files every enquiry into your approval queue **and** still opens WhatsApp exactly as before. If the database call fails, the WhatsApp handoff still works — it cannot break the form.

**Control Center**: you already have the `plantmaster-admin` repo and **it is live** at `xeebawan2-commits.github.io/plantmaster-admin/` — I was wrong earlier, I had only tested `/admin/` sub-paths. Upload the **4 changed files** from `control-center-UPDATE-4-files.zip`. Do not make a new repo. Full steps in `03-DEPLOY-CONTROL-CENTER.md`.

---

## Step 5 — How you onboard a customer from now on

1. Prospect fills the form on `hsbfix.org` → lands in **Enquiries** in your Control Center, and you get the WhatsApp message.
2. You talk to them. You decide.
3. Control Center → **Approve** → set company name, plant name, plan, trial days.
4. Because public signup is off, you create their login: Authentication → Users → **Add user** → their email → tick *Auto Confirm*. Send them the password over WhatsApp and tell them to change it.
5. They sign in, see "Create company", and the workspace is created **with the plan you chose**.
6. From then on the database enforces everything: the owner can only invite up to their user limit, only one plant, storage capped, AI capped.

---

## What happens when they hit a limit

| They try to | They see |
|---|---|
| Invite an 11th user on Essential | *"Worker limit of 10 reached (active 9, pending 1)"* |
| Create a second plant | *"Plant limit of 1 reached"* |
| Upload past their storage | *"Storage limit reached"* |
| Use AI past the monthly cap | *"Monthly AI limit of 500 requests reached. Contact HSB Fix Services to increase it."* |
| Anything, while suspended | *"Company access is suspended"* — writes blocked across 31 tables |

To give one customer more without changing their plan, insert a `quota_overrides` row of type `bonus`. To take something away, type `block`.

---

## Step 6 — Wire AI enforcement into the edge functions

`check_ai_quota()` now exists but nothing calls it yet. In `smart-responder.ts`, `vision-scanner.ts`, `condition-analyzer.ts` and `voice-translate.ts`, before calling Gemini:

```ts
const { error: quotaError } = await supabase.rpc('check_ai_quota', { p_org: organizationId });
if (quotaError) return json({ error: quotaError.message }, 429);
```

Those functions already write to `ai_usage` after each call, so the counting side is done.

**Leave this until after Steps 1–5.** Turning off public signup is the urgent part; AI overuse needs a customer first.

---

## Honest limits of this work

- **The SQL has not been run against a live Postgres.** I have no database in this workspace. It was checked with a SQL lexer (quotes, dollar-quotes, parentheses all balanced), every referenced table and function was verified to exist in your schema dump, and the positional INSERTs into `organization_members` and `plant_members` match the column order of the original function exactly. Run it and read the verification output.
- **Existing companies are untouched.** If Pakistan Synthetic has no subscription row, its limits still will not apply. Fix it from the Control Center: **Companies & Limits → Change plan**.
- **Rate limiting is not solved.** With public signup off it does not matter. If you ever reopen self-serve trials, you need a CAPTCHA and a disposable-email block first.
- **The form posts with your publishable key**, which is safe and intended — RLS allows insert only, and reading enquiries requires a platform admin. A determined person could spam the table; if that ever happens, add a CAPTCHA.
