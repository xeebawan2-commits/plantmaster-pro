# PlantMaster Pro — what to do, from your phone

Everything here can be done on a phone in a browser. No laptop, no
Android Studio, no command line. Where a step normally needs a computer I
have replaced it with something that runs in the cloud.

Read this page top to bottom once before you start. The order matters:
**the database comes first**, because the websites cannot work until it is
repaired.

---

## What is in this zip

| Folder | What it is | Where it goes |
|---|---|---|
| `UPLOAD-app/` | the customer app, built and ready | Cloudflare Pages → `plantmaster-pro` → app.hsbfix.org |
| `UPLOAD-site/` | the marketing site, built and ready | Cloudflare Pages → `plantmaster-site` → hsbfix.org |
| `UPLOAD-admin/` | the Control Center, built and ready | Cloudflare Pages → `plantmaster-admin` → admin.hsbfix.org |
| `DATABASE/` | four SQL files | paste into Supabase SQL Editor |
| `source/` | the full editable project | keep; this is what you edit later |
| `reference/` | your original master package, untouched | keep as backup |

The three `UPLOAD-*` folders are **already built**. You do not need to run
anything to produce them. Drag the folder into Cloudflare and it is live.

---

## Step 1 · Repair the database  ⚠️ do this first

Nothing else works until this is done. Right now **no one can create a
company account** — including you.

### Why it is broken

Your `create_organization` function inserts a plant before it creates the
subscription. But the plant table has a trigger that refuses to add a plant
unless a subscription already exists. So it fails every time with
*"Active subscription required"* and rolls the whole thing back.

It is a circle: no plant without a subscription, and nothing makes the
subscription.

The same missed step left **six buttons in your Control Center calling
functions that do not exist** — Invite Owner, Approve, Delete company, and
the signup queue.

### What to do

