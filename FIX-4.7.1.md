# PlantMaster v4.7.1 — Gemini Commercial Function and Performance Fix

## Cause addressed

The commercial Edge Function read only the legacy `SUPABASE_SERVICE_ROLE_KEY`. New Supabase projects may provide server secrets through `SUPABASE_SECRET_KEYS`. The function now supports both secret formats without exposing either value.

## Runtime improvements

- Calls the deployed `smart-responder` directly instead of first waiting for a missing endpoint to return 404.
- Fast Gemini mode no longer performs four manual-source database searches before invoking Gemini.
- Gemini + Manual and Manual modes still retrieve plant sources.
- Displays the actual Edge Function error returned by the backend instead of only `non-2xx status`.
- Debounces dashboard global search.
- Reduces always-on realtime table listeners.
- Corrects duplicate mobile Online dots.
- Adds reduced-motion support.

## Deployment

Replace the five GitHub files in this package, then replace/deploy `edge-functions/smart-responder/index.ts` in Supabase. No SQL rerun is required.
