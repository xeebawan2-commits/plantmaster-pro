# PlantMaster Pro v4 — Multi-User Phase 1

This is the production architecture foundation, not a wrapper around the standalone JSON-row prototype.

## Included

- Supabase email/password authentication
- Multi-tenant organizations and plants
- Roles and Row Level Security
- Owner workspace onboarding
- Multi-user asset register
- Multi-user work orders
- Supabase Storage file uploads (50 MB per file)
- Realtime asset/work-order refresh
- IndexedDB offline mutation queue
- Responsive PWA shell
- Audit-ready schema foundation

## Setup

1. Create a separate staging Supabase project (recommended).
2. Run `supabase/schema.sql` in SQL Editor.
3. Confirm email authentication settings.
4. Update `js/config.js` if using another project.
5. Upload all files to a staging GitHub Pages repository.
6. Create test accounts and an organization/plant.
7. Test on mobile/desktop before production migration.

## Current scope

Phase 1 intentionally focuses on the backend and concurrency foundation. The remaining standalone modules—custom checklists, maintenance, roster/attendance, inventory, QR/media, support, Problem Solver, Gemini, subscriptions and Android packaging—should be migrated onto these tables in subsequent phases.

Do not put a service-role key or Gemini key in frontend files.