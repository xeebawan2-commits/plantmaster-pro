-- ============================================================
--  PlantMaster Control Center — cleanup + the real answer
--  HSB Fix Services
--
--  Paste all -> Run.  Nothing here can fail.
-- ============================================================


-- ---- 1. Remove my test row ---------------------------------
--  While probing I inserted one row to check whether your
--  website could still file enquiries. It could (good). This
--  deletes it. Sorry for the noise.

delete from signup_requests where company_name = '__probe__';


-- ---- 2. Confirm your 16 permissions saved ------------------
--  The earlier run reported no error, so this should show 16.

select
  u.email,
  pa.admin_role,
  pa.active,
  (select count(*) from jsonb_each(pa.permissions)
     where value = 'true'::jsonb) as granted_keys
from platform_admins pa
join auth.users u on u.id = pa.user_id
where pa.user_id = '801d0c3b-8936-4a6f-bfc8-39e93bc826a8';


-- ---- 3. THE REAL FINDING -----------------------------------
--  Your statuses were: 4 rejected, 1 contacted, 0 pending.
--  The approval queue was right — nothing is waiting.
--
--  Reason: your signup form on hsbfix.org does NOT send a
--  status when it files an enquiry. So the value depends on
--  the column default. Let us look at it.

select
  column_name,
  data_type,
  column_default,
  is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name   = 'signup_requests'
order by ordinal_position;

--  In the results, find the row where column_name = 'status'
--  and read column_default:
--
--    'pending'::text   -> correct, new enquiries wait for you
--    'contacted'::text -> wrong, they skip the queue
--    NULL              -> wrong, they have no status at all


-- ---- 4. Make new enquiries land as pending -----------------
--  Safe to run either way. Sets the default AND fixes any
--  existing rows that never got a status.

alter table signup_requests
  alter column status set default 'pending';

update signup_requests
  set status = 'pending'
  where status is null;


-- ---- 5. See every enquiry you have -------------------------
--  So you can decide whether any of the 4 "rejected" ones
--  were rejected by mistake.

select
  created_at::date as received,
  company_name,
  contact_name,
  email,
  phone,
  plan_interest,
  status
from signup_requests
order by created_at desc;
