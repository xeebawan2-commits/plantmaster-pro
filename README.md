# PlantMaster Pro

Maintenance management for industrial plants — work orders, assets, preventive
maintenance, digital checklists, condition monitoring, spares and procurement,
with an AI problem solver grounded in the plant's own manuals.

Built as an offline-capable PWA, shipped to Android as a Trusted Web Activity.

---

## The three properties

| | Source | Build output | Deploy |
|---|---|---|---|
| **hsbfix.org** — marketing & legal | `site/` | `dist/site` | `npm run deploy:site` |
| **app.hsbfix.org** — the application | repo root | `public/` | `npm run deploy` |
| **admin.hsbfix.org** — operator console | `admin/` | `dist/admin` | `npm run deploy:admin` |

All three are independently deployable from this one repository.
`public/` and `dist/` are generated and git-ignored.

---

## Quick start

```bash
npm install
npm run verify     # all five gates must pass
npm run dev        # app :8080 · site :8081 · admin :8082
```

---

## Verification

`npm run verify` is the gate before any deploy.

| Command | Proves |
|---|---|
| `npm run verify:db` | 9 migrations apply to a real Postgres; 66 RLS / RPC / tenant-isolation assertions hold |
| `npm run verify:fn` | Every invoked edge function exists, type-checks, is declared in `config.toml`, holds no hard-coded secret |
| `npm run verify:push` | The hand-written web-push crypto produces payloads a real browser decrypts, and VAPID JWTs verify |
| `npm run verify:pwa` | Manifest, true icon dimensions, screenshots, service worker, asset links, security headers |
| `npm run verify:links` | Every `src`, `href` and local import in all three builds resolves |

The database tests run against genuine PostgreSQL (PGlite/WASM) with real JWT
impersonation, so policies are evaluated exactly as PostgREST evaluates them —
not mocked.

---

## Layout

```
├── index.html app.js service-worker.js …   the PWA (repo root)
├── site/                 marketing site + legal pages
├── admin/                platform operator console
├── android/              Gradle TWA project for Play
├── supabase/
│   ├── migrations/       0001–0009, idempotent, versioned
│   ├── functions/        8 edge functions + _shared guard
│   └── config.toml       API, auth, storage and per-function JWT settings
├── scripts/              build, serve and the four verifiers
├── tools/
│   ├── db-verify/        Postgres test harness
│   ├── fn-check/         edge-function type check + web-push test
│   └── screenshots/      manifest / Play screenshot renderer
├── docs/                 deployment, database audit, Play submission
├── play-assets/          store icon + feature graphic
└── screenshots/          manifest + listing screenshots
```

---

## Architecture notes

**Security is enforced in Postgres, not in the UI.** The admin console ships
no privileged key — it uses the same anon key as the app and is gated by
`is_platform_admin()`. A customer who loads `admin.hsbfix.org` can sign in, and
every `platform_*` RPC will still be refused by the database.

**Edge functions never trust the request body.** The `organization_id` a client
sends is a claim that is checked against `organization_members` server-side
before anything happens.

**AI usage is metered against the plan** in `_shared/guard.ts`, so a runaway
client cannot spend an unbounded amount of Gemini quota.

**Web push is dependency-free** — RFC 8291 payload encryption and RFC 8292
VAPID implemented directly on Web Crypto, so the function has no third-party
supply chain and no CDN fetch at cold start.

---

## Documentation

| Document | Contents |
|---|---|
| [`START-HERE.md`](START-HERE.md) | The 6 remaining owner tasks, in order |
| [`WHAT-GOES-WHERE.md`](WHAT-GOES-WHERE.md) | What deploys where; new vs existing accounts |
| [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) | Full runbook: migrations, function secrets, DNS, smoke tests, rollback |
| [`docs/DATABASE.md`](docs/DATABASE.md) | The schema/policy audit, what the 66 tests assert, bugs found |
| [`docs/PLAY_STORE.md`](docs/PLAY_STORE.md) | Keystore, asset links, listing copy, data safety form, release checklist |

---

## Outstanding items requiring the owner

1. **Rotate `PUSH_INTERNAL_TOKEN`.** It was committed in plain text and is
   still in git history at `6c367eb`.
2. **Supply the Play App Signing SHA-256** in `.well-known/assetlinks.json`
   (and its mirror in `site/`) — available only after the first upload to the
   Play Console.
3. **Seed `platform_admins`** before using the admin console.
4. **Generate the release keystore** (needs a JDK; see `docs/PLAY_STORE.md`).

---

HSB Fix Services · Karachi, Pakistan · support@hsbfix.org
