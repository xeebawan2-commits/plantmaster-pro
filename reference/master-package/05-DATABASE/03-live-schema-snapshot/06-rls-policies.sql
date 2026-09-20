-- =====================================================================
-- PlantMaster Pro — ROW LEVEL SECURITY POLICIES
-- 135 policies across 79 tables. Run AFTER tables and functions exist.
-- =====================================================================


-- ============ action_attachments ============
drop policy if exists "action_attachments_member" on public.action_attachments;
create policy "action_attachments_member" on public.action_attachments for all
  using (is_org_member(organization_id))
  with check (is_org_member(organization_id));

-- ============ admin_action_logs ============
drop policy if exists "platform insert admin logs" on public.admin_action_logs;
create policy "platform insert admin logs" on public.admin_action_logs for insert
  with check (is_platform_admin());
drop policy if exists "platform read admin logs" on public.admin_action_logs;
create policy "platform read admin logs" on public.admin_action_logs for select
  using (platform_has_permission('audit.view'::text));
drop policy if exists "super admin inserts audit" on public.admin_action_logs;
create policy "super admin inserts audit" on public.admin_action_logs for insert
  with check (is_super_platform_admin());
drop policy if exists "super admin read access admin_action_logs" on public.admin_action_logs;
create policy "super admin read access admin_action_logs" on public.admin_action_logs for select
  using (is_super_platform_admin());

-- ============ ai_usage ============
drop policy if exists "ai_usage_member" on public.ai_usage;
create policy "ai_usage_member" on public.ai_usage for select
  using (is_org_member(organization_id));
drop policy if exists "super admin read access ai_usage" on public.ai_usage;
create policy "super admin read access ai_usage" on public.ai_usage for select
  using (is_super_platform_admin());

-- ============ api_keys ============
drop policy if exists "api_keys_read" on public.api_keys;
create policy "api_keys_read" on public.api_keys for select
  using (pm_is_org_owner(organization_id));
drop policy if exists "api_keys_write" on public.api_keys;
create policy "api_keys_write" on public.api_keys for all
  using (pm_is_org_owner(organization_id))
  with check (pm_is_org_owner(organization_id));

-- ============ asset_status_history ============
drop policy if exists "status_insert" on public.asset_status_history;
create policy "status_insert" on public.asset_status_history for insert
  with check (is_org_member(organization_id));
drop policy if exists "status_read" on public.asset_status_history;
create policy "status_read" on public.asset_status_history for select
  using (is_org_member(organization_id));

-- ============ assets ============
drop policy if exists "assets read" on public.assets;
create policy "assets read" on public.assets for select
  using (is_org_member(organization_id));
drop policy if exists "assets write" on public.assets;
create policy "assets write" on public.assets for all
  using ((is_org_member(organization_id) AND (org_role(organization_id) = ANY (ARRAY['owner'::text, 'manager'::text, 'engineer'::text, 'supervisor'::text, 'technician'::text]))))
  with check ((is_org_member(organization_id) AND (org_role(organization_id) = ANY (ARRAY['owner'::text, 'manager'::text, 'engineer'::text, 'supervisor'::text, 'technician'::text]))));

-- ============ attendance ============
drop policy if exists "attendance_member" on public.attendance;
create policy "attendance_member" on public.attendance for all
  using (is_org_member(organization_id))
  with check (is_org_member(organization_id));

-- ============ audit_logs ============
drop policy if exists "audit insert" on public.audit_logs;
create policy "audit insert" on public.audit_logs for insert
  with check (is_org_member(organization_id));
drop policy if exists "audit read" on public.audit_logs;
create policy "audit read" on public.audit_logs for select
  using (is_org_member(organization_id));

-- ============ backup_jobs ============
drop policy if exists "platform backup access" on public.backup_jobs;
create policy "platform backup access" on public.backup_jobs for all
  using (platform_has_permission('backups.manage'::text))
  with check (platform_has_permission('backups.manage'::text));
drop policy if exists "super admin full access backup_jobs" on public.backup_jobs;
create policy "super admin full access backup_jobs" on public.backup_jobs for all
  using (is_super_platform_admin())
  with check (is_super_platform_admin());

