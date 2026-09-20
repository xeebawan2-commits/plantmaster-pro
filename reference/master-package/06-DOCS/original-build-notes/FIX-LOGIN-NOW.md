# "Email logins are disabled" — fix this first

## What happened

Supabase's Email provider panel has **two switches**, and my instruction was not precise enough. I said *"Authentication → Providers → Email → disable Allow new users to sign up"*. The **master switch** at the top of that same panel got turned off instead.

Live state, read from your project just now:

| Setting | Now | Should be |
|---|---|---|
| **Email** (master provider switch) | **OFF** | **ON** |
| **Allow new users to sign up** | **ON** | **OFF** |

The result is the opposite of the goal: **everyone is locked out — you, and any customer — while public signup is technically still open.** The master switch overrides everything nested beneath it, so no email login works at all.

My wording caused this. The two controls sit in the same panel and read almost identically.

---

## The fix (1 minute)

**Supabase Dashboard → Authentication → Sign In / Providers → Email**

You will see a switch at the top of the panel, with options indented below it:

```
  [ ON  ]   Email                          <-- turn this BACK ON

              Allow new users to sign up     [ OFF ]   <-- turn THIS one off
              Confirm email                  [ ON  ]   <-- leave on
```

- **Top switch = the provider.** Off means nobody can sign in, ever.
- **"Allow new users to sign up" = the signup gate.** This is the one that stops strangers.

Save. You will be able to sign in immediately.

---

## How to confirm it worked

Reload `admin.hsbfix.org`. The red *"Email logins are disabled"* line should be gone and your password should work.

If you want to be certain of the underlying state, this URL returns the raw settings in any browser:

```
https://dpmmenwziplixrgylapy.supabase.co/auth/v1/settings?apikey=sb_publishable_TlKlrk7ulAG8G7EptLCllA_Rbgt7YXY
```

You are looking for:

```json
"email": true          <-  provider on
"disable_signup": true <-  signups closed
```

Both must read that way. `"email": false` is the lockout. `"disable_signup": false` means strangers can still register.

---

## Good news on the rest

**`admin.hsbfix.org` is working.** You added the DNS and the CNAME, and it resolves and serves correctly over HTTPS.

**The 4-file update is deployed.** I fetched the live `admin.js` — 62,030 bytes, md5 matches my build exactly, and it contains `control_invite_owner`, `requestPage` and `invitePage`. `config.js` correctly points at `app.hsbfix.org`.

So once you flip the two switches, you should sign straight in and see **✉ Signup Requests** and **✓ Invitations** in the drawer.

---

## Then carry on

1. **Fix the two switches** (above)
2. Sign in to `admin.hsbfix.org`
3. Delete my `pmtest.*` and `probe.*@mailinator.com` test accounts (Authentication → Users)
4. Run **`01-GATEKEEPER.sql`** — until you do, the two new pages will show *"Request failed"*, because the tables do not exist yet
5. Run the `platform_admins` insert from `03-DEPLOY-CONTROL-CENTER.md` if sign-in reports *"Active Platform Administrator record not found"*
6. Upload `signup.html` from `hsbfix-site-v1.6.zip` to the `hsbfix-site` repo
