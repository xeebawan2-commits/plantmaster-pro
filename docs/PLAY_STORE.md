# Google Play submission — PlantMaster Pro

The Android app is a **Trusted Web Activity**: a thin native shell that renders
`https://app.hsbfix.org` full-screen with no browser chrome. You ship the web
app as normal and the store listing points at the same code.

| Field | Value |
|---|---|
| Application ID | `org.hsbfix.plantmaster` |
| Launch URL | `https://app.hsbfix.org` |
| versionCode / versionName | `1` / `4.49.0` |
| minSdk / targetSdk | 24 (Android 7.0) / 35 (Android 15) |
| Project | `android/` (Gradle, androidbrowserhelper 2.5.0) |

---

## The one thing that will bite you

A TWA only hides the URL bar when **two** files agree:

1. `app/src/main/res/values/strings.xml` → `asset_statements`
2. `https://app.hsbfix.org/.well-known/assetlinks.json`

Both must contain the SHA-256 of the certificate that **actually signs the
installed app**. If you use Play App Signing — and you should — that is
Google's certificate, not your upload key. The file in this repo currently
holds the placeholder:

```
REPLACE_WITH_PLAY_APP_SIGNING_SHA256_FINGERPRINT
```

Get the real value **after** the first upload:

> Play Console → your app → **Test and release → Setup → App signing** →
> *App signing key certificate* → copy the SHA-256 fingerprint.

Then replace the placeholder in **both** files, redeploy the web app, and
verify:

```bash
curl -s https://app.hsbfix.org/.well-known/assetlinks.json | jq .
npm run verify:pwa      # the advisory disappears once it is a real fingerprint
```

Symptom of getting this wrong: the app works but shows a Chrome address bar at
the top. Verification is retried by Android, so fixing the JSON and
reinstalling usually resolves it without a new upload.

---

## 1. Create the signing key

Cannot be done in this workspace (no JDK). On your own machine:

```bash
keytool -genkeypair -v \
  -keystore plantmaster-release.jks \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -alias plantmaster
```

Then create `android/keystore.properties` (git-ignored — see
`keystore.properties.example`):

```properties
storeFile=/absolute/path/to/plantmaster-release.jks
storePassword=...
keyAlias=plantmaster
keyPassword=...
```

**Back the keystore up somewhere you will still have in five years.** With Play
App Signing a lost upload key can be reset by Google; without it, you can never
update the app again.

---

## 2. Build the release bundle

```bash
cd android
./gradlew bundleRelease
# -> app/build/outputs/bundle/release/app-release.aab
```

Check the version before every upload — Play rejects a duplicate
`versionCode`. Bump `versionCode` (integer, +1) and `versionName` (match the
web app) in `android/app/build.gradle`.

---

## 3. Store listing copy

**App name** (30 max)
```
PlantMaster Pro
```

**Short description** (80 max)
```
Maintenance, work orders and asset management for industrial plants.
```

**Full description** (4000 max)
```
PlantMaster Pro is a complete maintenance management system for industrial
plants — cement, steel, textile, sugar, chemical and food processing.

Run your maintenance from the plant floor, not from a desk.

WORK ORDERS
Raise, assign, prioritise and close corrective work. Track downtime, labour
minutes, spare parts consumed and the real root cause of every failure.

ASSET REGISTER
Every machine with its nameplate data, manuals, history and QR code. Scan the
code on the machine to open its record instantly.

PREVENTIVE MAINTENANCE
Weekly, monthly, quarterly and yearly plans that generate work automatically,
so routine servicing does not depend on somebody remembering.

DIGITAL CHECKLISTS
Shift rounds and inspections with pass/fail limits. A failed reading raises an
alarm immediately instead of sitting in a notebook until morning.

CONDITION MONITORING
Record machine sound and vibration with the phone, compare against an approved
baseline, and get an early warning about bearing wear, misalignment,
unbalance, looseness and cavitation.

AI PROBLEM SOLVER
Ask a question in plain language and get an answer grounded in your own
equipment manuals, your plant's solved-case history and approved technician
experience — with safety precautions stated first.

SPARES, TOOLS AND PURCHASING
Stock levels, minimum quantities, tool custody and calibration, purchase
requests, approvals and goods receipt.

PEOPLE AND SHIFTS
Attendance, shift assignments, handover notes and daily logs.

DOCUMENT INTELLIGENCE
Upload equipment manuals as PDF. They are indexed automatically and become
searchable, quotable knowledge for the whole team.

WORKS OFFLINE
Plant basements and steel structures kill signal. PlantMaster keeps working
and syncs when the connection returns.

BUILT FOR REAL PLANTS
Role-based access from owner to operator. Every record is isolated per
company. Urdu voice input for technicians who prefer to dictate. Reports and
documents carry your own company branding.

Free 30-day trial. No credit card required.

HSB Fix Services, Karachi, Pakistan
support@hsbfix.org
```