-- ============ checklist_items ============
drop policy if exists "checklist_items_member" on public.checklist_items;
create policy "checklist_items_member" on public.checklist_items for all
  using ((EXISTS ( SELECT 1
   FROM checklist_templates t
  WHERE ((t.id = checklist_items.template_id) AND is_org_member(t.organization_id)))))
  with check ((EXISTS ( SELECT 1
   FROM checklist_templates t
  WHERE ((t.id = checklist_items.template_id) AND is_org_member(t.organization_id)))));

-- ============ checklist_runs ============
drop policy if exists "checklist_runs_member" on public.checklist_runs;
create policy "checklist_runs_member" on public.checklist_runs for all
  using (is_org_member(organization_id))
  with check (is_org_member(organization_id));

-- ============ checklist_templates ============
drop policy if exists "checklist_templates_member" on public.checklist_templates;
create policy "checklist_templates_member" on public.checklist_templates for all
  using (is_org_member(organization_id))
  with check (is_org_member(organization_id));

-- ============ checklist_values ============
drop policy if exists "checklist_values_member" on public.checklist_values;
create policy "checklist_values_member" on public.checklist_values for all
  using ((EXISTS ( SELECT 1
   FROM checklist_runs r
  WHERE ((r.id = checklist_values.run_id) AND is_org_member(r.organization_id)))))
  with check ((EXISTS ( SELECT 1
   FROM checklist_runs r
  WHERE ((r.id = checklist_values.run_id) AND is_org_member(r.organization_id)))));

-- ============ code_registry ============
drop policy if exists "code registry member access" on public.code_registry;
create policy "code registry member access" on public.code_registry for all
  using (is_org_member(organization_id))
  with check (is_org_member(organization_id));

-- ============ company_feature_blocks ============
drop policy if exists "platform feature block access" on public.company_feature_blocks;
create policy "platform feature block access" on public.company_feature_blocks for all
  using (platform_has_permission('companies.manage'::text))
  with check (platform_has_permission('companies.manage'::text));
drop policy if exists "super admin full access company_feature_blocks" on public.company_feature_blocks;
create policy "super admin full access company_feature_blocks" on public.company_feature_blocks for all
  using (is_super_platform_admin())
  with check (is_super_platform_admin());

-- ============ complimentary_access ============
drop policy if exists "platform manage complimentary" on public.complimentary_access;
create policy "platform manage complimentary" on public.complimentary_access for all
  using (platform_has_permission('companies.manage'::text))
  with check (platform_has_permission('companies.manage'::text));
drop policy if exists "super admin full access complimentary_access" on public.complimentary_access;
create policy "super admin full access complimentary_access" on public.complimentary_access for all
  using (is_super_platform_admin())
  with check (is_super_platform_admin());

-- ============ condition_alarms ============
drop policy if exists "condition alarms member access" on public.condition_alarms;
create policy "condition alarms member access" on public.condition_alarms for all
  using (is_org_member(organization_id))
  with check (is_org_member(organization_id));

-- ============ condition_entity_links ============
drop policy if exists "condition links member access" on public.condition_entity_links;
create policy "condition links member access" on public.condition_entity_links for all
  using (is_org_member(organization_id))
  with check (is_org_member(organization_id));

-- ============ condition_recordings ============
drop policy if exists "condition recordings member access" on public.condition_recordings;
create policy "condition recordings member access" on public.condition_recordings for all
  using (is_org_member(organization_id))
  with check (is_org_member(organization_id));

-- ============ daily_logs ============
drop policy if exists "daily_logs_member" on public.daily_logs;
create policy "daily_logs_member" on public.daily_logs for all
  using (is_org_member(organization_id))
  with check (is_org_member(organization_id));

-- ============ data_retention_policies ============
drop policy if exists "owner manages retention" on public.data_retention_policies;
create policy "owner manages retention" on public.data_retention_policies for all
  using (((org_role(organization_id) = 'owner'::text) OR is_platform_admin()))
  with check (((org_role(organization_id) = 'owner'::text) OR is_platform_admin()));
drop policy if exists "super admin full access data_retention_policies" on public.data_retention_policies;
create policy "super admin full access data_retention_policies" on public.data_retention_policies for all
  using (is_super_platform_admin())
  with check (is_super_platform_admin());

