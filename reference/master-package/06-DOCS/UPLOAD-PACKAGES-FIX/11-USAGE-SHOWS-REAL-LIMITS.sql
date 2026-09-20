-- ===================================================================
-- 11-USAGE-SHOWS-REAL-LIMITS.sql
-- 16 September 2026
--
-- WHAT THIS FIXES
--
-- The "Plan & Usage" screen in the customer app showed the PLAN's
-- base limits, ignoring any per-company override you set in the
-- control centre.
--
-- So if you gave one company extra storage or extra workers, the
-- database correctly ALLOWED the extra (the enforcement triggers
-- already call effective_company_limit), but the customer's screen
-- still displayed the old plan number. The customer saw "18 / 10
-- workers" and thought the app was broken.
--
-- It also showed the plan's raw feature list, ignoring per-company
-- feature grants and blocks, so a module you switched on for one
-- company did not appear in their list.
--
-- This rewrites organization_plan_summary so that every limit and
-- every feature shown is the EFFECTIVE value - plan base, plus
-- overrides, minus blocks. Exactly what is enforced.
--
-- It also makes the subscription join safe. Previously an inner
-- join meant a company with no subscription row returned nothing
-- at all and the screen showed an error. Now it returns the usage
-- with a null plan, so the screen still renders.
--
-- SAFE TO RUN. Read-only reporting function, no data is changed.
-- Safe to run more than once.
-- ===================================================================

create or replace function public.organization_plan_summary(p_organization_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  result      jsonb;
  plan_json   jsonb;
  feat        jsonb;
  month_start date := date_trunc('month', current_date)::date;
begin
  if not public.is_org_member(p_organization_id)
     and not public.is_platform_admin() then
    raise exception 'Access denied';
  end if;

  -- Effective feature map: plan defaults, then per-company blocks
  -- and grants applied on top.
  select coalesce(
           jsonb_object_agg(
             key,
             public.company_feature_allowed(p_organization_id, key, (value)::boolean)
           ),
           '{}'::jsonb
         )
    into feat
  from public.organization_subscriptions s
  join public.subscription_plans pl on pl.id = s.plan_id
  cross join lateral jsonb_each_text(coalesce(pl.features, '{}'::jsonb))
  where s.organization_id = p_organization_id
  limit 1000;

  -- Add any feature granted to this company that the plan does not
  -- list at all, so extras bought separately still appear.
  begin
    select coalesce(feat, '{}'::jsonb)
           || coalesce(
                (select jsonb_object_agg(cfg.feature, true)
                   from public.company_feature_grants cfg
                  where cfg.organization_id = p_organization_id
                    and cfg.granted
                    and (cfg.expires_at is null or cfg.expires_at > now())),
                '{}'::jsonb)
      into feat;
  exception when undefined_table then
    null;  -- grants table not present on this install; ignore
  end;

  -- Plan, with every numeric limit replaced by its effective value.
  select to_jsonb(pl)
         || jsonb_build_object(
              'max_workers',
                public.effective_company_limit(p_organization_id,'workers',           coalesce(pl.max_workers,0)),
              'max_plants',
                public.effective_company_limit(p_organization_id,'plants',            coalesce(pl.max_plants,0)),
              'max_storage_bytes',
                public.effective_company_limit(p_organization_id,'storage_bytes',     coalesce(pl.max_storage_bytes,0)),
              'max_bandwidth_bytes_month',
                public.effective_company_limit(p_organization_id,'bandwidth_bytes',   coalesce(pl.max_bandwidth_bytes_month,0)),
              'max_files',
                public.effective_company_limit(p_organization_id,'files',             coalesce(pl.max_files,0)),
              'max_file_bytes',
                public.effective_company_limit(p_organization_id,'file_bytes',        coalesce(pl.max_file_bytes,0)),
              'ai_requests_month',
                public.effective_company_limit(p_organization_id,'ai_requests_month', coalesce(pl.ai_requests_month,0)),
              'ai_input_tokens_month',
                public.effective_company_limit(p_organization_id,'ai_input_tokens_month', coalesce(pl.ai_input_tokens_month,0)),
              'features', coalesce(feat, '{}'::jsonb)
            )
    into plan_json
  from public.organization_subscriptions s
  join public.subscription_plans pl on pl.id = s.plan_id
  where s.organization_id = p_organization_id
  limit 1;

  select jsonb_build_object(
    'organization_status',  o.commercial_status,
    'status_reason',        o.status_reason,
    'trial_ends_at',        o.trial_ends_at,
    'subscription_status',  s.status,
    'period_start',         s.current_period_start,
    'period_end',           s.current_period_end,
    'plan',                 coalesce(plan_json, 'null'::jsonb),
    'workers', (select count(*) from public.organization_members m
                 where m.organization_id = o.id and m.active),
    'plants',  (select count(*) from public.plants pl2
                 where pl2.organization_id = o.id),
    'files',   (select count(*) from public.file_metadata f
                 where f.organization_id = o.id and f.removed_at is null),
    'storage_bytes', (select coalesce(sum(f.size_bytes),0) from public.file_metadata f
                       where f.organization_id = o.id and f.removed_at is null),
    'bandwidth_bytes_month', coalesce((select u.quantity from public.usage_counters u
        where u.organization_id=o.id and u.metric='bandwidth_bytes'  and u.period_start=month_start),0),
    'ai_requests_month',     coalesce((select u.quantity from public.usage_counters u
        where u.organization_id=o.id and u.metric='ai_requests'      and u.period_start=month_start),0),
    'ai_input_tokens_month', coalesce((select u.quantity from public.usage_counters u
        where u.organization_id=o.id and u.metric='ai_input_tokens'  and u.period_start=month_start),0),
    'ai_output_tokens_month',coalesce((select u.quantity from public.usage_counters u
        where u.organization_id=o.id and u.metric='ai_output_tokens' and u.period_start=month_start),0)
  ) into result
  -- LEFT joins: a company with no subscription still gets its usage
  -- back instead of an error screen.
  from public.organizations o
  left join public.organization_subscriptions s on s.organization_id = o.id
  where o.id = p_organization_id;

  return result;
end $$;

grant execute on function public.organization_plan_summary(uuid) to authenticated;


-- ===================================================================
-- HOW TO CHECK IT WORKED
--
-- 1. In the control centre, give one company a storage bonus.
-- 2. Sign in to the customer app as that company.
-- 3. Open the menu, then "Plan".
-- 4. The storage bar should now show the RAISED limit, not the
--    plan's base figure.
--
-- Before this fix the bar showed the plan number and the customer
-- had no way to see the extra you had granted them.
-- ===================================================================
