# PlantMaster Pro v4.4.2 — Profile, Workers, Support and Solver

## Replace these runtime files

Upload these five files to the existing GitHub repository root:

- `index.html`
- `app.js`
- `operations.js`
- `styles.css`
- `service-worker.js`

No additional SQL is required when `schema-phase5-operations.sql` from v4.4.0 has already been run.

## Company Profile corrected

- Responsive, labelled profile form instead of the broken label/input flow.
- Logo preview and live header logo.
- Saved primary and secondary colours apply throughout the app immediately.
- Five themes automatically select distinct colour palettes.
- Five patterns apply to the live workspace.
- Saved plant display name, application title and logo are applied again at login.
- Address, contact, email, report time and document footer are saved correctly.
- Compact mobile Logout and Online header restored.

## Add Worker corrected

- The action is now **Add Worker**, not Invite Worker.
- Owner enters name, employee ID, designation, email, role, shift, contact and skills.
- The worker appears immediately in People as **Pending**.
- Owner can share the secure account link or cancel the pending worker.
- After the worker signs in through the link, the existing secure invitation RPC activates their membership and profile without exposing an admin/service-role key.

## Technical Support completed for basic operation

- New Support Issue form with subject, priority and first message.
- Voice-to-text for the first message and replies.
- Persistent multi-user conversation history.
- Worker name/designation and reply timestamp display.
- Open, close and reopen support issues.
- Audit entries for issue creation, reply and status changes.

## Problem Solver modes

- **Manual**: searches uploaded manual names, extracted document chunks, approved technical experiences and verified plant cases.
- **Gemini**: securely invokes the `gemini-problem-solver` Supabase Edge Function.
- **Gemini + Manual**: supplies matching plant manual/experience context and asks Gemini to use those sources.
- **Google**: opens a focused industrial-maintenance Google search.
- Search/diagnosis text supports voice input on HTTPS.
- Gemini result displays answer, safety guidance, confidence and sources.
- Gemini answers can be saved as plant problem cases.
- Saved case history remains accessible.

## Gemini deployment

Gemini requires the Supabase Edge Function named:

```text
gemini-problem-solver
```

The included `gemini-problem-solver/index.ts` is server-side code. Deploy it through Supabase and set the Edge Function secret:

```text
GEMINI_API_KEY
```

Never place the Gemini key in GitHub, `app.js`, `index.html`, localStorage or a QR code. Google mode does not require a key because it opens Google Search in the browser.

## Cache refresh

After uploading the five runtime files, close every PlantMaster browser/PWA tab, reopen the HTTPS site and refresh once if an older cached version is still displayed.
