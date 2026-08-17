# PlantMaster v4.5.2 Smooth Scrolling Fix

Replace only:

- index.html
- app.js
- ui-v4.5.css
- service-worker.js

No SQL change is required.

Changes:

- Removed expensive fixed-background repainting on mobile.
- Disabled mobile backdrop blur during scrolling.
- Reduced large mobile card shadows and touch-hover transforms.
- Added pan-y touch handling and momentum scrolling to overflow areas.
- Added overscroll containment for tables, tabs, drawer and conversations.
- Promoted fixed header/bottom navigation to stable compositor layers.
- Added reduced-motion support.
- Realtime changes are deferred while the user is actively scrolling, preventing module rerenders under the finger.
- Realtime refresh resumes immediately after scrolling stops.
- Service-worker cache updated to v4.5.2.
