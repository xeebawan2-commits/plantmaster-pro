# PlantMaster Pro v4.11.0 — Unified English/Urdu Deep Problem Solver

## Requested interface

Problem Solver now has one combined search, not separate Manual/Gemini/Google mode buttons.

Input methods:

- Type Search
- Voice Search

Languages:

- Auto Detect
- English
- Urdu (`ur-PK` voice recognition, Urdu script input/output)

Every search combines:

- PlantMaster manual files and extracted pages
- Approved technical experiences
- Verified plant problem cases
- Gemini technical reasoning
- Google Search grounding

Results include written answer, Read Aloud, safety, confidence, causes, checks, tools, parts, sources, plant-source count, copy and Save Case. Urdu answers may include an expandable English translation.

## Deployment

Replace `index.html`, `app.js`, `solver.js`, `solver-v4.11.css`, and `service-worker.js` in the customer PlantMaster repository. Replace/redeploy `edge-functions/smart-responder/index.ts` over the existing `smart-responder` function. The Edge Function performs custom JWT and membership validation; use the same gateway JWT setting that currently works for the secured function (legacy verification may remain OFF on newer Supabase key projects).

No SQL migration is required.

## Notes

Read Aloud uses the phone/browser speech-synthesis engine. Written Urdu remains available even if that Android device does not have an Urdu speech voice installed. Install/enable an Urdu voice in the device Text-to-Speech settings for best pronunciation.