-- ============ deletion_requests ============
drop policy if exists "owner manages deletion requests" on public.deletion_requests;
create policy "owner manages deletion requests" on public.deletion_requests for all
  using (((org_role(organization_id) = 'owner'::text) OR (requested_by = auth.uid()) OR is_platform_admin()))
  with check (((org_role(organization_id) = 'owner'::text) OR (requested_by = auth.uid()) OR is_platform_admin()));
drop policy if exists "super admin full access deletion_requests" on public.deletion_requests;
create policy "super admin full access deletion_requests" on public.deletion_requests for all
  using (is_super_platform_admin())
  with check (is_super_platform_admin());

-- ============ document_chunks ============
drop policy if exists "chunks_member" on public.document_chunks;
create policy "chunks_member" on public.document_chunks for select
  using ((EXISTS ( SELECT 1
   FROM manuals m
  WHERE ((m.id = document_chunks.manual_id) AND is_org_member(m.organization_id)))));

-- ============ file_metadata ============
drop policy if exists "files read" on public.file_metadata;
create policy "files read" on public.file_metadata for select
  using (is_org_member(organization_id));
drop policy if exists "files write" on public.file_metadata;
create policy "files write" on public.file_metadata for insert
  with check (is_org_member(organization_id));

-- ============ inventory_transactions ============
drop policy if exists "inventory_transactions_member" on public.inventory_transactions;
create policy "inventory_transactions_member" on public.inventory_transactions for all
  using ((EXISTS ( SELECT 1
   FROM spares s
  WHERE ((s.id = inventory_transactions.spare_id) AND is_org_member(s.organization_id)))))
  with check ((EXISTS ( SELECT 1
   FROM spares s
  WHERE ((s.id = inventory_transactions.spare_id) AND is_org_member(s.organization_id)))));

-- ============ invitations ============
drop policy if exists "invites_manage" on public.invitations;
create policy "invites_manage" on public.invitations for all
  using ((is_org_member(organization_id) AND (org_role(organization_id) = ANY (ARRAY['owner'::text, 'manager'::text]))))
  with check ((is_org_member(organization_id) AND (org_role(organization_id) = ANY (ARRAY['owner'::text, 'manager'::text]))));

-- ============ legal_acceptances ============
drop policy if exists "super admin full access legal_acceptances" on public.legal_acceptances;
create policy "super admin full access legal_acceptances" on public.legal_acceptances for all
  using (is_super_platform_admin())
  with check (is_super_platform_admin());
drop policy if exists "user manages own acceptance" on public.legal_acceptances;
create policy "user manages own acceptance" on public.legal_acceptances for all
  using ((user_id = auth.uid()))
  with check (((user_id = auth.uid()) AND ((organization_id IS NULL) OR is_org_member(organization_id))));

-- ============ legal_documents ============
drop policy if exists "authenticated read active legal docs" on public.legal_documents;
create policy "authenticated read active legal docs" on public.legal_documents for select
  using ((active OR is_platform_admin()));
drop policy if exists "platform manages legal documents" on public.legal_documents;
create policy "platform manages legal documents" on public.legal_documents for all
  using (platform_has_permission('legal.manage'::text))
  with check (platform_has_permission('legal.manage'::text));
drop policy if exists "super admin full access legal_documents" on public.legal_documents;
create policy "super admin full access legal_documents" on public.legal_documents for all
  using (is_super_platform_admin())
  with check (is_super_platform_admin());

-- ============ loto_procedures ============
drop policy if exists "loto access" on public.loto_procedures;
create policy "loto access" on public.loto_procedures for all
  using ((EXISTS ( SELECT 1
   FROM plants p
  WHERE ((p.id = loto_procedures.plant_id) AND is_org_member(p.organization_id)))));

-- ============ maintenance_completions ============
drop policy if exists "maintenance_completions_member" on public.maintenance_completions;
create policy "maintenance_completions_member" on public.maintenance_completions for all
  using (is_org_member(organization_id))
  with check (is_org_member(organization_id));

-- ============ maintenance_plans ============
drop policy if exists "maintenance_plans_member" on public.maintenance_plans;
create policy "maintenance_plans_member" on public.maintenance_plans for all
  using (is_org_member(organization_id))
  with check (is_org_member(organization_id));

