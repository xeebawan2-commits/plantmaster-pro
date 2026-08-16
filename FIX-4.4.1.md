# PlantMaster Pro v4.4.1 — Navigation and UI Regression Fix

Replace only these five files in the existing GitHub repository root:

- `index.html`
- `app.js`
- `operations.js`
- `styles.css`
- `service-worker.js`

No SQL migration is required for this fix if `schema-phase5-operations.sql` was already run.

## Corrected

- Visiting People no longer destroys the shared Assets/Work/Files toolbar.
- Assets and Work Orders open again after visiting People.
- `+ Add` is restored in Assets and Work Orders; Upload is restored in Files.
- Dashboard KPI tiles and module cards are explicit navigation buttons.
- Added Running and unread Alerts dashboard KPIs.
- Restored Alarms & Notifications on dashboard and mobile bottom navigation.
- Notifications can be marked read individually or together.
- Restored visible `Online/Offline` text and mobile Logout.
- Added a second Logout control inside the drawer.
- Removed the Back-history trap. Physical/browser Back now follows normal route history and can leave from Home.
- Reports now have module selection, date filters, preview, CSV, Excel, Word, and PDF/Print actions.
- People, Roster, Attendance, Handovers and Daily Logs now show CSV, Excel, Word and PDF actions.
- Fixed the detached/floating voice button in the mobile module toolbar.
- Updated service-worker cache key and runtime URLs to v4.4.1.

## Cache refresh

After uploading all five files, close every open PlantMaster tab and reopen the HTTPS URL. If the old version remains, refresh once after the page opens so the new service worker activates.
