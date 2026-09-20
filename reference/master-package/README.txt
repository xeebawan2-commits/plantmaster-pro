===============================================================

   P L A N T M A S T E R   P R O
   Complete project — start to finish

   HSB Fix Services
   Built 16 September 2026

===============================================================

  This is the ONE folder you need. If everything else were
  lost tomorrow — every site, every file, every zip — you
  could rebuild the whole business from what is in here.

  It is assembled from two sources:
    - the live sites, downloaded and verified today
    - your "completed project" archive, which contained the
      original database scripts and the edge function source
      code that could not be downloaded from the internet

  Everything is in the order you would do it in.


===============================================================
  THE FOLDERS
===============================================================

  01-WEBSITE          hsbfix.org — the public marketing site
  02-CUSTOMER-APP     app.hsbfix.org — what your customers use
  03-ADMIN-PANEL      admin.hsbfix.org — your control centre
  04-EDGE-FUNCTIONS   the server functions (source code)
  05-DATABASE         every SQL script, in run order
  06-DOCS             guides, old and new
  07-OLD-RELEASES     18 historical zips, for reference only


===============================================================
  IF YOU HAD TO START COMPLETELY FROM SCRATCH
===============================================================

  Roughly half a day. Follow these in order — do not skip
  ahead, each step depends on the one before it.


  ---------------------------------------------------------
  STEP 1 — CREATE THE SUPABASE PROJECT
  ---------------------------------------------------------

  supabase.com > New project.
  Note down the project URL and the publishable (anon) key.

  Then Storage > New bucket, named exactly:

      plant-files

  Set it to PRIVATE. The app creates signed links for every
  download; a public bucket would expose customer manuals.


  ---------------------------------------------------------
  STEP 2 — BUILD THE DATABASE
  ---------------------------------------------------------

  Folder: 05-DATABASE/01-schema-build-order/

  32 files, numbered 01 to 32. Open Supabase > SQL Editor,
  and run them ONE AT A TIME, in number order.

  Before running, set the dropdown next to the Run button to
  "No limit", or long scripts get truncated.

  The order matters enormously. 01 creates the foundation
  tables; everything after builds on it. Running 13 before
  07 will fail with confusing errors.

    01-10   the core system: companies, plants, assets,
            work orders, manuals, operations, commercial
            plans, platform administration, scanner,
            condition monitoring
    11-12   procurement and plant security rules
    13-24   the Control Center, QA lab, permission repairs,
            AI metering, accounts
    25-28   expanded roles, manual access, push notifications
    29      the public API keys table
    30-32   the gatekeeper (stops strangers signing up),
            signup email, and delete fixes

  Then run everything in:

      05-DATABASE/02-repairs-and-features/

  in number order (02, 03, 07, 09, 10). These are the fixes
  made during the September rebuild. The important ones:

      07-FULL-CONTROL.sql     made deletion work properly
      10-COMPANY-FEATURES.sql per-company feature grants

  DO NOT run 04 or 05 — they are kept as history only and
  are superseded by 07. There is a README in that folder
  explaining why.


  ---------------------------------------------------------
  STEP 3 — DEPLOY THE EDGE FUNCTIONS
  ---------------------------------------------------------

  Folder: 04-EDGE-FUNCTIONS/

  12 folders, each containing an index.ts. These run the AI,
  the emails, the push notifications and the file handling.
  A 13th function, create-owner, is live on your project but
  its source was never found — see the note at the end of
  this step.

  On a computer with Node installed:

      npx supabase login
      npx supabase link --project-ref YOUR-PROJECT-REF

  Copy the folders into supabase/functions/ in a working
  directory, then for each one:

      npx supabase functions deploy condition-analyzer
      npx supabase functions deploy daily-reports
      npx supabase functions deploy delete-manual
      npx supabase functions deploy health-monitor
      npx supabase functions deploy ingest-manual
      npx supabase functions deploy platform-admin-api
      npx supabase functions deploy public-api
      npx supabase functions deploy signup-notify
      npx supabase functions deploy smart-responder
      npx supabase functions deploy vision-scanner
      npx supabase functions deploy voice-translate
      npx supabase functions deploy web-push

  THEN SET THE SECRETS. The functions read their keys from
  the environment — no key is written in the code, which is
  correct. In Supabase: Edge Functions > Secrets.

      SUPABASE_URL                  your project URL
      SUPABASE_SERVICE_ROLE_KEY     from Settings > API
      GEMINI_API_KEY                for all the AI features
      RESEND_API_KEY                for sending email
      SIGNUP_FROM                   e.g. no-reply@hsbfix.org
      SIGNUP_ALERT_TO               where enquiries go
      DAILY_REPORTS_FROM            sender for daily reports
      DAILY_REPORTS_TOKEN           any long random string
      VAPID_PUBLIC_KEY              for push notifications
      VAPID_PRIVATE_KEY             for push notifications
      VAPID_SUBJECT                 mailto:you@hsbfix.org
      PUSH_INTERNAL_TOKEN           any long random string
      HEALTH_MONITOR_TOKEN          any long random string

  ONE FUNCTION IS MISSING: create-owner. Its source was not
  in any archive. It is deployed and working on your live
  project, so you are fine today, but if you rebuilt from
  zero you would have to write it again. It is small — it
  takes { email, invitation_id }, creates the auth user,
  and returns { email, password, app_url }. Download it
  while you still can:

      npx supabase functions download create-owner

  Do this. It is the last gap in the whole backup.


  ---------------------------------------------------------
  STEP 4 — PUT THE THREE SITES ONLINE
  ---------------------------------------------------------

  All three are plain files. No build step, no server, and
  no hosting cost — GitHub Pages serves them free.

  For each one: create a GitHub repository, upload the
  folder's contents, then Settings > Pages > deploy from
  main branch.

      01-WEBSITE       ->  hsbfix.org
      02-CUSTOMER-APP  ->  app.hsbfix.org
      03-ADMIN-PANEL   ->  admin.hsbfix.org

  Point each domain at its repo (the CNAME file in
  01-WEBSITE shows how yours is set up).

  Then edit config.js in BOTH 02-CUSTOMER-APP and
  03-ADMIN-PANEL to hold your project URL and publishable
  key. Nothing else needs changing.


  ---------------------------------------------------------
  STEP 5 — SETTINGS THAT ARE EASY TO FORGET
  ---------------------------------------------------------

  These are not in any file. Miss them and things fail in
  ways that are hard to diagnose.

  a) STOP STRANGERS SIGNING UP
     Authentication > Sign In / Providers > Email
        Email provider                 ON   (leave it on)
        Allow new users to sign up     OFF  (turn this off)
     Getting these the wrong way round locks everyone out,
     including you.

  b) WHERE LOGIN LINKS GO
     Authentication > URL Configuration
        Site URL:  https://app.hsbfix.org
        Redirect URLs — add all six:
            https://app.hsbfix.org
            https://app.hsbfix.org/**
            https://app.hsbfix.org/index.html
            https://admin.hsbfix.org
            https://admin.hsbfix.org/**
            https://admin.hsbfix.org/index.html
     Without the /** entries, every password reset link is
     rejected and lands on the wrong site.

  c) EMAIL DELIVERY
     Authentication > Emails > turn on Custom SMTP.
        Host      smtp.resend.com
        Port      465
        Username  resend
        Password  your Resend API key (starts re_)
        Sender    no-reply@hsbfix.org
     Then Authentication > Rate Limits, raise email from
     the default 30/hour to 100.
     The built-in mailer only delivers to your own address
     and stops after 2 emails an hour, with no error — so
     this step is not optional on a real project.
     Done on the live project, 16 September 2026.

  d) MAKE YOURSELF THE ADMIN
     Run 02-FIX-v2.sql from 02-repairs-and-features with
     your own user id, so you appear in platform_admins
     with all 16 permissions.


===============================================================
  WHAT IS IN EACH FOLDER, IN DETAIL
===============================================================

  01-WEBSITE
  ----------
  6 pages, one stylesheet, 6 photographs, and the CNAME file
  that binds the domain. The signup form writes into the
  signup_requests table and calls signup-notify to send the
  acknowledgement.

  02-CUSTOMER-APP
  ---------------
  index.html, app.js, config.js, 6 stylesheets, the service
  worker, the manifest, 3 app icons, and 12 feature modules
  (analytics, condition monitoring, operations, procurement,
  scanner, AI solver, CSV import, offline queue, smart
  select, voice input, push client, job titles).

  IMPORTANT when updating: if you change app.js or
  styles.css you MUST also upload index.html and
  service-worker.js. They carry the version numbers that
  force phones to fetch the new files. Skip them and your
  customers keep running the old version from their phone's
  cache — this cost us an evening.

  03-ADMIN-PANEL
  --------------
  Four files. The whole Control Center: companies, accounts,
  approvals, invitations, packages, files, complaints,
  backups, activity log.

  04-EDGE-FUNCTIONS
  -----------------
  condition-analyzer   machine health from vibration and
                       temperature readings
  daily-reports        the scheduled daily email
  delete-manual        removes a manual and its indexed text
  health-monitor       system health checks
  ingest-manual        splits an uploaded manual into
                       passages so the AI can quote it
  platform-admin-api   file links and deletion for the
                       control centre
  public-api           the customer-facing REST API
  signup-notify        acknowledgement email for enquiries
  smart-responder      the AI maintenance assistant
  vision-scanner       reads nameplates and gauges from a
                       photograph
  voice-translate      speech to text, with translation
  web-push             sends push notifications to phones

  All 13 are confirmed live on your project today. Twelve
  have their source here; create-owner does not.

  05-DATABASE
  -----------
  01-schema-build-order/     32 scripts, numbered, run in
                             order on a fresh project
  02-repairs-and-features/   the September fixes
  03-live-schema-snapshot/   a dump of the live database as
                             it stands: every table and
                             column, every function's
                             source, every security policy,
                             every trigger, index and
                             constraint. Use this to check
                             a rebuild matches the original.
  RPC-INVENTORY.txt          every database function, its
                             arguments, and the 16
                             permission keys

  06-DOCS
  -------
  Current guides:
    LOGIN-EMAILS.txt          password reset and the SMTP
                              setup you still need to do
    HOW-TO-SELL-BRANDING.txt  selling the company profile as
                              a paid feature
    STEPS-THIS-ROUND.txt      per-company module grants
    FIX-NOTES.txt             bugs found and their causes
    UPLOAD-STEPS.txt          the upload routine

  original-build-notes/ — from the first build. Worth
  reading: 00-DO-THIS-FIRST.md explains which limits the
  database already enforces (worker counts, plant counts,
  storage, suspension) and WORKFLOW.md explains the
  difference between a purchase request and a purchase
  order, which confused everyone.

  07-OLD-RELEASES
  ---------------
  18 zips from earlier versions. You do not need these. They
  are kept only so you can look back at how something used
  to work. Everything current is in folders 01 to 06.


===============================================================
  WHAT IS STILL NOT HERE
===============================================================

  1. YOUR DATA — companies, users, work orders, complaints.
     Supabase keeps daily backups. You can also export it
     yourself: Control centre > More > Backup & download,
     in Excel, CSV, Word or PDF.

  2. UPLOADED FILES — customer manuals and photographs live
     in the plant-files storage bucket, not in these folders.

  3. create-owner's source code. See Step 3.

  4. YOUR SECRET KEYS — deliberately. They belong in
     Supabase's secrets, never in a backup folder. The list
     of which ones you need is in Step 3.


===============================================================
  STATE OF THE PROJECT
===============================================================

  Everything is working. Website, customer app, control
  centre, database, all 13 edge functions, and email.

  Custom SMTP was connected on 16 September 2026 and is
  confirmed working — that was the last blocker, and it is
  gone. Password resets and signup acknowledgements now
  reach real customers, not just your own address.

  Verified on the live project today:
    - all 13 edge functions responding
    - signups closed to strangers (disable_signup = true)
      with the email provider still on, which is the
      correct combination for invite-only accounts
    - all 8 front-end files matching these folders

  ONE LOOSE END, and it is small: the source code for the
  create-owner function was never found. The function is
  live and working, so nothing is broken today. But it is
  the only piece of this system you could not rebuild from
  this folder. Run this when you have five minutes:

      npx supabase functions download create-owner

  and drop the result into 04-EDGE-FUNCTIONS/create-owner/.
  Then this backup is genuinely complete.


===============================================================
  YOUR SETTINGS
===============================================================

  Supabase project : dpmmenwziplixrgylapy
  Storage bucket   : plant-files
  Website          : https://hsbfix.org
  Customer app     : https://app.hsbfix.org
  Control centre   : https://admin.hsbfix.org
  Super admin      : xeebawan2@gmail.com
  WhatsApp         : +92 316 2364074

  Database backups:
  supabase.com/dashboard/project/dpmmenwziplixrgylapy/database/backups/scheduled

  Running cost: the Supabase plan you already pay for.
  Hosting is free.