-- ============ manuals ============
drop policy if exists "manuals_member" on public.manuals;
create policy "manuals_member" on public.manuals for all
  using ((EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = manuals.organization_id) AND (om.user_id = auth.uid()) AND om.active AND ((om.role = ANY (ARRAY['owner'::text, 'manager'::text])) OR COALESCE(((om.permissions ->> 'manuals.view'::text))::boolean, true))))))
  with check ((EXISTS ( SELECT 1
   FROM organization_members om
  WHERE ((om.organization_id = manuals.organization_id) AND (om.user_id = auth.uid()) AND om.active AND ((om.role = ANY (ARRAY['owner'::text, 'manager'::text])) OR COALESCE(((om.permissions ->> 'manuals.view'::text))::boolean, true))))));

-- ============ material_requests ============
drop policy if exists "mat_req access" on public.material_requests;
create policy "mat_req access" on public.material_requests for all
  using (is_org_member(organization_id))
  with check (is_org_member(organization_id));

-- ============ measurement_points ============
drop policy if exists "condition points member access" on public.measurement_points;
create policy "condition points member access" on public.measurement_points for all
  using (is_org_member(organization_id))
  with check (is_org_member(organization_id));

-- ============ notifications ============
drop policy if exists "notifications_member" on public.notifications;
create policy "notifications_member" on public.notifications for all
  using (is_org_member(organization_id))
  with check (is_org_member(organization_id));

-- ============ organization_entitlements ============
drop policy if exists "owner reads entitlements" on public.organization_entitlements;
create policy "owner reads entitlements" on public.organization_entitlements for select
  using (((org_role(organization_id) = 'owner'::text) OR is_platform_admin()));

-- ============ organization_members ============
drop policy if exists "members read" on public.organization_members;
create policy "members read" on public.organization_members for select
  using (is_org_member(organization_id));
drop policy if exists "owner manages members" on public.organization_members;
create policy "owner manages members" on public.organization_members for update
  using ((org_role(organization_id) = 'owner'::text))
  with check ((org_role(organization_id) = 'owner'::text));

-- ============ organization_settings ============
drop policy if exists "settings_read" on public.organization_settings;
create policy "settings_read" on public.organization_settings for select
  using (is_org_member(organization_id));
drop policy if exists "settings_write" on public.organization_settings;
create policy "settings_write" on public.organization_settings for all
  using ((is_org_member(organization_id) AND (org_role(organization_id) = ANY (ARRAY['owner'::text, 'manager'::text]))))
  with check ((is_org_member(organization_id) AND (org_role(organization_id) = ANY (ARRAY['owner'::text, 'manager'::text]))));

-- ============ organization_subscriptions ============
drop policy if exists "owner reads subscription" on public.organization_subscriptions;
create policy "owner reads subscription" on public.organization_subscriptions for select
  using (((org_role(organization_id) = 'owner'::text) OR is_platform_admin()));
drop policy if exists "super admin read access organization_subscriptions" on public.organization_subscriptions;
create policy "super admin read access organization_subscriptions" on public.organization_subscriptions for select
  using (is_super_platform_admin());

-- ============ organizations ============
drop policy if exists "org members read" on public.organizations;
create policy "org members read" on public.organizations for select
  using (is_org_member(id));

-- ============ permits ============
drop policy if exists "permits access" on public.permits;
create policy "permits access" on public.permits for all
  using ((EXISTS ( SELECT 1
   FROM plants p
  WHERE ((p.id = permits.plant_id) AND is_org_member(p.organization_id)))));

-- ============ plantmaster_sync ============
drop policy if exists "plantmaster insert" on public.plantmaster_sync;
create policy "plantmaster insert" on public.plantmaster_sync for insert
  with check (true);
drop policy if exists "plantmaster read" on public.plantmaster_sync;
create policy "plantmaster read" on public.plantmaster_sync for select
  using (true);
drop policy if exists "plantmaster update" on public.plantmaster_sync;
create policy "plantmaster update" on public.plantmaster_sync for update
  using (true)
  with check (true);

-- ============ plants ============
drop policy if exists "plants read" on public.plants;
create policy "plants read" on public.plants for select
  using (is_org_member(organization_id));

-- ============ platform_admins ============
drop policy if exists "platform admin updates self" on public.platform_admins;
create policy "platform admin updates self" on public.platform_admins for update
  using ((user_id = auth.uid()))
  with check ((user_id = auth.uid()));