1. Open [supabase.com](https://supabase.com) in your phone browser and sign in.
2. Open project **dpmmenwziplixrgylapy**.
3. Go to **Database → Backups** and take a manual backup. One minute. Do not skip.
4. Go to **SQL Editor**. Next to the **Run** button there is a row-limit
   dropdown — set it to **No limit**.
5. Open `DATABASE/R1-fix-organization-creation.sql` from this zip in any text
   app, select all, copy, paste into the editor, press **Run**.
6. Repeat for the others **in this order**:

| Order | File | What it fixes |
|---|---|---|
| 1 | `R1-fix-organization-creation.sql` | creating a company works again |
| 2 | `R2-control-center.sql` | the six dead Control Center buttons |
| 3 | `R4-company-features.sql` | giving one company extra modules |
| 4 | `R3-verify.sql` | checks the other three worked |

`R3` changes nothing — it only reports. It prints **19 rows**, each with a
`result` and a `want` column. They should match.

> **Look at row 13: "companies with NO subscription".**
> If it is not `0`, those companies were created before the fix and are in a
> broken state. The bottom of `R3` has a commented-out block that repairs
> them. Read the list it prints first, then remove the `--` marks from the
> `insert` and run just that part.

All four files are safe to run twice. They only add things; nothing is
deleted or renamed.

### After it runs

Make sure you are a platform admin, or the Control Center will lock **you**
out too. In the SQL Editor, with your own email:

```sql
insert into public.platform_admins (user_id, email)
select id, email from auth.users where email = 'you@hsbfix.org'
on conflict do nothing;
```

---

## Step 2 · Put the three sites online

Cloudflare Pages accepts a drag-and-drop upload from a phone browser.

1. Open [dash.cloudflare.com](https://dash.cloudflare.com) → **Workers & Pages**.
2. You already have three projects. For each one, open it → **Create
   deployment** (or *Upload assets*) → select the matching folder from this zip:

| Cloudflare project | Upload this folder | Becomes |
|---|---|---|
| `plantmaster-pro` | `UPLOAD-app/` | app.hsbfix.org |
| `plantmaster-site` | `UPLOAD-site/` | hsbfix.org |
| `plantmaster-admin` | `UPLOAD-admin/` | admin.hsbfix.org |

Upload the **contents** of the folder, not the folder itself. If the site
comes up blank, that is usually the mistake — you should see `index.html` at
the top level of what you uploaded.

Your DNS is already correct. Nothing to change there.

> **One warning about hsbfix.org.** It is currently served from a *separate*
> GitHub repository called `hsbfix-org`, which auto-builds on push. If you
> upload `UPLOAD-site/` to Cloudflare directly, the next push to that repo
> will overwrite it. Pick one method and stick to it. Either:
> - **keep using the `hsbfix-org` repo** — then copy `delete-account.html`
>   and the `img/` folder from `UPLOAD-site/` into that repo instead; or
> - **switch to uploading** — then stop pushing to `hsbfix-org`.

### Supabase redirect URLs

In Supabase → **Authentication → URL Configuration**, make sure all three
are in the **Redirect URLs** list:

```
https://app.hsbfix.org
https://admin.hsbfix.org
https://hsbfix.org
```

Missing entries break password reset with a confusing error.

---

## Step 3 · Three secrets to set

Supabase → **Edge Functions → Secrets**.

| Secret | Value | Why |
|---|---|---|
| `PUSH_INTERNAL_TOKEN` | a new long random string | **the old one leaked** — it is in your git history in plain text. Change it. |
| `DAILY_REPORTS_TOKEN` | any long random string | not set today, so daily reports cannot send |
| `REPORT_FROM` | `PlantMaster Pro <reports@hsbfix.org>` | not set today, same reason |

Put the same `PUSH_INTERNAL_TOKEN` and `DAILY_REPORTS_TOKEN` into GitHub →
your repo → **Settings → Secrets and variables → Actions**.

To make a random string on a phone: mash 40+ characters, or use any password
generator app.

### Notifications need one more thing

Phone notifications will not work until a VAPID key pair exists. This
normally needs a command line. Instead:

1. Open <https://www.attheminute.com/vapid-key-generator> (or any "VAPID key
   generator" site) and generate a pair.
2. Put the **private** key in Supabase secrets as `VAPID_PRIVATE_KEY`, the
   **public** key as `VAPID_PUBLIC_KEY`, and add
   `VAPID_SUBJECT` = `mailto:support@hsbfix.org`.
3. Open `source/push-client.js`, find `VAPID_PUBLIC_KEY` on **line 11**, and
   paste the **public** key there. Then re-upload the app folder.

> If the key in `push-client.js` does not match the secret, phones will
> subscribe successfully and every notification will then fail silently.
> That is the single most common cause of "push doesn't work".

---

## Step 4 · Leave the edge functions alone

All 14 are already running on Supabase and working. Do not redeploy them.

Three of them — `create-owner`, `platform-admin-api`, `signup-notify` — exist
**only** on Supabase. Their source code is not in this zip and not in any
repository, because it was never saved. If you overwrite one, it is gone for
good.

If you ever get access to a computer, rescue them first:

```
npx supabase functions download create-owner
npx supabase functions download platform-admin-api
npx supabase functions download signup-notify
```

---

## Step 5 · Google Play

You cannot build an Android app on a phone. So I added a workflow that
builds it on GitHub's computers instead.

### 5a. Create the signing key

This is the one step that genuinely needs a keyboard-ish environment. Two
phone options:

- **Termux** (free, from F-Droid): install it, run `pkg install openjdk-17`,
  then:
  ```
  keytool -genkeypair -v -keystore plantmaster-release.jks \
    -keyalg RSA -keysize 4096 -validity 10000 -alias plantmaster
  ```
- **Or** ask someone with a laptop to run that one command and send you the
  `.jks` file.

**Back this file up somewhere safe.** If you lose it you can never update the
app again under the same listing.

### 5b. Put the key into GitHub

You need the file as base64 text. In Termux:

```
base64 -w0 plantmaster-release.jks > key.txt
```

Then in GitHub → your repo → **Settings → Secrets and variables → Actions**,
add four secrets:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the entire contents of `key.txt` |
| `ANDROID_KEYSTORE_PASSWORD` | the store password you chose |
| `ANDROID_KEY_ALIAS` | `plantmaster` |
| `ANDROID_KEY_PASSWORD` | the key password you chose |

### 5c. Build it

GitHub → **Actions** → **Build Android app bundle** → **Run workflow**.

Wait a few minutes, then download the **plantmaster-aab** artifact. That is
your `.aab` file for the Play Console.

### 5d. Submit

Play Console → create the app → upload the `.aab`. Listing text is in
`source/docs/PLAY_STORE.md`.

### 5e. The one step people get wrong

After your first upload, Play generates its **own** signing key, which is
different from the one you just made.

Go to **Play Console → Test and release → Setup → App signing** and copy the
**SHA-256 certificate fingerprint** shown there. Then edit
`UPLOAD-app/.well-known/assetlinks.json` and
`UPLOAD-site/.well-known/assetlinks.json`, replacing:

```
REPLACE_WITH_PLAY_APP_SIGNING_SHA256_FINGERPRINT
```

with that fingerprint. Re-upload both folders to Cloudflare.

> Get this wrong and the app still works, but it opens with an ugly browser
> address bar across the top instead of looking like a real app.

---

## Step 6 · Two PDFs

`hsbfix.org/resources.html` has two download buttons that currently 404.
Put your two PDFs into `UPLOAD-site/docs/` with **exactly** these names:

```
PlantMaster-Pro-Overview.pdf
PlantMaster-Pro-Subscription-Agreement.pdf
```

One character different and the button breaks.

---

## Checklist

- [ ] Database backup taken
- [ ] R1, R2, R4, R3 run — all 19 rows match
- [ ] Row 13 is `0`, or the repair block was run
- [ ] You are in `platform_admins`
- [ ] Three folders uploaded to Cloudflare
- [ ] Three redirect URLs set in Supabase
- [ ] `PUSH_INTERNAL_TOKEN` rotated
- [ ] `DAILY_REPORTS_TOKEN` + `REPORT_FROM` set
- [ ] VAPID keys set and pasted into `push-client.js` line 11
- [ ] Signing key created and backed up
- [ ] `.aab` built and uploaded to Play
- [ ] `assetlinks.json` updated with the **Play App Signing** fingerprint
- [ ] Two PDFs added

---

## What changed in this version

**The database.** Found and fixed the reason no company could be created,
and the reason six Control Center buttons did nothing. Four SQL scripts,
1,018 lines, every one tested against a real PostgreSQL before you see it.

**The Control Center.** Replaced with your real 90 KB one from the master
package — nine sections, all 15 functions wired. I had been working from a
much smaller reconstruction. Also fixed a bug that would have stopped it
loading at all: it imports a setting the app's config file does not export.

**The marketing site.** My copy had 6 files; your real site has 24. Uploading
mine would have destroyed hsbfix.org. It is now your real site, plus the
account-deletion page Google Play requires.

**A live bug on hsbfix.org.** Every page asks for four icon files at
`/img/...` that are actually stored at the top level. Fixed.

**The app.** `push-client.js` called a function that was never defined, which
threw an error and stopped notification setup before it began — that is why
no device has ever received one. The service worker also cached files under
names it could never look up again, so offline mode never worked. Both fixed.

**Checks.** 40 automated tests now run against a real database engine,
covering all four repair scripts.

---

## If something goes wrong

- **A site shows a blank page** → you uploaded the folder instead of its
  contents. Re-upload so `index.html` is at the top level.
- **Control Center says "Platform administrator required"** → run the
  `platform_admins` insert from Step 1.
- **Control Center buttons still do nothing** → R2 did not run. Re-run it and
  check R3 row 7 says `6`.
- **Signup says "Active subscription required"** → R1 did not run.
- **Signup says "Accounts are approved by HSB Fix Services"** → that is
  correct behaviour after R2. Invite the person from the Control Center
  first, then they can sign up.
- **App loads but is stale** → it is a PWA; close every tab and reopen, or
  pull to refresh twice.

Everything is also mirrored in the GitHub repository on branch
`arena/01a0be08-plantmaster-pro`, so nothing here is the only copy.
