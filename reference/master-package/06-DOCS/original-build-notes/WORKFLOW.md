# Who does what — procurement in plain terms

## The two halves

There are **two separate things**, and that's the confusion:

| | Purchase **Request** | Purchase **Order** |
|---|---|---|
| What | "We need this" | "We are buying this from X for Rs Y" |
| Who raises it | **Anyone** — technician, supervisor | **Owner / Manager** only |
| Supplier? | No. Staff don't pick suppliers | Yes — required |
| Price? | No | Yes |
| Goes to | Management, internally | The actual vendor |
| Table | `material_requests` | `purchase_orders` |

**That's why requesting didn't take you to a supplier.** A request is a shop-floor
signal: *"the Husky cylinder is running out."* The technician has no business
choosing the vendor or agreeing a price — that's a commercial decision.

---

## Who does what

| Step | Who | Where |
|---|---|---|
| 1. Raise a request | Technician / supervisor / anyone | Spares & Tools → 🛒 **Request** |
| 2. Review requests | Owner or Manager | Spares & Tools → 🛒 Purchase Requests |
| 3. Convert to a PO | Owner or Manager | **→ Convert to PO** — pick supplier, tick items |
| 4. Add unit prices | Owner or Manager | Purchase Orders → Open → edit lines |
| 5. Submit for approval | Owner or Manager | **Submit** — status becomes `pending_approval` |
| 6. **Approve** | **Owner only** | **Approve** |
| 7. Send to supplier | Owner or Manager | **Print** → WhatsApp / email the PDF |
| 8. Receive goods | Owner or Manager | **Receive** → enter quantity |
| 9. Stock updates | Automatic | `spares.stock` increases |

**The one hard rule: only an `owner` can approve.** A manager can build the PO and
submit it, but cannot approve their own order. That separation is the point of the
approval step — it's what makes the audit trail worth anything.

---

## Your current state

`PO-2026-0002` is **approved** and the Husky cylinder request is linked to it.

**Next step: Purchase Orders → Receive.** Not "Mark Received" on the request.

---

## A bug this exposed

Your screenshot showed **✓ Mark Received (Adds to Stock)** on a request that was
already on a PO. Pressing it would have added the quantity to stock, and then
receiving the PO would have added it **again** — double-counted.

Fixed in v4.33.1:

- That button no longer appears on requests linked to a PO
- Instead you get **"Receive on PO-2026-0002 →"**, which takes you to the right place
- The underlying function refuses the double-add even if called another way

The rule now: **stock moves in exactly one place per request** — on the PO if there
is one, on the request if there isn't.

---

## When to skip the PO entirely

For petty cash — a Rs 500 item bought from the corner shop — a PO is overhead.

Raise the request, **Mark Ordered**, then **Mark Received** when it arrives. Stock
updates, you keep the audit trail, and no PO is involved. That path still works and
is the right one for small purchases.

Use a PO when you need a document the vendor will act on: a price, GST, payment
terms, a signature block.