drop policy if exists "platform admins read self" on public.platform_admins;
create policy "platform admins read self" on public.platform_admins for select
  using ((user_id = auth.uid()));
drop policy if exists "super admin full access platform_admins" on public.platform_admins;
create policy "super admin full access platform_admins" on public.platform_admins for all
  using (is_super_platform_admin())
  with check (is_super_platform_admin());
drop policy if exists "super admin manages administrators" on public.platform_admins;
create policy "super admin manages administrators" on public.platform_admins for all
  using (platform_has_permission('admins.manage'::text))
  with check (platform_has_permission('admins.manage'::text));

-- ============ platform_notifications ============
drop policy if exists "platform notification access" on public.platform_notifications;
create policy "platform notification access" on public.platform_notifications for all
  using (is_platform_admin())
  with check (is_platform_admin());
drop policy if exists "super admin full access platform_notifications" on public.platform_notifications;
create policy "super admin full access platform_notifications" on public.platform_notifications for all
  using (is_super_platform_admin())
  with check (is_super_platform_admin());

-- ============ platform_support_messages ============
drop policy if exists "owner creates public ticket messages" on public.platform_support_messages;
create policy "owner creates public ticket messages" on public.platform_support_messages for insert
  with check (((NOT internal) AND (user_id = auth.uid()) AND (EXISTS ( SELECT 1
   FROM platform_support_tickets t
  WHERE ((t.id = platform_support_messages.ticket_id) AND (org_role(t.organization_id) = 'owner'::text))))));
drop policy if exists "owner reads public ticket messages" on public.platform_support_messages;
create policy "owner reads public ticket messages" on public.platform_support_messages for select
  using (((NOT internal) AND (EXISTS ( SELECT 1
   FROM platform_support_tickets t
  WHERE ((t.id = platform_support_messages.ticket_id) AND (org_role(t.organization_id) = 'owner'::text))))));
drop policy if exists "platform manages ticket messages" on public.platform_support_messages;
create policy "platform manages ticket messages" on public.platform_support_messages for all
  using (platform_has_permission('support.manage'::text))
  with check (platform_has_permission('support.manage'::text));
drop policy if exists "super admin full access platform_support_messages" on public.platform_support_messages;
create policy "super admin full access platform_support_messages" on public.platform_support_messages for all
  using (is_super_platform_admin())
  with check (is_super_platform_admin());

-- ============ platform_support_tickets ============
drop policy if exists "owner creates tickets" on public.platform_support_tickets;
create policy "owner creates tickets" on public.platform_support_tickets for insert
  with check (((organization_id IS NOT NULL) AND (org_role(organization_id) = 'owner'::text) AND (opened_by = auth.uid())));
drop policy if exists "owner reads tickets" on public.platform_support_tickets;
create policy "owner reads tickets" on public.platform_support_tickets for select
  using (((organization_id IS NOT NULL) AND (org_role(organization_id) = 'owner'::text)));
drop policy if exists "platform manages tickets" on public.platform_support_tickets;
create policy "platform manages tickets" on public.platform_support_tickets for all
  using (platform_has_permission('support.manage'::text))
  with check (platform_has_permission('support.manage'::text));
drop policy if exists "super admin full access platform_support_tickets" on public.platform_support_tickets;
create policy "super admin full access platform_support_tickets" on public.platform_support_tickets for all
  using (is_super_platform_admin())
  with check (is_super_platform_admin());

-- ============ problem_cases ============
drop policy if exists "cases_member" on public.problem_cases;
create policy "cases_member" on public.problem_cases for all
  using (is_org_member(organization_id))
  with check (is_org_member(organization_id));

-- ============ profiles ============
drop policy if exists "members read coworker profiles" on public.profiles;
create policy "members read coworker profiles" on public.profiles for select
  using ((EXISTS ( SELECT 1
   FROM organization_members target
  WHERE ((target.user_id = profiles.id) AND is_org_member(target.organization_id)))));
drop policy if exists "owner updates coworker profiles" on public.profiles;
create policy "owner updates coworker profiles" on public.profiles for update
  using ((EXISTS ( SELECT 1
   FROM organization_members target
  WHERE ((target.user_id = profiles.id) AND (org_role(target.organization_id) = 'owner'::text)))))
  with check ((EXISTS ( SELECT 1
   FROM organization_members target
  WHERE ((target.user_id = profiles.id) AND (org_role(target.organization_id) = 'owner'::text)))));
