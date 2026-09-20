# START HERE — PlantMaster Pro launch package

**Status: the code is finished.** Every build passes, every check is green, and
nothing further needs to be written. What remains is work only you can do,
because it needs your accounts, your passwords and your signing key.

There are **6 tasks**. Total hands-on time is roughly **2–3 hours**, plus
Google's review wait (typically 1–7 days for a first submission).

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

## Task 2 · Set up the database and the server functions

**Steps**

1. Install the Supabase CLI: <https://supabase.com/docs/guides/cli>

2. Open a terminal in this folder and connect it to your project:
   ```bash
   npm install
   supabase link --project-ref dpmmenwziplixrgylapy
   ```

3. **Back up first.** In the Supabase dashboard go to
   *Database → Backups* and take a manual backup. The migrations are written
   to merge safely into your existing database rather than replace it, but a
   backup costs you one minute and removes all risk.

4. Apply the database:
   ```bash
   npm run db:push
   ```

5. Deploy the eight server functions:
   ```bash
   npm run functions:deploy
   ```

6. Create a VAPID key pair (needed for phone notifications):
   ```bash
   npx web-push generate-vapid-keys
   ```
   It prints a **Public Key** and a **Private Key**. Keep both.

7. Set the secrets (replace each `...` with your real value):
   ```bash
   supabase secrets set \
     GEMINI_API_KEY=... \
     VAPID_PUBLIC_KEY=... \
     VAPID_PRIVATE_KEY=... \
     VAPID_SUBJECT=mailto:support@hsbfix.org \
     PUSH_INTERNAL_TOKEN=... \
     DAILY_REPORTS_TOKEN=... \
     RESEND_API_KEY=... \
     REPORT_FROM="PlantMaster Pro <reports@hsbfix.org>"
   ```
   - `GEMINI_API_KEY` — from <https://aistudio.google.com/apikey>
   - `RESEND_API_KEY` — from <https://resend.com> (for the daily report email)
   - The two tokens are the ones you generated in Task 1.

8. Open `push-client.js` in this folder. On line 11 replace the value of
   `VAPID_PUBLIC_KEY` with the **public** key from step 6.
   > If this does not match the secret you set, phones will subscribe
   > successfully but every notification will silently fail.

9. Make yourself the platform operator. In the Supabase dashboard open
   *SQL Editor* and run, using your own email:
   ```sql
   insert into public.platform_admins (user_id, email)
   select id, email from auth.users where email = 'you@hsbfix.org'
   on conflict do nothing;
   ```
   > Skip this and `admin.hsbfix.org` will lock **you** out too — the refusal
   > is enforced by the database, not the screen.

10. In the dashboard go to *Authentication → URL Configuration* and add all
    three site addresses to **Redirect URLs**:
    ```
    https://app.hsbfix.org
    https://admin.hsbfix.org
    https://hsbfix.org
    ```
    Missing entries break password reset with an unhelpful error.

**Done when:** `npm run db:push` and `npm run functions:deploy` both finish
without an error.

---

## Task 3 · Put the three websites online

**Steps**

1. Check everything still passes:
   ```bash
   npm run verify
   ```
   You should see `ALL CHECKS PASSED`, `EDGE FUNCTIONS OK`, `WEB PUSH OK`,
   `0 blocking`, and `All internal references resolve.`

2. Publish all three:
   ```bash
   npm run deploy:all
   ```

3. Point your domain names at them in Cloudflare:

   | Address | Points to |
   |---|---|
   | `hsbfix.org` and `www.hsbfix.org` | `plantmaster-site.pages.dev` |
   | `app.hsbfix.org` | `plantmaster-app.pages.dev` |
   | `admin.hsbfix.org` | `plantmaster-admin.pages.dev` |

**Done when:** all three addresses open in a browser.

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

   Paste that fingerprint into **two** files, replacing the placeholder text
   `REPLACE_WITH_PLAY_APP_SIGNING_SHA256_FINGERPRINT`:

   - `.well-known/assetlinks.json`
   - `android/app/src/main/res/values/strings.xml`

   Then republish the web app:
   ```bash
   npm run deploy
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
