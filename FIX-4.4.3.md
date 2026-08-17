# PlantMaster v4.4.3 Gemini endpoint compatibility
Replace only index.html, app.js and service-worker.js.

PlantMaster now tries `gemini-problem-solver` first and automatically falls back to the already deployed `smart-responder` endpoint. No SQL change is required.

In Supabase, the modified smart-responder code must still be deployed with **Deploy updates** after changing `gemini-2.5-flash` to `gemini-3.7-flash`.