drop policy if exists "profile self" on public.profiles;
create policy "profile self" on public.profiles for all
  using ((id = auth.uid()))
  with check ((id = auth.uid()));

-- ============ purchase_order_lines ============
drop policy if exists "pol_read" on public.purchase_order_lines;
create policy "pol_read" on public.purchase_order_lines for select
  using ((EXISTS ( SELECT 1
   FROM purchase_orders po
  WHERE ((po.id = purchase_order_lines.purchase_order_id) AND pm_is_org_member(po.organization_id)))));
drop policy if exists "pol_write" on public.purchase_order_lines;
create policy "pol_write" on public.purchase_order_lines for all
  using ((EXISTS ( SELECT 1
   FROM purchase_orders po
  WHERE ((po.id = purchase_order_lines.purchase_order_id) AND pm_is_org_leader(po.organization_id)))))
  with check ((EXISTS ( SELECT 1
   FROM purchase_orders po
  WHERE ((po.id = purchase_order_lines.purchase_order_id) AND pm_is_org_leader(po.organization_id)))));

-- ============ purchase_orders ============
drop policy if exists "po_read" on public.purchase_orders;
create policy "po_read" on public.purchase_orders for select
  using (pm_is_org_member(organization_id));
drop policy if exists "po_write" on public.purchase_orders;
create policy "po_write" on public.purchase_orders for all
  using (pm_is_org_leader(organization_id))
  with check (pm_is_org_leader(organization_id));

-- ============ qa_environments ============
drop policy if exists "active platform admin qa environments" on public.qa_environments;
create policy "active platform admin qa environments" on public.qa_environments for all
  using (is_platform_admin())
  with check (is_platform_admin());
drop policy if exists "platform qa environment access" on public.qa_environments;
create policy "platform qa environment access" on public.qa_environments for all
  using (platform_has_permission('qa.manage'::text))
  with check (platform_has_permission('qa.manage'::text));
drop policy if exists "super admin full access qa_environments" on public.qa_environments;
create policy "super admin full access qa_environments" on public.qa_environments for all
  using (is_super_platform_admin())
  with check (is_super_platform_admin());

-- ============ qa_manual_checks ============
drop policy if exists "active platform admin qa manual checks" on public.qa_manual_checks;
create policy "active platform admin qa manual checks" on public.qa_manual_checks for all
  using (is_platform_admin())
  with check (is_platform_admin());
drop policy if exists "platform qa manual access" on public.qa_manual_checks;
create policy "platform qa manual access" on public.qa_manual_checks for all
  using (platform_has_permission('qa.manage'::text))
  with check (platform_has_permission('qa.manage'::text));
drop policy if exists "super admin full access qa_manual_checks" on public.qa_manual_checks;
create policy "super admin full access qa_manual_checks" on public.qa_manual_checks for all
  using (is_super_platform_admin())
  with check (is_super_platform_admin());

-- ============ qa_test_results ============
drop policy if exists "active platform admin qa results" on public.qa_test_results;
create policy "active platform admin qa results" on public.qa_test_results for all
  using (is_platform_admin())
  with check (is_platform_admin());
drop policy if exists "platform qa result access" on public.qa_test_results;
create policy "platform qa result access" on public.qa_test_results for all
  using (platform_has_permission('qa.manage'::text))
  with check (platform_has_permission('qa.manage'::text));
drop policy if exists "super admin full access qa_test_results" on public.qa_test_results;
create policy "super admin full access qa_test_results" on public.qa_test_results for all
  using (is_super_platform_admin())
  with check (is_super_platform_admin());

-- ============ qa_test_runs ============
drop policy if exists "active platform admin qa runs" on public.qa_test_runs;
create policy "active platform admin qa runs" on public.qa_test_runs for all
  using (is_platform_admin())
  with check (is_platform_admin());
drop policy if exists "platform qa run access" on public.qa_test_runs;
create policy "platform qa run access" on public.qa_test_runs for all
  using (platform_has_permission('qa.manage'::text))
  with check (platform_has_permission('qa.manage'::text));
drop policy if exists "super admin full access qa_test_runs" on public.qa_test_runs;
create policy "super admin full access qa_test_runs" on public.qa_test_runs for all
  using (is_super_platform_admin())
  with check (is_super_platform_admin());

