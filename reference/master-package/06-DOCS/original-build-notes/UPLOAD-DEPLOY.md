# Deploy — 10 minutes, no code editing

Everything is already edited. You just upload files and run one SQL script.

---

## Step 1 — Run the SQL (2 min)

1. Open your Supabase dashboard → **SQL Editor** → **New query**
2. Open `01-schema-procurement.sql`, copy the whole thing, paste, click **Run**
3. You should see `Success. No rows returned`

Then run these two lines in a new query (permissions for the new functions):

```sql
grant execute on function public.next_po_number(uuid) to authenticated;
grant execute on function public.receive_po_line(uuid,numeric,uuid) to authenticated;
```

**If you get an error**, stop and send me the exact message. Most likely cause is a
table named differently than I assumed (e.g. `organizations`). Easy to fix.

---

## Step 2 — Upload 5 files (5 min)

Upload these to wherever `hsbfix.org` is hosted, replacing the existing versions:

| File | Status |
|---|---|
| `index.html` | **replaces** existing |
| `app.js` | **replaces** existing |
| `service-worker.js` | **replaces** existing |
| `procurement.js` | **new file** |
| `csv-import.js` | **new file** |

All five go in the **same folder** — the one that currently has `app.js` and `operations.js`.

> If it's a GitHub repo: drag all five into the repo root on github.com, commit.
> Nothing else needs to change.

---

## Step 3 — Check it worked (3 min)

1. Open `hsbfix.org` on your phone or laptop
2. **Hard refresh** — Ctrl+Shift+R (desktop) or close/reopen the installed app
3. Sign in as **owner**
4. Open the menu — you should see two new entries: **Purchase Orders** and **Suppliers**
5. Suppliers → **＋ Add** → fill in a name → Save
6. Purchase Orders → **＋ Add** → the PO number should pre-fill as `PO-2026-0001`
7. Assets → you should see an **⬆ Import CSV** button

If the new menu items don't appear, the service worker is still serving the old
version — close the app completely, or in a browser open DevTools → Application →
Service Workers → Unregister, then reload.

---

## What changed

**Fixes applied automatically:**
- Chart.js was loaded **twice** → now once, pinned to `4.4.1` (was floating on latest)
- Meta description no longer claims "bilingual" → now accurately describes Urdu/English
  **voice input** and names the manual-grounded AI, which is your real differentiator
- `app.js` bumped to `v4.31.0`, service worker cache to `plantmaster-pro-v4.31.0`
  so returning users actually get the update

**New features:**
- **Suppliers** — name, contact, phone, email, NTN, STRN, payment terms, currency,
  rating. WhatsApp button opens with an Urdu greeting.
- **Purchase Orders** — auto-numbered `PO-2026-0001`, line items, 18% GST default (editable),
  draft → pending_approval → approved → sent → partially_received → received.
  Only owners can approve.
- **Goods receipt** — receiving a line increments spare stock and writes an
  `inventory_transactions` row **in one database transaction**, so stock can never
  drift from the PO.
- **Printable PO** — opens a clean print view with Prepared / Approved / Received
  signature blocks.
- **CSV import** for Assets and Spares, with a downloadable template. Headers are
  fuzzy-matched (`part no`, `Part Number`, `SKU` all work). Bad rows are skipped and
  reported rather than failing the whole file.

---

## Important — a schema correction

While wiring this up I read your real column names, and several differed from what I
assumed in the earlier patch pack:

| I assumed | Actually is |
|---|---|
| `deleted_at` | **`removed_at`** |
| `spares.code` | **`spares.part_number`** |
| `spares.minimum` | **`spares.min_stock`** |
| `spares.location` | **`spares.bin_location`** |
| `assets.code` | **`assets.asset_code`** |

**All files here are corrected.** If you'd deployed the earlier patch pack it would have
failed. Use only what's in this `UPLOAD` folder.

I also found you already have a `material_requests` table with a working
request flow (`PMOps.requestSpare`). The new schema adds a `purchase_order_id` column to
it, so those requests can later be converted into formal POs — that conversion button is
a small follow-up I haven't built yet.

---

## Rollback

If anything breaks, re-upload the previous `index.html`, `app.js` and `service-worker.js`.
The new tables are additive and harmless if unused — nothing existing was dropped or
altered destructively.

---

## Not done yet

- SSO, webhooks, Urdu UI localisation, deeper asset hierarchy
- The rename — say the word once you've settled the domain and I'll do a full
  search-and-replace across both apps, including manifests and icons
- Phase 1 (marketing site, pricing page, G2/Capterra listings) — still the highest-value
  work, and still not code
