# START HERE — PlantMaster Pro launch package

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

**Status: the code is finished.** Every build passes, every check is green, and
nothing further needs to be written. What remains is work only you can do,
because it needs your accounts, your passwords and your signing key.

There are **6 tasks**. Total hands-on time is roughly **2–3 hours**, plus
Google's review wait (typically 1–7 days for a first submission).

> **Wondering what to upload where, or whether you need a new account or
> database?** Read **`WHAT-GOES-WHERE.md`** first — short answer: no new
> accounts, and there is almost no manual uploading. Three commands publish
> everything.

Do them in order. Task 4 depends on Task 3, and Task 6 depends on all of them.

---

## Task 1 · Rotate the leaked push token  ⚠️ do this first

A secret token was committed in plain text to your **public** GitHub repository
before this renewal. It has been removed from the current code, but **it is
still readable in the git history** at commit `6c367eb`. Anyone who has ever
seen that repo can still read it. Until you rotate it, a stranger can trigger
your push-notification endpoint.

> This zip does **not** contain the git history, so the token is not in here.
> The exposure is on GitHub only.

**Steps**

1. Generate two fresh random tokens. On Mac/Linux run this twice:
   ```bash
   openssl rand -base64 32
   ```
   On Windows PowerShell:
   ```powershell
   [Convert]::ToBase64String((1..32|%{Get-Random -Max 256}))
   ```
   Call the first one `PUSH_INTERNAL_TOKEN`, the second `DAILY_REPORTS_TOKEN`.
   Keep them in your password manager.

2. You will paste them into two places in Task 2 and Task 5. The old value is
   then dead.

**Done when:** you have two new random strings saved.

---

## Task 2 · Repair the database

Your database is already built — 83 tables, 73 functions, 135 policies. It
does **not** need creating. It needs three specific repairs.

Do **not** run `npm run db:push` or `npm run functions:deploy`. Both are
deliberately blocked. They describe a clean-slate database and would create
duplicate tables alongside your real ones.

**Steps**

1. **Back up first.** Supabase dashboard → *Database → Backups* → take a
   manual backup. One minute, removes all risk.

2. Open Supabase → **SQL Editor**. Set the row-limit dropdown beside *Run*
   to **No limit**.

3. Run these three files from `supabase/repairs/`, in order. Open each,
   copy the whole contents, paste, Run:

   | Order | File | Fixes |
   |---|---|---|
   | 1 | `R1-fix-organization-creation.sql` | signup — creating a company works again |
   | 2 | `R2-control-center.sql` | the Control Center's dead buttons |
   | 3 | `R4-company-features.sql` | per-company module control in the Control Center |
   | 4 | `R3-verify.sql` | read-only; confirms the others worked |

   R3 prints 19 rows, each with a *result* and a *want* column. They should
   match. If row 13 (*companies with NO subscription*) is not `0`, the bottom
   of R3 has a commented-out block that repairs those companies — read the
   list it prints first.

4. Make yourself the platform operator, if you are not already:
   ```sql
   insert into public.platform_admins (user_id, email)
   select id, email from auth.users where email = 'you@hsbfix.org'
   on conflict do nothing;
   ```
   > Skip this and `admin.hsbfix.org` locks **you** out too — the refusal is
   > enforced by the database, not the screen.

5. Set the two secrets that are missing. Supabase → *Edge Functions →
   Secrets*:
   - `DAILY_REPORTS_TOKEN` — any long random string; put the same value in
     your GitHub Actions secrets
   - `REPORT_FROM` — e.g. `PlantMaster Pro <reports@hsbfix.org>`

   `daily-reports` reads both. Neither is set today, so it cannot send.

6. Create a VAPID key pair for phone notifications, if you have not already:
   ```bash
   npx web-push generate-vapid-keys
   ```
   Set `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY` and
   `VAPID_SUBJECT=mailto:support@hsbfix.org` as secrets, then open
   `push-client.js` and put the **public** key on line 11.
   > If the two do not match, phones subscribe successfully and every
   > notification then fails silently.

7. Supabase → *Authentication → URL Configuration* → add all three addresses
   to **Redirect URLs**:
   ```
   https://app.hsbfix.org
   https://admin.hsbfix.org
   https://hsbfix.org
   ```
   Missing entries break password reset with an unhelpful error.

