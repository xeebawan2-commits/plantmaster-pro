# PlantMaster v4.5.1 Report and Mobile Action Fix

Replace only these files in the GitHub repository root:

- index.html
- app.js
- operations.js
- ui-v4.5.css
- service-worker.js

No SQL rerun is required.

## Fixed

- Declared the missing report state that caused the permanent `Loading reports…` screen.
- Reports render immediately instead of waiting for counts from every module.
- Only the selected report module is queried.
- Added a 15-second timeout and visible Retry state.
- CSV, Excel, Word and PDF each have separate View and Download actions.
- CSV can be viewed directly inside PlantMaster.
- Excel, Word and PDF open a formatted view.
- PDF Download opens the print dialog for Save as PDF.
- Mobile Logout is visible in the header again.
- Online status is a compact green status dot with an accessible status tooltip.
- Add Worker now includes `After adding, send invitation by`: Save only, Email or WhatsApp.
- Pending workers continue to show Email, WhatsApp, Copy/Share and Cancel buttons.
- WhatsApp opens the prepared secure invitation through wa.me.
- Service worker cache updated to v4.5.1.