-- ============ quota_overrides ============
drop policy if exists "platform manage quota" on public.quota_overrides;
create policy "platform manage quota" on public.quota_overrides for all
  using (platform_has_permission('usage.manage'::text))
  with check (platform_has_permission('usage.manage'::text));
drop policy if exists "super admin full access quota_overrides" on public.quota_overrides;
create policy "super admin full access quota_overrides" on public.quota_overrides for all
  using (is_super_platform_admin())
  with check (is_super_platform_admin());

-- ============ report_dispatches ============
drop policy if exists "reports_member" on public.report_dispatches;
create policy "reports_member" on public.report_dispatches for all
  using (is_org_member(organization_id))
  with check (is_org_member(organization_id));

-- ============ restore_drills ============
drop policy if exists "platform restore access" on public.restore_drills;
create policy "platform restore access" on public.restore_drills for all
  using (platform_has_permission('backups.manage'::text))
  with check (platform_has_permission('backups.manage'::text));
drop policy if exists "super admin full access restore_drills" on public.restore_drills;
create policy "super admin full access restore_drills" on public.restore_drills for all
  using (is_super_platform_admin())
  with check (is_super_platform_admin());

-- ============ scan_entity_links ============
drop policy if exists "scan links member access" on public.scan_entity_links;
create policy "scan links member access" on public.scan_entity_links for all
  using (is_org_member(organization_id))
  with check (is_org_member(organization_id));

-- ============ scan_pages ============
drop policy if exists "scanner page member access" on public.scan_pages;
create policy "scanner page member access" on public.scan_pages for all
  using ((EXISTS ( SELECT 1
   FROM scan_sessions s
  WHERE ((s.id = scan_pages.session_id) AND is_org_member(s.organization_id)))))
  with check ((EXISTS ( SELECT 1
   FROM scan_sessions s
  WHERE ((s.id = scan_pages.session_id) AND is_org_member(s.organization_id)))));

-- ============ scan_sessions ============
drop policy if exists "scanner member access" on public.scan_sessions;
create policy "scanner member access" on public.scan_sessions for all
  using (is_org_member(organization_id))
  with check (is_org_member(organization_id));

-- ============ sensor_devices ============
drop policy if exists "condition sensors member access" on public.sensor_devices;
create policy "condition sensors member access" on public.sensor_devices for all
  using (is_org_member(organization_id))
  with check (is_org_member(organization_id));

-- ============ shift_assignments ============
drop policy if exists "shift_assignments_member" on public.shift_assignments;
create policy "shift_assignments_member" on public.shift_assignments for all
  using (is_org_member(organization_id))
  with check (is_org_member(organization_id));

-- ============ shift_handovers ============
drop policy if exists "shift_handovers_member" on public.shift_handovers;
create policy "shift_handovers_member" on public.shift_handovers for all
  using (is_org_member(organization_id))
  with check (is_org_member(organization_id));

-- ============ spares ============
drop policy if exists "spares_member" on public.spares;
create policy "spares_member" on public.spares for all
  using (is_org_member(organization_id))
  with check (is_org_member(organization_id));

-- ============ storage_reservations ============
drop policy if exists "user reads own storage reservations" on public.storage_reservations;
create policy "user reads own storage reservations" on public.storage_reservations for select
  using (((user_id = auth.uid()) OR (org_role(organization_id) = 'owner'::text) OR is_platform_admin()));

-- ============ storage_usage_events ============
drop policy if exists "owner reads storage usage" on public.storage_usage_events;
create policy "owner reads storage usage" on public.storage_usage_events for select
  using (((org_role(organization_id) = 'owner'::text) OR is_platform_admin()));
drop policy if exists "super admin read access storage_usage_events" on public.storage_usage_events;
create policy "super admin read access storage_usage_events" on public.storage_usage_events for select
  using (is_super_platform_admin());

-- ============ subscription_plans ============
drop policy if exists "authenticated read active plans" on public.subscription_plans;
create policy "authenticated read active plans" on public.subscription_plans for select
  using ((active OR is_platform_admin()));
drop policy if exists "super admin read access subscription_plans" on public.subscription_plans;
create policy "super admin read access subscription_plans" on public.subscription_plans for select
  using (is_super_platform_admin());

