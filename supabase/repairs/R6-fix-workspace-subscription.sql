-- ============================================================================
-- R6 — Fix: "duplicate key value violates unique constraint
--            organization_subscriptions_organization_id_key"
--            when a client creates their company workspace.
--
-- WHAT WAS WRONG
--   Creating a company runs TWO things that both insert the trial subscription:
--     1. the AFTER INSERT trigger on `organizations`
--        (organization_commercial_defaults -> create_default_commercial_records)
--        inserts ONE subscription row, keyed by organization_id,
--        with `on conflict (organization_id) do nothing`;
--     2. `create_organization()` then ALSO inserts a subscription row for the
--        same organization, but WITHOUT an on-conflict clause.
--   The trigger (1) runs first (it fires the moment the org row is inserted),
--   so (2) collides with the row that already exists -> the duplicate-key error
--   the client saw. The whole function is one transaction, so it rolls back and
--   the workspace is never created.
--
-- THE FIX
--   Make create_organization()'s subscription insert idempotent: turn it into an
--   UPSERT (`on conflict (organization_id) do update`). Now it coexists with the
--   trigger — whichever inserted the row first, create_organization ends with the
--   subscription in the exact trial/plan state it intends. Nothing else changes:
--   the "approved by HSB Fix Services" invitation gate and all other behaviour
--   are preserved verbatim from R2.
--
-- SAFE TO RUN
--   Idempotent. Only replaces one function. Does not touch data, the trigger,
--   RLS, or any other object. Re-runnable. Run this in the Supabase SQL editor.
-- ============================================================================

begin;

create or replace function public.create_organization(org_name text, plant_name text)
returns table(organization_id uuid, plant_id uuid)
language plpgsql security definer set search_path to 'public'
as $function$
declare
  o uuid; p uuid;
  caller_email text;
  inv  public.owner_invitations%rowtype;
  plan public.subscription_plans%rowtype;
  trial_end timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select lower(email) into caller_email from auth.users where id = auth.uid();

  select * into inv
    from public.owner_invitations
   where lower(email) = caller_email
     and used_at is null and revoked_at is null and expires_at > now()
   order by created_at desc
   limit 1;

  if inv.id is null then
    raise exception
      'Accounts are approved by HSB Fix Services. Please request access at https://hsbfix.org or contact support@hsbfix.org.'
      using errcode = 'check_violation';
  end if;

  select * into plan from public.subscription_plans where code = inv.plan_code;
  if plan.id is null then
    raise exception 'Configured plan % does not exist', inv.plan_code;
  end if;

  insert into public.organizations (name, slug, created_by, commercial_status)
  values (
    coalesce(nullif(inv.company_name,''), org_name),
    lower(regexp_replace(coalesce(nullif(inv.company_name,''), org_name),
                         '[^a-zA-Z0-9]+','-','g'))
      || '-' || substr(gen_random_uuid()::text,1,6),
    auth.uid(),
    case when inv.trial_days > 0 then 'trial' else 'active' end
  )
  returning id into o;

  insert into public.organization_members (organization_id, user_id, role, active, created_at)
  values (o, auth.uid(), 'owner', true, now());

  trial_end := case when inv.trial_days > 0
                    then now() + make_interval(days => inv.trial_days) end;

  -- Idempotent: the organization_commercial_defaults trigger already inserted a
  -- trial subscription for this org, so UPSERT to the intended plan/trial state
  -- instead of a plain insert (which used to raise the duplicate-key error).
  insert into public.organization_subscriptions
    (organization_id, plan_id, status,
     current_period_start, current_period_end, trial_ends_at)
  values
    (o, plan.id,
     case when inv.trial_days > 0 then 'trial' else 'active' end,
     now(), coalesce(trial_end, now() + interval '30 days'), trial_end)
  on conflict on constraint organization_subscriptions_organization_id_key do update set
    plan_id              = excluded.plan_id,
    status               = excluded.status,
    current_period_start = excluded.current_period_start,
    current_period_end   = excluded.current_period_end,
    trial_ends_at        = excluded.trial_ends_at,
    updated_at           = now();

  insert into public.plants (organization_id, name)
  values (o, coalesce(nullif(inv.plant_name,''), plant_name))
  returning id into p;

  insert into public.plant_members (plant_id, user_id, created_at)
  values (p, auth.uid(), now());

  update public.owner_invitations
     set used_at = now(), used_by = auth.uid(), created_org_id = o
   where id = inv.id;

  if inv.signup_request_id is not null then
    update public.signup_requests
       set status = 'approved', reviewed_at = now()
     where id = inv.signup_request_id;
  end if;

  return query select o, p;
end
$function$;

grant execute on function public.create_organization(text,text) to authenticated;

commit;

-- ============================================================================
-- VERIFY (optional) — expect 'yes — idempotent'
-- ============================================================================
-- select case
--   when position('on conflict' in lower(pg_get_functiondef(p.oid))) > 0
--     then 'yes — idempotent' else 'NO — still broken' end as create_org_upsert
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'public' and p.proname = 'create_organization';