---

## 4. Graphic assets

| Asset | Spec | In repo |
|---|---|---|
| App icon | 512×512 PNG, 32-bit | `play-assets/play-store-icon-512.png` |
| Feature graphic | 1024×500 PNG | `play-assets/feature-graphic-1024x500.png` |
| Phone screenshots | ≥2, 16:9 or 9:16, min 320px | `screenshots/dashboard-narrow.png` |
| Tablet screenshots | optional | `screenshots/dashboard-wide.png` |

Play wants a minimum of two phone screenshots; capture a few more from a real
device once you have live data — assets, a work order and the Problem Solver
answering a question are the three that sell the product.

---

## 5. Data safety form

Answer these consistently with `site/privacy.html` or the listing will be
rejected on review.

| Question | Answer |
|---|---|
| Does the app collect data? | Yes |
| Is data encrypted in transit? | Yes (HTTPS/TLS everywhere) |
| Can users request deletion? | Yes — in-app, and `hsbfix.org/delete-account.html` |
| Personal info | Name, email — account management |
| Photos | Equipment photos — app functionality |
| Audio | Machine sound recordings — app functionality |
| Files | Equipment manuals — app functionality |
| Location | Not collected |
| Financial info | Not collected |
| Data shared with third parties | No |

Declare the AI features honestly: uploaded text, images and audio are sent to
Google Gemini for processing.

**Account deletion URL** (required, must be reachable without signing in):
```
https://hsbfix.org/delete-account.html
```

---

## 6. Content rating & declarations

- Category: **Business** (secondary: Productivity)
- Content rating questionnaire: no objectionable content → **Everyone / PEGI 3**
- Target audience: 18+, not designed for children
- Ads: none
- In-app purchases: none (subscriptions are invoiced directly, outside Play)
- Permissions: `INTERNET`, `CAMERA` (QR/nameplate scanning), `RECORD_AUDIO`
  (condition monitoring). Each is requested at point of use, with the reason
  shown.

Because billing happens outside the app, do **not** describe subscription
pricing inside the Android build — Play's payments policy treats in-app
promotion of external payment as a violation. The pricing lives on
`hsbfix.org`.

---

## 7. Release checklist

- [ ] `npm run verify` green
- [ ] Web app deployed; `app.hsbfix.org` loads and installs
- [ ] `assetlinks.json` holds the **Play App Signing** SHA-256 (not the upload key)
- [ ] `strings.xml` `asset_statements` holds the same fingerprint
- [ ] `versionCode` bumped
- [ ] `./gradlew bundleRelease` succeeds
- [ ] Uploaded to **internal testing** first
- [ ] Installed from internal testing: **no URL bar**
- [ ] Sign-in, work order, camera scan and push all work on a real device
- [ ] Data safety form submitted
- [ ] Privacy policy URL reachable: `https://hsbfix.org/privacy.html`
- [ ] Account deletion URL reachable
- [ ] Promote internal → closed → production

---

## 8. After the first release

Every subsequent web deploy updates the Android app automatically — the TWA
loads the live site, so there is no new upload for a normal change. You only
need a new bundle when you change the native shell: icons, name, permissions,
launch URL, or the target SDK level Play requires each year.
