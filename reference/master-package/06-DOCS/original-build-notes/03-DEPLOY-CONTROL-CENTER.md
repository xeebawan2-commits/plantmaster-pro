# Updating the Control Center

## I was wrong — it is deployed

You already have **`plantmaster-admin`**, and it has been live this whole time:

```
https://xeebawan2-commits.github.io/plantmaster-admin/   200 OK
```

**My mistake:** I tested `app.hsbfix.org/admin/` and `hsbfix.org/admin/`, got 404 on both, and concluded it was never deployed. I never tested the obvious thing — its own repo URL. A 404 on two guessed paths is not evidence a site does not exist. **Do not create a new repository.** Use the one you have.

I also checked my local copy against the live files: `admin.js` is byte-identical to what is deployed, so nothing of yours was out of date or at risk of being overwritten with something older.

---

## Upload 4 files to `plantmaster-admin`

Only four files changed. No folders, nothing else to touch.

**`control-center-UPDATE-4-files.zip`** → `index.html`, `admin.js`, `config.js`, `service-worker.js`

GitHub → `plantmaster-admin` → **Add file** → **Upload files** → drop all four → **Commit changes**. They overwrite the existing ones.

---

## What changed and why

| File | Change |
|---|---|
| `admin.js` | **Invite Owner button fixed.** It called `adminApi({action:'invite_owner'})` — an action the edge function never implemented. It has always failed with *"Unknown QA action"*. Now calls `control_invite_owner` by RPC. |
| `admin.js` | **Signup Requests page** — website enquiries with Approve / Reject / WhatsApp / Email. |
| `admin.js` | **Invitations page** — live, used, expired, revoked, with Revoke. |
| `index.html` | Both pages added to the drawer; **Approvals** added to the mobile bottom bar. |
| `config.js` | `CUSTOMER_APP_URL` was still `xeebawan2-commits.github.io/plantmaster-pro/`. Now `https://app.hsbfix.org`. |
| `service-worker.js` | Cache bumped to `v1.4.0`. **Without this your browser keeps serving the old `admin.js` from cache and the update looks like it did nothing.** |

**Your icons are untouched.** I had generated crude replacements believing `icons/` was missing. It is not — your real PlantMaster Pro artwork is there and is much better. I downloaded the live versions back over mine. `manifest.webmanifest`, `admin.css` and `admin-v1.1.css` are unchanged, so they are not in the upload.

---

## After uploading — force the cache to clear

The service worker is aggressive. After committing:

1. Open `https://xeebawan2-commits.github.io/plantmaster-admin/`
2. **Pull down to refresh**, twice
3. If the new menu items are still missing: Chrome → **⋮** → **Settings** → **Privacy** → **Clear browsing data** → *Cached images and files* → clear, then reopen

If you installed it to your home screen, remove and re-add it.

You will know it worked when the drawer shows **✉ Signup Requests** and **✓ Invitations** under Companies.

---

## Custom domain — optional, and not required

I originally told you to add a `CNAME` file. **I have removed it from the upload** because it would break the working URL: `admin.hsbfix.org` has no DNS record yet, so committing a CNAME would take the site offline until Porkbun propagated.

The current URL works fine. If you do want `admin.hsbfix.org` later, the order matters:

1. **Porkbun first** → `hsbfix.org` → DNS → add **CNAME**, host `admin`, answer `xeebawan2-commits.github.io`
2. Wait until it resolves
3. **Then** upload the `CNAME` file from `gatekeeper/optional-custom-domain/`
4. GitHub → Settings → Pages → tick **Enforce HTTPS** once the certificate is issued

Leave the Resend records (`send`, `rsend`, `resend._domainkey`) alone.

---

## Before the new pages will work

They read two tables that do not exist yet. **Run `01-GATEKEEPER.sql` first** or both pages will show *"Request failed"*.

And you need a `platform_admins` row, or the Control Center signs you in then refuses with *"Active Platform Administrator record not found"*:

```sql
insert into public.platform_admins (user_id, admin_role, display_name, active)
select id, 'super_admin', 'HSB Fix Services', true
from auth.users
where email = 'YOUR-EMAIL-HERE'
on conflict (user_id) do update
  set admin_role = 'super_admin', active = true;
```

---

## Full order

1. Supabase → Authentication → Email → **turn off "Allow new users to sign up"**
2. Delete my two `pmtest.*@mailinator.com` test accounts
3. Run **`01-GATEKEEPER.sql`**
4. Run the `platform_admins` insert above
5. Upload the **4 files** to `plantmaster-admin`
6. Upload `signup.html` from `hsbfix-site-v1.6.zip` to `hsbfix-site`
7. Test: submit the form on hsbfix.org → it should appear under **Signup Requests**

---

## Caveat

The new pages passed jsdom structure and routing checks (9/9) and `admin.js` parses cleanly as an ES module, but I cannot sign in as a platform admin from here, so they have not been rendered against live data. If a page shows "Request failed", the error banner names the column at fault.
