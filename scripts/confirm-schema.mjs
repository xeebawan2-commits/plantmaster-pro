#!/usr/bin/env node
/**
 * Refuses db:push / functions:deploy until the migrations have been adapted
 * to the live schema.
 *
 * The live project has 87 tables and 14 edge functions; these migrations were
 * reconstructed from application code and describe 55 and 8. Applying them
 * as-is creates duplicate tables (ai_usage_events vs the live ai_usage) and
 * re-grants privileges on 32 tables they know nothing about.
 *
 * Set PM_SCHEMA_ADAPTED=1 once the migrations match the live database.
 */
const RED='\x1b[31m', YEL='\x1b[33m', GRN='\x1b[32m', DIM='\x1b[2m', RST='\x1b[0m';
if (process.env.PM_SCHEMA_ADAPTED === '1') process.exit(0);

console.error(`
${RED}BLOCKED — this command is unsafe against the live database.${RST}

${YEL}Live project:${RST}  87 tables, 14 edge functions
${YEL}These files:${RST}   55 tables,  8 edge functions (reconstructed from app code)

Applying them would:
  • create 5 duplicate tables, splitting your data
      ${DIM}ai_usage_events   vs live ai_usage (25 rows)
      app_complaints    vs live platform_support_tickets
      organization_features vs live organization_entitlements
      daily_report_runs vs live report_dispatches${RST}
  • re-grant privileges on 32 tables these migrations do not model
  • overwrite 7 working edge functions with schema-mismatched versions

${GRN}Safe right now:${RST}  npm run deploy      ${DIM}(the PWA — all the real fixes)${RST}

Read ${YEL}STOP-READ-FIRST.md${RST} for the three options.

Once the migrations genuinely match the live schema:
  ${DIM}PM_SCHEMA_ADAPTED=1 npm run db:push${RST}
`);
process.exit(1);
