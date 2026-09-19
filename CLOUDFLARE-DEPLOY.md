# Customer app Cloudflare deployment

The customer app is a static Cloudflare Worker asset deployment. The previous
build failed because Cloudflare detected `npx wrangler deploy` but the repository
did not contain a Wrangler configuration, so Wrangler entered its interactive
first-time setup during the non-interactive build.

This folder now contains `wrangler.jsonc` and a pinned Wrangler dev dependency.
Keep the Cloudflare Workers Build settings as follows:

- **Root directory:** `/`
- **Build command:** `npx wrangler deploy`
- **Deploy command:** leave the repository default, or use `npx wrangler deploy`
- **Worker name:** `plantmaster-pro`

Do not use a separate output directory. The static app files are the asset
directory itself.

After the first successful deployment:

1. Open `https://app.hsbfix.org/`.
2. Confirm the login screen loads.
3. Confirm `https://app.hsbfix.org/service-worker.js` returns JavaScript, not HTML.
4. Hard-refresh the app or unregister the old service worker once on a test phone.

No database SQL is required to fix this Cloudflare build failure. SQL is only
needed if the app opens successfully but reports a missing table, column, RPC,
or policy error from Supabase.

The supplied database pack defines all 45 tables referenced by the current
customer-app JavaScript. Do not re-run every historical SQL file against the
live database: several files are phased repairs and commercial/control-center
updates. If you need to verify a separate Supabase project before using SQL,
check its existing schema first and apply only the missing phase.