**Done when:** every row of `R3-verify.sql` matches its *want* column.

> **Leave the edge functions alone.** All 14 are deployed and working. Three
> of them — `create-owner`, `platform-admin-api`, `signup-notify` — exist
> *only* on Supabase; their source is in no repository. Overwriting one would
> be unrecoverable. If you ever need to change one, download it first:
> `npx supabase functions download create-owner`.

---

## Task 3 · Put the three websites online

**Steps**

1. Check everything still passes:
   ```bash
   npm run verify
   ```
   You should see `ALL CHECKS PASSED`, `EDGE FUNCTIONS OK`, `WEB PUSH OK`,
   `0 blocking`, and `All internal references resolve.`

2. Publish the app and the admin console:
   ```bash
   npm run deploy         # app.hsbfix.org
   npm run deploy:admin   # admin.hsbfix.org
   ```

   > `npm run deploy:site` is now safe too — `site/` holds your real 24-file
   > site, not the old 6-page reconstruction. Run it **only** if you want this
   > repo to drive hsbfix.org; if you do, stop pushing to the `hsbfix-org`
   > repo so the two do not fight over the same Cloudflare project. See
   > `WHAT-GOES-WHERE.md` → *So what do I do about the marketing site?*

3. Your DNS is already correct — all three addresses are live in Cloudflare
   (`plantmaster-pro`, `plantmaster-site`, `plantmaster-admin`). Nothing to
   change.

4. One page Google Play requires: a publicly reachable **account deletion**
   page. Your live `hsbfix.org` does not have one yet.
   - If you stay on the `hsbfix-org` repo: copy `site/delete-account.html`
     into it, add a footer link, add it to `sitemap.xml`, and push —
     Cloudflare publishes automatically. Copy `site/img/` across too; your
     live pages link four favicons at `/img/...` that are not there today.
   - If you ran `npm run deploy:site`: it is already published.

**Done when:** `app.hsbfix.org`, `admin.hsbfix.org` and
`hsbfix.org/delete-account.html` all open.

---

## Task 4 · Create your Android signing key

This could not be done for you — it requires a Java installation and, more
importantly, it is the one secret that must never leave your possession.

**Steps**

1. Install Java (any JDK 17+), then run:
   ```bash
   keytool -genkeypair -v \
     -keystore plantmaster-release.jks \
     -keyalg RSA -keysize 4096 -validity 10000 \
     -alias plantmaster
   ```
   It asks for a password and your organisation details.

2. **Back up `plantmaster-release.jks` somewhere you will still have in five
   years** — a password manager, an encrypted drive, and a second location.

3. Copy `android/keystore.properties.example` to
   `android/keystore.properties` and fill in your real path and passwords.
   That file is already excluded from git and will never be uploaded.

4. Build the app bundle:
   ```bash
   cd android
   ./gradlew bundleRelease
   ```
   The result is `android/app/build/outputs/bundle/release/app-release.aab`.

**Done when:** the `.aab` file exists.

---

## Task 5 · Submit to Google Play

Full listing text, the data-safety answers and the content rating answers are
all written out for you in **`docs/PLAY_STORE.md`** — copy and paste from there.

**Steps**

1. Create the app at <https://play.google.com/console> (one-time US$25 fee).

2. Upload the `.aab` to **Internal testing** first, not production.

3. **The critical step.** Go to
   *Test and release → Setup → App signing* and copy the
   **SHA-256 certificate fingerprint**.

   Paste that fingerprint into these **two files**, replacing the placeholder
   text `REPLACE_WITH_PLAY_APP_SIGNING_SHA256_FINGERPRINT`:

   - `.well-known/assetlinks.json`  ← the one that matters
   - `site/.well-known/assetlinks.json`  ← keep the copy in sync

   > You do **not** touch `strings.xml`. It is already correct. It carries the
   > app's side of the handshake, which only names the website; the
   > fingerprint only ever goes in `assetlinks.json`.

   Then republish:
   ```bash
   npm run deploy && npm run deploy:site
   ```

   > **Why this matters:** without it the app still works, but it shows a
   > browser address bar across the top and looks like a web page instead of
   > an app. This is the single most common mistake with this type of app.
   > Use Google's fingerprint, **not** your own upload key.

