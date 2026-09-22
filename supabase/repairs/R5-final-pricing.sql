-- ============================================================================
--  R5 — align subscription_plans with the FINAL published pricing
-- ============================================================================
--
--  Run this in the Supabase SQL Editor AFTER R1/R2/R4, with the row-limit
--  dropdown set to "No limit". Safe to run more than once.
--
--  WHY THIS EXISTS
--
--  Three places quote a price to a customer:
--    1. site/pricing.html          the page a buyer reads
--    2. PlantMaster-Pro-Subscription-Agreement.pdf   the contract they sign
--    3. subscription_plans         what the software actually enforces
--
--  (1) and (2) agree. (3) did not:
--
--    plan          site + PDF      database before R5
--    ------------  --------------  ---------------------------
--    Basic         Rs  7,500       MISSING ENTIRELY
--    Essential     Rs 12,000       Rs 12,000          ok
--    Professional  Rs 24,000       Rs 24,000          ok
--    Enterprise    Rs 40,000       Rs 0 ("Quoted")
--
--  Consequences of leaving it: nobody can be put on Basic at all, and an
--  Enterprise customer is billed against a plan whose price is 0.
--
--  Limits below are taken from the pricing page, so what a customer is sold
--  is exactly what the software enforces.
--
--    plan          users  plants  storage  files
--    ------------  -----  ------  -------  ------
--    Basic             5       1     5 GB   2,000
--    Essential        10       1    10 GB   5,000
--    Professional     25       1    30 GB  20,000
--    Enterprise      100       2   100 GB  50,000
--
--  These file limits are also what site/pricing.html advertises; R5's test
--  reads the page so the two can never drift apart again.
--
--  Trial is deliberately left untouched: 7 days of full Professional access,
--  which is what the page and the agreement both promise.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. Basic — absent until now, so it could never be sold.
-- ---------------------------------------------------------------------------
insert into public.subscription_plans
  (code, name, description, currency, price_monthly, price_yearly,
   max_workers, max_plants, max_storage_bytes, max_files, max_file_bytes,
   ai_requests_month, ai_requests_day, ai_requests_minute_user,
   ai_input_tokens_month, ai_output_tokens_month, retention_days, active)
values
  ('basic', 'Basic',
   '5 users, 1 plant, 5 GB. Core maintenance and operations. No AI features.',
   'PKR', 7500, 90000,
   5, 1, 5368709120, 2000, 52428800,
   -- No AI on this tier: the page lists the AI rows as excluded.
   0, 0, 0, 0, 0,
   365, true)
on conflict (code) do update set
  name           = excluded.name,
  description    = excluded.description,
  currency       = excluded.currency,
  price_monthly  = excluded.price_monthly,
  price_yearly   = excluded.price_yearly,
  max_workers    = excluded.max_workers,
  max_plants     = excluded.max_plants,
  max_storage_bytes = excluded.max_storage_bytes,
  max_files      = excluded.max_files,
  active         = true,
  updated_at     = now();

-- ---------------------------------------------------------------------------
-- 2. Enterprise — was priced at 0 because it used to be "quoted".
--    The published price is Rs 40,000/month.
-- ---------------------------------------------------------------------------
update public.subscription_plans set
  name          = 'Enterprise',
  description   = '100 users, 2 plants, 100 GB. All Professional features, plus company branding and custom limits.',
  currency      = 'PKR',
  price_monthly = 40000,
  price_yearly  = 400000,
  max_workers   = 100,
  max_plants    = 2,
  max_storage_bytes = 107374182400,
  max_files     = 50000,
  active        = true,
  updated_at    = now()
where code = 'enterprise';

-- ---------------------------------------------------------------------------
-- 3. Essential and Professional — prices already correct. Re-assert the
--    descriptions and limits so all four tiers read consistently.
-- ---------------------------------------------------------------------------
update public.subscription_plans set
  description   = '10 users, 1 plant, 10 GB. Adds AI Problem Solver, deep search, vision scanner, manual uploads.',
  price_monthly = 12000,
  price_yearly  = 120000,
  max_workers   = 10,
  max_plants    = 1,
  max_storage_bytes = 10737418240,
  max_files     = 5000,
  active        = true,
  updated_at    = now()
where code = 'essential';

update public.subscription_plans set
  description   = '25 users, 1 plant, 30 GB. Adds condition monitoring, predictive maintenance, daily report email.',
  price_monthly = 24000,
  price_yearly  = 240000,
  max_workers   = 25,
  max_plants    = 1,
  max_storage_bytes = 32212254720,
  max_files     = 20000,
  active        = true,
  updated_at    = now()
where code = 'professional';

-- ---------------------------------------------------------------------------
-- 4. Retire any legacy tier that is no longer sold.
--    Deactivated, never deleted: existing subscriptions keep their foreign key
--    and their billing history stays readable.
-- ---------------------------------------------------------------------------
update public.subscription_plans
   set active = false, updated_at = now()
 where code not in ('trial','basic','essential','professional','enterprise')
   and active;

commit;

-- ============================================================================
--  VERIFY — every row should read "ok"
-- ============================================================================
select
  code,
  name,
  price_monthly,
  max_workers,
  max_plants,
  round(max_storage_bytes / 1073741824.0)::int as storage_gb,
  active,
  case
    when code = 'basic'        and price_monthly =  7500 then 'ok'
    when code = 'essential'    and price_monthly = 12000 then 'ok'
    when code = 'professional' and price_monthly = 24000 then 'ok'
    when code = 'enterprise'   and price_monthly = 40000 then 'ok'
    when code = 'trial'        and price_monthly =     0 then 'ok'
    else 'CHECK THIS ROW'
  end as matches_published_price
from public.subscription_plans
order by price_monthly, code;
