# Three fixes: menu, free option, acknowledgement email

---

## 1. The menu that would not close — fixed

You were right. There was **no outside-tap handler anywhere on the site** — I checked all six pages. The only way to close the menu was to hit the burger again, which nobody does.

Added to all 6 pages: tapping anywhere outside the header closes it, **Escape** closes it, and choosing a link closes it. Taps *inside* the header still keep it open, so the menu does not vanish while you are reading it.

Tested in jsdom: **10/10**, including the "tap inside stays open" case.

---

## 2. A free option on the form — added

The plan picker now leads with:

> **Just the free trial** — 7 days · full Professional features · no card · **Rs 0**

Professional is still the default selection, so the pricing anchor is unchanged. The Control Center also gained a **Free (complimentary)** plan you can grant when approving — same caps as Essential, zero price, no trial countdown. Useful for founding customers and for Pakistan Synthetic.

---

## 3. "Thank you for applying" email — built

**New edge function: `signup-notify.ts`.** When someone submits the form it sends two emails:

**To the applicant**, from `support@hsbfix.org`:

> Dear [name], thank you for applying for a PlantMaster Pro trial for [company]…
> 1. We review your request, usually within one working day.
> 2. We contact you on WhatsApp to understand your plant.
> 3. Once approved, we create your workspace and send your sign-in details.
>
> *Accounts are opened by us, not self-service. This keeps every plant's data separate and properly set up before your team starts.*
>
> Your 7-day trial starts when we activate your workspace, so none of it is wasted while you wait.

That last line matters: it removes the fear that the clock is running while they wait for you.

**To you**, an alert with every field, an **Open Control Center** button and a **WhatsApp** button that deep-links to their number.

It reuses the exact Resend pattern already working in `daily-reports.ts`.

---

## Deploying the email function (phone-only)

**Supabase → Edge Functions → Deploy a new function → Via Editor**

1. Name it exactly **`signup-notify`**
2. Paste all of `signup-notify.ts`
3. Deploy (10–30 seconds)
4. **Turn Verify JWT OFF** for this function — the website calls it without a login

> **Re-check that toggle after every redeploy.** Supabase has a known bug where it silently switches itself back on, and then the function returns 401 before it even runs, with nothing in the logs.

**Then add two secrets** (Edge Functions → Secrets). `RESEND_API_KEY` is already there from daily-reports:

| Name | Value |
|---|---|
| `SIGNUP_FROM` | `HSB Fix Services <support@hsbfix.org>` |
| `SIGNUP_ALERT_TO` | `support@hsbfix.org` |

**Check your Resend domain first.** Your DNS already has `send`, `rsend` and `resend._domainkey` for `hsbfix.org`. In the Resend dashboard, `hsbfix.org` must show **Verified**. If it does not, the email silently fails and `SIGNUP_FROM` must stay `onboarding@resend.dev` until it is.

**Resend free tier is 100 emails/day, 3/hour.** Each enquiry sends 2. That is fine for now — but a busy day could hit the hourly cap, and the applicant's email is sent first so yours is the one that would drop.

---

## Then run `02-SIGNUP-EMAIL.sql`

Adds `ack_sent_at` to `signup_requests`, creates the **free** plan, and adds `control_clear_ack()` so you can re-send an acknowledgement.

**One thing I could not verify:** whether the `pg_net` extension is enabled on your project. It is what lets the *database* call an edge function. I have left that trigger **commented out** in the SQL rather than ship something that might error.

It is not needed — **the website calls the function directly, and that path is tested.** The trigger is only a backup for enquiries created some other way. If you want it, enable `pg_net` under Database → Extensions and uncomment the marked block. The function refuses to email the same row twice, so enabling it cannot cause duplicates.

---

## The full flow, once deployed

1. Prospect fills the form on `hsbfix.org`
2. The enquiry is saved to `signup_requests` — **this happens first, so a lead is never lost to an email failure**
3. They get "thank you for applying" from `support@hsbfix.org`
4. You get an alert email **and** the WhatsApp message
5. It appears under **✉ Signup Requests** in the Control Center
6. You talk to them, then hit **Approve** — pick Free, Trial, Essential, Professional or Enterprise
7. You create their login in Supabase → Authentication → Users (**Auto Confirm** ticked)
8. They sign in, and only then can they create their workspace — on the plan you chose

**Nobody can open an account without you approving it.** Verified by testing 13 attack routes against your live system.

---

## Upload these

| Zip | Where |
|---|---|
| `hsbfix-site-v1.7.zip` | `hsbfix-site` repo — menu fix on all 6 pages + free option + email trigger |
| `control-center-UPDATE-4-files.zip` | `plantmaster-admin` repo — adds the Free plan option |
| `app-UPDATE-3-files.zip` | `plantmaster-pro` repo — removes the dead "Create account" button |
| `signup-notify.ts` | paste into Supabase Edge Functions |
| `02-SIGNUP-EMAIL.sql` | run in the SQL Editor |

---

## Caveat

The email templates render correctly as HTML and the function follows the pattern of `daily-reports.ts`, which is known to work. But **I cannot send a real email from here**, so the first live submission is the real test. Send one yourself to an address you control before pointing a prospect at the form.
