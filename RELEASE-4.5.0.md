# PlantMaster Pro v4.5.0 — Professional UI & Multi-user Hardening

This release updates the existing PlantMaster v4 application and preserves the current Supabase project and business data.

## Deployment order

1. Run `schema-phase6-production.sql` once in the existing Supabase SQL Editor.
2. Upload the runtime files from this package to the existing GitHub repository root.
3. Keep the existing `config.js` unchanged.
4. Close all PlantMaster tabs/PWA windows, reopen the HTTPS URL and refresh once.

The SQL migration is additive and does not truncate or intentionally delete existing records.

## Professional interface

- New unified industrial design system in `ui-v4.5.css`.
- Coherent dark and light themes instead of mixed white/dark surfaces.
- Compact branded header with properly aligned logo, plant and status.
- Online status is now a compact presence chip rather than floating text.
- Mobile Logout is kept in the More drawer; desktop Logout remains in the header.
- Compact KPI dashboard and clearer module cards.
- Active mobile bottom-navigation state.
- Improved cards, tabs, dialogs, forms, empty states, support conversations and Gemini output.
- Increased bottom safe area so actions/results are not hidden behind navigation.
- Responsive phone, tablet and desktop layouts.

## Worker invitation delivery

Pending workers now provide:

- Email invitation button
- WhatsApp invitation button
- Native Copy/Share button
- Cancel invitation
- Pending/expiry display

Email uses the device's configured email application. WhatsApp uses `wa.me` with the worker's country-code number. No private email or WhatsApp API key is exposed in the frontend.

## Multi-user improvements

- Realtime subscriptions expanded across operational modules.
- Supabase Presence shows the active plant-user count in the Online status chip.
- Debounced realtime refresh avoids repeated rendering bursts.
- Atomic `transact_spare` RPC locks the stock row and prevents simultaneous negative-stock issues.
- Atomic `transact_tool` RPC prevents simultaneous tool checkout.
- Permission checks are enforced inside both transaction RPCs.
- Row-version metadata and update triggers added for core operational records.
- Additional operational tables added to the Supabase realtime publication.
- Atomic transactions write worker-attributed audit records.

## Verification performed before packaging

- JavaScript syntax checks for `app.js`, `operations.js` and `offline.js`.
- HTML parsing and required navigation element checks.
- CSS brace-balance and required design selector checks.
- Service-worker asset/version checks.
- Local HTTP 200 checks for every required runtime file.
- Secret scan to ensure no Gemini private key value is included.
- Live Gemini Edge Function health test: HTTP 200 with answer, safety, confidence and sources.
- ZIP integrity test.

## Important production statement

This release substantially improves simultaneous-user safety, but no web application should be described as mathematically "flawless." Before APK/Play Store release, authenticated staging should still undergo a controlled 30-user load test, long-duration offline/reconnect testing, and device-camera/microphone testing on the target Android models.
