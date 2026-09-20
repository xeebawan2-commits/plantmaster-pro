-- PlantMaster Control Center v1.0.1 — reliable owner complaint RPCs
-- Additive/idempotent. Requires Phase 11.

create or replace function public.submit_app_complaint(
 p_organization_id uuid,p_category text,p_priority text,p_subject text,p_description text,p_app_version text,p_device_info jsonb default '{}'::jsonb
) returns table(ticket_id uuid,ticket_number bigint)
language plpgsql security definer set search_path=public as $$
declare tid uuid:=gen_random_uuid();tn bigint;
begin
 if auth.uid() is null then raise exception 'Authentication required';end if;
 if public.org_role(p_organization_id)<>'owner' then raise exception 'Company owner access required';end if;
 if p_priority not in('low','medium','high','critical') then raise exception 'Invalid priority';end if;
 if length(trim(coalesce(p_subject,'')))<3 then raise exception 'Subject is required';end if;
 if length(trim(coalesce(p_description,'')))<10 then raise exception 'Please provide a more detailed description';end if;
 insert into public.platform_support_tickets(id,organization_id,opened_by,owner_email,category,priority,subject,description,app_version,device_info,status)
 values(tid,p_organization_id,auth.uid(),coalesce(auth.jwt()->>'email',''),p_category,p_priority,trim(p_subject),trim(p_description),p_app_version,coalesce(p_device_info,'{}'::jsonb),'new') returning platform_support_tickets.ticket_number into tn;
 insert into public.audit_logs(organization_id,user_id,action,entity_type,entity_id,details)
 values(p_organization_id,auth.uid(),'platform_complaint_created','platform_support_ticket',tid::text,jsonb_build_object('ticket_number',tn,'priority',p_priority,'category',p_category,'timestamp',now()));
 return query select tid,tn;
end $$;
grant execute on function public.submit_app_complaint(uuid,text,text,text,text,text,jsonb) to authenticated;

create or replace function public.reply_app_complaint(p_ticket_id uuid,p_message text)
returns uuid language plpgsql security definer set search_path=public as $$
declare t public.platform_support_tickets%rowtype;mid uuid:=gen_random_uuid();
begin
 if auth.uid() is null then raise exception 'Authentication required';end if;
 select * into t from public.platform_support_tickets where id=p_ticket_id;
 if not found then raise exception 'Complaint not found';end if;
 if public.org_role(t.organization_id)<>'owner' then raise exception 'Company owner access required';end if;
 if length(trim(coalesce(p_message,'')))<1 then raise exception 'Reply is required';end if;
 insert into public.platform_support_messages(id,ticket_id,user_id,message,internal) values(mid,t.id,auth.uid(),trim(p_message),false);
 update public.platform_support_tickets set updated_at=now(),status=case when status in('resolved','closed') then 'acknowledged' else status end where id=t.id;
 return mid;
end $$;
grant execute on function public.reply_app_complaint(uuid,text) to authenticated;

create or replace function public.owner_app_complaints(p_organization_id uuid)
returns setof public.platform_support_tickets language plpgsql stable security definer set search_path=public as $$
begin
 if auth.uid() is null or public.org_role(p_organization_id)<>'owner' then raise exception 'Company owner access required';end if;
 return query select * from public.platform_support_tickets where organization_id=p_organization_id order by updated_at desc;
end $$;
grant execute on function public.owner_app_complaints(uuid) to authenticated;

create or replace function public.owner_app_complaint_messages(p_ticket_id uuid)
returns table(id uuid,user_id uuid,message text,created_at timestamptz)
language plpgsql stable security definer set search_path=public as $$
declare oid uuid;
begin
 select organization_id into oid from public.platform_support_tickets where platform_support_tickets.id=p_ticket_id;
 if oid is null or public.org_role(oid)<>'owner' then raise exception 'Company owner access required';end if;
 return query select m.id,m.user_id,m.message,m.created_at from public.platform_support_messages m where m.ticket_id=p_ticket_id and not m.internal order by m.created_at;
end $$;
grant execute on function public.owner_app_complaint_messages(uuid) to authenticated;
