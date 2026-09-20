THE SEPTEMBER 2026 REPAIRS
Run these AFTER all 32 scripts in 01-schema-build-order.

RUN THESE, in this order:

  02-FIX-v2.sql            Grants the super admin all 16
                           permissions and repairs
                           control_admins(), which was
                           failing with "structure of query
                           does not match function result".

  03-cleanup-and-check.sql Fixes the default status on
                           signup_requests so new enquiries
                           arrive as pending.

  07-FULL-CONTROL.sql      THE IMPORTANT ONE. Made deleting
                           work. Nothing could be deleted
                           because other tables pointed at
                           the rows with foreign keys set to
                           block it. This walks every one of
                           those links in a single loop.

  09-CLEAN-QA-v2.sql       Removes leftover QA test accounts.
                           Only needed if you have some.

  10-COMPANY-FEATURES.sql  Adds per-company feature grants,
                           so one customer can be given a
                           module their package does not
                           include. Also removes an old limit
                           that silently blocked most feature
                           names, and adds
                           organization_effective_features().


DO NOT RUN THESE — history only:

  04-FIX-DELETES.sql       Made things worse. It tried to
                           blank the organisation link on the
                           audit log, but that table is
                           append-only and a trigger
                           correctly refused.

  05-FIX-OWNER-DELETE.sql  Reported success but missed the
                           real problem. It read the foreign
                           key list from information_schema,
                           which only shows links pointing at
                           tables you own — and Supabase owns
                           auth.users, so the links that
                           mattered were invisible.

  Both are superseded by 07-FULL-CONTROL.sql.


IF A DELETE EVER FAILS AGAIN

  Look for error 23503, "violates foreign key constraint".
  The message names the constraint blocking you. Use
  pg_constraint to find the links, NOT information_schema.
  07-FULL-CONTROL.sql is the pattern to copy.
