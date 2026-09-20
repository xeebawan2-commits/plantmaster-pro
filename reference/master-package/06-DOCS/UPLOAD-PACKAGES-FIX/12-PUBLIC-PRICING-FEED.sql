-- ===================================================================
-- 12-PUBLIC-PRICING-FEED.sql
-- 16 September 2026
--
-- OPTIONAL. Run this only if you want the website pricing page to
-- update ITSELF whenever you change a package in the control centre.
--
--
-- THE PROBLEM THIS SOLVES
--
-- Right now your prices live in two places: the control centre
-- (which is what customers are actually billed and limited by) and
-- hsbfix.org/pricing.html (which is hand-written HTML).
--
-- Change one and the other goes stale. A prospect reads Rs 12,000
-- on the website, signs up, and the system gives them something
-- different. That conversation is awkward and it costs trust.
--
--
-- WHAT THIS DOES
--
-- Creates ONE read-only function that returns only the harmless,
-- public marketing fields of your active plans - the same things
-- already printed on your pricing page today.
--
-- It deliberately does NOT expose internal controls: no AI rate
-- limits, no per-minute ceilings, no retention settings, no
-- internal notes, no company data. Those stay private.
--
-- The subscription_plans table itself stays locked. Nothing is
-- granted on the table - only on this one narrow function.
--
-- SAFE TO RUN. Creates one read-only function. Changes no data.
-- Safe to run more than once.
-- ===================================================================

create or replace function public.public_pricing_plans()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'code',            p.code,
        'name',            p.name,
        'description',     p.description,
        'price_monthly',   p.price_monthly,
        'price_yearly',    p.price_yearly,
        'max_workers',     p.max_workers,
        'max_plants',      p.max_plants,
        'storage_gb',      round((coalesce(p.max_storage_bytes,0) / 1073741824.0)::numeric, 0),
        'max_files',       p.max_files,
        'features',        coalesce(p.features, '{}'::jsonb)
      )
      order by p.price_monthly nulls last, p.name
    ),
    '[]'::jsonb
  )
  from public.subscription_plans p
  where p.active
    -- never expose an internal or hidden plan on the public website
    and coalesce((p.features->>'internal')::boolean, false) = false
    and p.code not ilike '%internal%'
    and p.code not ilike '%test%'
    and p.code not ilike '%demo%';
$$;

-- The website is not logged in, so the anonymous role needs this one
-- function. It returns marketing copy only.
grant execute on function public.public_pricing_plans() to anon, authenticated;


-- ===================================================================
-- CHECK IT WORKS
--
-- Run this in the SQL editor - it should list your live packages:
--
--     select public.public_pricing_plans();
--
-- Or from any browser, which proves the website can read it:
--
--     https://dpmmenwziplixrgylapy.supabase.co/rest/v1/rpc/
--       public_pricing_plans?apikey=YOUR_PUBLISHABLE_KEY
--
--
-- IF YOU WANT TO HIDE A PLAN FROM THE WEBSITE
--
-- Either set it inactive in the control centre, or name its code
-- with "internal", "test" or "demo" in it, or add "internal": true
-- to its feature list. Any of those keeps it working for existing
-- customers while keeping it off the public page.
-- ===================================================================
