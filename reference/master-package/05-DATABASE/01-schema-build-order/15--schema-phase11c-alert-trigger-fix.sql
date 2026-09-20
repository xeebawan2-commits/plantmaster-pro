-- PlantMaster Control Center v1.0.2
-- Fix shared alert trigger: complaint rows have priority, incidents have severity.

create or replace function public.create_platform_alert()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  row_data jsonb:=to_jsonb(new);
  sev text;
  org_id uuid;
  ticket_no text;
  title_text text;
  body_text text;
begin
  org_id:=nullif(row_data->>'organization_id','')::uuid;

  if tg_table_name='system_incidents' then
    sev:=row_data->>'severity';
    if sev in('error','critical') then
      insert into public.platform_notifications(severity,title,body,component,organization_id)
      values(
        sev,
        'System incident: '||coalesce(row_data->>'component','unknown'),
        coalesce(row_data->>'message','No incident message'),
        coalesce(row_data->>'component','system'),
        org_id
      );
    end if;
  elsif tg_table_name='platform_support_tickets' then
    sev:=row_data->>'priority';
    if sev in('high','critical') then
      ticket_no:=coalesce(row_data->>'ticket_number','');
      title_text:='Complaint #'||ticket_no||': '||coalesce(row_data->>'subject','Untitled complaint');
      body_text:=coalesce(row_data->>'description','No complaint description');
      insert into public.platform_notifications(severity,title,body,component,organization_id)
      values(
        case when sev='critical' then 'critical' else 'warning' end,
        title_text,
        body_text,
        'platform_support',
        org_id
      );
    end if;
  end if;

  return new;
end $$;
