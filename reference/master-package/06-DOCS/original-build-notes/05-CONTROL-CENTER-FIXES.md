# Why nothing worked — the real cause

You were right to push back. My previous round fixed the *layout* and nothing else, because I never actually clicked a button — I only checked that the code looked correct. It did look correct. It was still broken.

---

## The actual bug: one line in `index.html`

```html
<script type="module" src="admin.js">
```

`admin.js` is an **ES module**. Module top-level functions are **not global**. But every button in the Control Center is wired with an inline attribute:

```html
<button onclick="requestPage('pending')">
```

Inline `onclick` is evaluated in **global scope**. It cannot see module-scoped functions. So the browser threw `ReferenceError: requestPage is not defined` on click and did nothing visible.

Functions defined as `window.inviteOwner = ...` worked. Functions defined as `async function requestPage()` did not. That is the whole difference, and it explains exactly the pattern you saw: the page renders perfectly, buttons look right, clicking does nothing at all.

**Six functions were affected:** `requestPage`, `invitePage`, `companyPage`, `accountPage`, `storagePage`, `usagePage`. All now exported to `window`.

---

## How I proved it this time

I stopped reading the code and executed it. I loaded the real `index.html`, ran the real `admin.js` against a stubbed database, rendered each page, and **clicked every button the way a browser does** — evaluating the `onclick` attribute in global scope.

That immediately reproduced your bug: `Pending` and `All` were silently dead, while `Approve` and `Delete` fired. Then I swept all of it:

```
pages rendered  : 16/16
controls checked: 69
NO DEAD CONTROLS — every onclick resolves to a real function.
```

---

## What I got wrong before

I wrote tests that asserted the *text* `window.deleteRequest=` existed in the file. It did. That test passed while the button was dead, because the failure was in how the browser resolves the handler, not in whether the code was written. Presence checks cannot catch this. I have made this exact mistake before in this project and I made it again.

I also told you deletes were broken because of a missing SQL grant. **That part was real and you evidently ran the SQL** — I probed your live database and confirmed all five functions now exist and correctly reject unauthorised callers:

```
control_invite_owner             400  Platform administrator required
control_delete_signup_request    400  Platform administrator required
control_delete_owner_invitation  400  Platform administrator required
control_delete_company           400  Platform administrator required
control_revoke_owner_invitation  400  Platform administrator required
```

"Platform administrator required" is the *correct* answer to an anonymous request. Signed in as you, these will run. So the database side is already done — the only thing standing between you and working buttons was the module-scope bug.

---

## Deploy

**Upload `control-center-UPDATE.zip`** to `plantmaster-admin` — `index.html`, `admin.js`, `admin-v1.1.css`, `service-worker.js`.

Cache is bumped to **v1.5.1**. Pull to refresh twice after uploading.

No SQL to run this time. You already did it.

---

## What should work after this upload

- **Pending / All / Purge rejected** filters on Signup Requests
- **Approve** → opens the modal → **Save** creates the invitation
- **Reject** and **Delete** on each enquiry
- **Delete** on companies (type the name to confirm) and on invitations
- Navigation to Companies, Accounts, Storage, Usage from in-page buttons

---

## Honest limits

I tested against a stubbed database, not your live one, because I cannot sign in as a platform admin. What I can now state with confidence: every control resolves to a real function, every page renders without throwing, and the RPCs the UI calls all exist server-side with the argument names the UI sends — I verified those names against your live database, not against my own SQL file.

What I still cannot verify is the behaviour of `control_delete_company` against real data with real foreign keys. It runs in a single transaction, so a constraint I missed will abort cleanly with a readable error rather than half-delete a company. Try it on something disposable first.

---

## Still outstanding

**Your alert emails are still going nowhere.** `hsbfix.org` has no MX records, so `support@hsbfix.org` cannot receive mail. Set `SIGNUP_ALERT_TO` to `xeebawan2@gmail.com` and **redeploy `signup-notify`** — secrets are cached at deploy time, so changing the secret alone does nothing. Also add Porkbun forwarding for `support@` so customer replies reach you.

**`app-UPDATE-3-files.zip`** is still not uploaded to `plantmaster-pro`.