-- ============ suppliers ============
drop policy if exists "suppliers_read" on public.suppliers;
create policy "suppliers_read" on public.suppliers for select
  using (pm_is_org_member(organization_id));
drop policy if exists "suppliers_write" on public.suppliers;
create policy "suppliers_write" on public.suppliers for all
  using (pm_is_org_leader(organization_id))
  with check (pm_is_org_leader(organization_id));

-- ============ support_messages ============
drop policy if exists "support_messages_member" on public.support_messages;
create policy "support_messages_member" on public.support_messages for all
  using ((EXISTS ( SELECT 1
   FROM support_threads t
  WHERE ((t.id = support_messages.thread_id) AND is_org_member(t.organization_id)))))
  with check ((EXISTS ( SELECT 1
   FROM support_threads t
  WHERE ((t.id = support_messages.thread_id) AND is_org_member(t.organization_id)))));

-- ============ support_threads ============
drop policy if exists "support_threads_member" on public.support_threads;
create policy "support_threads_member" on public.support_threads for all
  using (is_org_member(organization_id))
  with check (is_org_member(organization_id));

-- ============ system_incidents ============
drop policy if exists "members read own incidents" on public.system_incidents;
create policy "members read own incidents" on public.system_incidents for select
  using ((((organization_id IS NOT NULL) AND is_org_member(organization_id)) OR is_platform_admin()));
drop policy if exists "super admin read access system_incidents" on public.system_incidents;
create policy "super admin read access system_incidents" on public.system_incidents for select
  using (is_super_platform_admin());

-- ============ technical_experiences ============
drop policy if exists "experiences_member" on public.technical_experiences;
create policy "experiences_member" on public.technical_experiences for all
  using (is_org_member(organization_id))
  with check (is_org_member(organization_id));

-- ============ tool_transactions ============
drop policy if exists "tool_transactions_member" on public.tool_transactions;
create policy "tool_transactions_member" on public.tool_transactions for all
  using (is_org_member(organization_id))
  with check (is_org_member(organization_id));

-- ============ tools ============
drop policy if exists "tools_member" on public.tools;
create policy "tools_member" on public.tools for all
  using (is_org_member(organization_id))
  with check (is_org_member(organization_id));

-- ============ usage_adjustments ============
drop policy if exists "platform create adjustment" on public.usage_adjustments;
create policy "platform create adjustment" on public.usage_adjustments for select
  using (platform_has_permission('usage.view'::text));
drop policy if exists "platform insert adjustment" on public.usage_adjustments;
create policy "platform insert adjustment" on public.usage_adjustments for insert
  with check (platform_has_permission('usage.manage'::text));
drop policy if exists "super admin inserts usage adjustments" on public.usage_adjustments;
create policy "super admin inserts usage adjustments" on public.usage_adjustments for insert
  with check (is_super_platform_admin());
drop policy if exists "super admin read access usage_adjustments" on public.usage_adjustments;
create policy "super admin read access usage_adjustments" on public.usage_adjustments for select
  using (is_super_platform_admin());

-- ============ usage_counters ============
drop policy if exists "owner reads usage counters" on public.usage_counters;
create policy "owner reads usage counters" on public.usage_counters for select
  using (((org_role(organization_id) = 'owner'::text) OR is_platform_admin()));
drop policy if exists "super admin read access usage_counters" on public.usage_counters;
create policy "super admin read access usage_counters" on public.usage_counters for select
  using (is_super_platform_admin());

-- ============ usage_events ============
drop policy if exists "owner reads usage events" on public.usage_events;
create policy "owner reads usage events" on public.usage_events for select
  using (((org_role(organization_id) = 'owner'::text) OR is_platform_admin()));
drop policy if exists "super admin read access usage_events" on public.usage_events;
create policy "super admin read access usage_events" on public.usage_events for select
  using (is_super_platform_admin());

-- ============ work_orders ============
drop policy if exists "work read" on public.work_orders;
create policy "work read" on public.work_orders for select
  using (is_org_member(organization_id));
drop policy if exists "work write" on public.work_orders;
create policy "work write" on public.work_orders for all
  using ((is_org_member(organization_id) AND (org_role(organization_id) <> 'viewer'::text)))
  with check ((is_org_member(organization_id) AND (org_role(organization_id) <> 'viewer'::text)));