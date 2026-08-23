# PlantMaster v4.9.6 — Unified Scanner Automatic Completion

## Corrected behavior

- QR/Barcode image with a code: detects, searches PlantMaster and opens a visible completion page.
- QR/Barcode image without a code: automatically switches to Document OCR instead of staying on the image.
- Document Camera/Gallery: automatically performs OCR after page capture/selection.
- Multi-page gallery: sends up to six compressed pages in one secured Vision request and requests page-wise OCR.
- Nameplate Camera/Gallery: automatically analyzes and displays extracted specifications.
- Identify Camera/Gallery: automatically identifies and displays evidence, safety and actions.
- Import image: checks QR/barcode first, then automatically runs image analysis when no code is present.
- Non-image import: displays a completed Ready to Save result rather than remaining on the file preview.
- Every success or error replaces the scanner workspace with a visible completion/result page containing Back and New Scan.
- Back preserves the current captured pages/image; New Scan clears the scanner state.

## Deployment

Replace `index.html`, `app.js`, `scanner.js`, `scanner-v4.8.css`, and `service-worker.js`. Replace/redeploy `edge-functions/vision-scanner/index.ts` to enable multi-page input. Keep legacy JWT verification OFF for `vision-scanner`; the function validates JWT and membership internally. No SQL migration is required.
