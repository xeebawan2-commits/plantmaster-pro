# AI Cost Guard v8 — stops the repeat-billing + cheaper reads

## Why you saw $1.95
NOT your questions (a question costs ~$0.0002). It was the repeated
indexing attempts on the 14.8 MB manual during debugging — each attempt
re-read the whole document several times and Gemini bills each read.

## What v8 changes
1. **50-page batches** → a 150-page manual now costs only 3 full reads
   (was 6-7).
2. **Re-index guard**: tapping "Index for AI" on an already-indexed manual
   now ASKS first ("already indexed — re-index uses credits again?").
   No more accidental re-billing.
3. **Stale-state cleanup**: a job that dies with the app is marked
   "index failed — tap to retry" on next open (honest status, no ghost
   jobs, no surprise auto-runs).
4. **Durable status**: "indexing…" is saved BEFORE any AI call, so the app
   can never double-start a job.

Costs after this: big manual ≈ $0.04-0.08 ONE TIME. Questions ≈ free.

## Deploy (2 steps)
1. Supabase → Edge Functions → **ingest-manual** → Code tab → delete all →
   paste entire `supabase-functions/ingest-manual.ts` → **Deploy** (JWT ON)
2. GitHub → upload `app.js` → Commit → upload `index.html` → Commit

## Test
- Open Manuals → your big manual should show "index failed — tap to retry"
  (the stale job was cleaned up). Tap Index for AI once → wait 2-4 min → indexed.
- Tap Index for AI again on the now-indexed one → you get the warning
  dialog (that's the guard working).
- Ask 5 questions in Problem Solver → bill should not visibly move.
