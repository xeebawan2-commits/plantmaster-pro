# Can anyone sign up by themselves? — tested against the live system

**Answer: no.** I attacked it from outside with no credentials. Every route is closed.

Tested 14 September 2026 against `dpmmenwziplixrgylapy.supabase.co`.

---

## Your settings are now correct

| Setting | Value | Meaning |
|---|---|---|
| Email provider | **ON** | you and your customers can sign in |
| Allow new users to sign up | **OFF** | strangers cannot register |
| Confirm email | ON | |
| Anonymous sign-ins | OFF | |
| Phone auth | OFF | |
| OAuth providers (Google, GitHub…) | **all OFF** | no side door |
| SAML | OFF | |

---

## Attacks I ran, and what happened

| # | Attack | Result |
|---|---|---|
| 1 | `POST /auth/v1/signup` with email + password | **`signup_disabled`** — "Signups not allowed for this instance" |
| 2 | Anonymous sign-in (no email at all) | **`anonymous_provider_disabled`** |
| 3 | **Magic-link / OTP with `create_user:true`** | **`signup_disabled`** |
| 4 | Phone OTP | **`phone_provider_disabled`** |
| 5 | OAuth redirect (`?provider=google`) | **HTTP 400** |
| 6 | Admin API `POST /auth/v1/admin/users` | **HTTP 401** |
| 7 | `POST /auth/v1/invite` | **HTTP 401** |
| 8 | Password recovery on a non-existent email | `{}` — no account created |
| 9 | Call `create_organization` directly by RPC | **"Authentication required"** |
| 10 | Insert into `owner_invitations` to self-approve | **permission denied** |
| 11 | Read `signup_requests` (see other leads) | **permission denied** |
| 12 | Update a request to `status='approved'` | **HTTP 401** |
| 13 | Delete from `signup_requests` | **HTTP 401** |

**Attack 3 is the one most people miss.** Magic links create an account by default, which bypasses a signup form entirely. It is blocked here.

---

## The gatekeeper SQL is confirmed deployed

I verified this indirectly, since I cannot read your tables:

- `signup_requests` and `owner_invitations` return **`42501` (permission denied)**, not **`PGRST205` (table not found)**. The tables exist and are protected.
- `control_invite_owner`, `control_set_plan` and `check_ai_quota` all answer **"Platform administrator required"** / **"Membership required"**. They exist and refuse anonymous callers.

## The website form still works

`POST /rest/v1/signup_requests` returned **HTTP 201**. So a prospect can file an enquiry, but **cannot read, approve, alter or delete anything** — confirmed by attacks 11, 12 and 13.

**One cleanup job for you:** that test created a row called **"VERIFY TEST - delete me"** in your enquiries. Delete it from the Control Center once you can sign in. I deliberately could not delete it myself, which is the correct behaviour.

---

## One thing I fixed

`app.hsbfix.org` still showed a **"Create account with email"** button. It was not a security hole — signup is blocked server-side — but a prospect tapping it got a raw error: *"Signups not allowed for this instance."* That looks broken.

**`app-UPDATE-3-files.zip`** → upload `index.html`, `app.js`, `service-worker.js` to the **`plantmaster-pro`** repo.

- Removed the dead button; replaced it with: *"Accounts are created by HSB Fix Services. Request access at hsbfix.org or message us on WhatsApp."*
- **Guarded the handler in `app.js`.** Removing the button alone would have crashed the app at load — `$('#signUp').onclick` on a missing element throws and stops all the auth wiring below it. Now `const _su=$('#signUp');if(_su)…`.
- Service-worker cache bumped `v4.33.1` → `v4.42.0` so phones actually fetch the new files.

Verified: 8/8 jsdom checks, `app.js` passes `node --check`, sign-in / password / forgot-password all intact.

---

## What is left open, honestly

**Someone can still spam your enquiry form.** It is a public endpoint with no CAPTCHA — by design, so the website works. The damage is junk rows in one table that only you can read. If it ever happens, add a CAPTCHA or a rate limit.

**Existing accounts still work.** Turning off signup does not remove anyone. Check Authentication → Users and delete anyone who should not be there. My `pmtest.*` accounts are already gone — I confirmed they can no longer log in.

**A logged-in user with no company still reaches "Create company".** The screen appears, but the gatekeeper rejects the submission unless you issued them an invitation. Ugly rather than dangerous, and only visible to someone who already has an account.