4. Install the app from internal testing on a real phone. **No address bar =
   correct.** If you see one, re-check step 3.

5. Fill in the store listing, data safety form and content rating from
   `docs/PLAY_STORE.md`, then promote internal → production.

**Done when:** the app installs from Play with no address bar.

---

## Task 6 · Final check on a real phone

Walk through these once before telling customers:

- [ ] Sign in works
- [ ] Create a work order
- [ ] Scan a QR code with the camera
- [ ] Enable alerts, then run the **Push poller** workflow manually in GitHub
      (*Actions → Push poller → Run workflow*) — the phone should buzz
- [ ] Upload a small PDF manual; it should reach "indexed"
- [ ] Ask the Problem Solver something answerable from that manual
- [ ] Open `admin.hsbfix.org` in a private window with a **customer** account —
      it must refuse access
- [ ] Turn on airplane mode; the app should still open and work

Also add these to GitHub under
*Settings → Secrets and variables → Actions*, so the scheduled jobs run:

| Secret | Value |
|---|---|
| `PUSH_FN_URL` | `https://dpmmenwziplixrgylapy.supabase.co/functions/v1/web-push` |
| `PUSH_INTERNAL_TOKEN` | your new token from Task 1 |
| `SUPABASE_ANON_KEY` | the key already in `config.js` |
| `DAILY_REPORTS_FN_URL` | `https://dpmmenwziplixrgylapy.supabase.co/functions/v1/daily-reports` |
| `DAILY_REPORTS_TOKEN` | your second new token from Task 1 |

---

## What is in this package

| Folder | What it is | Do you edit it? |
|---|---|---|
| *(root)* `index.html`, `app.js`, `service-worker.js`, the `.css` files | **The application itself** — app.hsbfix.org | Yes, this is the product |
| `config.js` | Your Supabase address and public key | Only if you change project |
| `push-client.js` | Phone notification sign-up | Yes — Task 2 step 8 |
| `manifest.webmanifest` | Makes it installable as an app | Rarely |
| `.well-known/assetlinks.json` | Links the website to the Android app | Yes — Task 5 step 3 |
| `site/` | **Marketing website** — hsbfix.org, incl. privacy, terms, delete-account | Yes, your public pages |
| `admin/` | **Operator console** — admin.hsbfix.org, for you, not customers | Yes |
| `android/` | **Google Play app project** | Only the fingerprint + version |
| `supabase/migrations/` | **The database**, 9 numbered files, applied in order | Add new numbered files only |
| `supabase/functions/` | **8 server functions** (AI, notifications, reports) | Yes, if changing AI behaviour |
| `supabase/config.toml` | Project settings and per-function security | Rarely |
| `scripts/` | Build and the 5 automated checks | No |
| `tools/` | Test harnesses (database, push crypto, screenshots) | No |
| `docs/` | **Your three manuals** — read these | Reference |
| `icons/`, `play-assets/`, `screenshots/` | App icons and store images | Replace if rebranding |
| `.github/workflows/` | Scheduled notification + daily report jobs | No |

**Not included, created automatically:** `node_modules/` (run `npm install`),
`public/` and `dist/` (run `npm run build`). Never edit those — they are
overwritten on every build.

### The three manuals in `docs/`

- **`DEPLOYMENT.md`** — full runbook: migrations, secrets, DNS, smoke tests, rollback
- **`DATABASE.md`** — the security audit: what is protected, what the 66 tests prove, the bugs found
- **`PLAY_STORE.md`** — keystore, asset links, **ready-to-paste listing text**, data safety answers

---

## If something breaks

Run `npm run verify` first. It checks five things independently and tells you
which one failed:

| Check | Covers |
|---|---|
| `verify:db` | Database: 9 migrations + 66 security assertions |
| `verify:fn` | Server functions exist, compile, hold no secrets |
| `verify:push` | Notification encryption actually works |
| `verify:pwa` | Installability, icons, screenshots, Play requirements |
| `verify:links` | No broken file references in any of the three sites |

To undo a website change, Cloudflare Pages keeps every previous deployment —
promote an older one from the dashboard. Database changes are forward-only:
add a new `0010_*.sql` rather than editing a file already applied.

---

HSB Fix Services · Karachi, Pakistan · support@hsbfix.org
