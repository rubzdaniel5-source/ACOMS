-- ============================================================================
-- ACOMS Migration 004: Seed Identity Data
-- Per decisions.md ADR-009/ADR-011. Only the currently-active roles are
-- seeded; the remaining provisional roles from ACOMS_MASTER_SPEC.md §4
-- stay documented but are not created until actually needed.
-- ============================================================================

-- Single organization for now (ADR-010). Replace the code/name below to
-- match your actual airline before running in production.
insert into organizations (code, name) values
  ('AIRLINE01', 'Primary Airline Organization');

-- Known stations from the source workbook (workbook-migration.md).
-- Add further stations as operations confirm them.
insert into stations (organization_id, code, name)
select id, 'LGW', 'London Gatwick' from organizations where code = 'AIRLINE01'
union all
select id, 'EBB', 'Entebbe' from organizations where code = 'AIRLINE01';

-- ----------------------------------------------------------------------------
-- Permissions (capability codes from CLAUDE.md > Authorization / security.md)
-- ----------------------------------------------------------------------------
insert into permissions (code, description) values
  ('view_inventory', 'View equipment inventory and balances'),
  ('create_transfer', 'Create an equipment transfer request'),
  ('approve_transfer', 'Approve a requested transfer'),
  ('dispatch_transfer', 'Mark a transfer as dispatched with actual quantities'),
  ('receive_transfer', 'Record received quantities for an incoming transfer'),
  ('reconcile_transfer', 'Reconcile and close a transfer'),
  ('report_damage', 'Report damaged equipment'),
  ('confirm_loss', 'Confirm equipment as lost following investigation'),
  ('manage_catalogue', 'Create/edit equipment types and categories'),
  ('manage_users', 'Create/edit users and role assignments'),
  ('view_reports', 'View operational and management reports'),
  ('manage_configuration', 'Manage stations, thresholds, and system configuration');

-- ----------------------------------------------------------------------------
-- Roles — only the 7 currently active (decisions.md ADR-009).
-- ----------------------------------------------------------------------------
insert into roles (organization_id, code, name, description)
select id, r.code, r.name, r.description
from organizations, (values
  ('system_admin', 'System Administrator', 'Full system configuration and user management'),
  ('catering_manager', 'Catering Manager', 'Network-wide oversight of catering operations'),
  ('catering_supervisor', 'Catering Supervisor', 'Station-group level operational supervision'),
  ('stores_officer', 'Equipment/Stores Officer', 'Manages equipment catalogue and inventory at a station'),
  ('station_manager', 'Station Manager', 'Manages all catering operations at a specific station'),
  ('catering_assistant_base', 'Catering Assistant (Base)', 'Airline-employed catering staff at base/hub'),
  ('catering_assistant_outstation', 'Catering Assistant (Outstation)', 'Service-provider staff at an outstation')
) as r(code, name, description)
where organizations.code = 'AIRLINE01';

-- ----------------------------------------------------------------------------
-- Role → Permission mapping (initial, adjustable — this is data, not code).
-- Requester-approver separation (ADR-007) is enforced in application/function
-- logic, not by withholding approve_transfer from requesters generally.
-- ----------------------------------------------------------------------------
insert into role_permissions (role_id, permission_id)
select r.id, p.id
from roles r
join permissions p on true
where r.code = 'system_admin' -- full access
  and r.organization_id = (select id from organizations where code = 'AIRLINE01');

insert into role_permissions (role_id, permission_id)
select r.id, p.id
from roles r, permissions p
where r.code = 'catering_manager'
  and p.code in (
    'view_inventory', 'create_transfer', 'approve_transfer', 'reconcile_transfer',
    'report_damage', 'confirm_loss', 'manage_catalogue', 'view_reports', 'manage_configuration'
  );

insert into role_permissions (role_id, permission_id)
select r.id, p.id
from roles r, permissions p
where r.code = 'catering_supervisor'
  and p.code in (
    'view_inventory', 'create_transfer', 'approve_transfer', 'dispatch_transfer',
    'receive_transfer', 'report_damage', 'confirm_loss', 'view_reports'
  );

insert into role_permissions (role_id, permission_id)
select r.id, p.id
from roles r, permissions p
where r.code = 'stores_officer'
  and p.code in (
    'view_inventory', 'create_transfer', 'dispatch_transfer', 'receive_transfer',
    'report_damage', 'manage_catalogue', 'view_reports'
  );

insert into role_permissions (role_id, permission_id)
select r.id, p.id
from roles r, permissions p
where r.code = 'station_manager'
  and p.code in (
    'view_inventory', 'create_transfer', 'approve_transfer', 'dispatch_transfer',
    'receive_transfer', 'reconcile_transfer', 'report_damage', 'confirm_loss', 'view_reports'
  );

insert into role_permissions (role_id, permission_id)
select r.id, p.id
from roles r, permissions p
where r.code in ('catering_assistant_base', 'catering_assistant_outstation')
  and p.code in ('view_inventory', 'create_transfer', 'dispatch_transfer', 'receive_transfer', 'report_damage');
