-- Roles, users, settings, dispatch limits and the pending-transfers view.

-- ===== Users and roles ==========================================================
select test.as_user('mgr_ebb');
select test.fails($$select set_user_active(test.uid('asst_ebb'), false, 'x')$$, 'manage_users', 'users: a station manager cannot deactivate users');
select test.fails($$select assign_user_role(test.uid('outsider'), test.role('station_manager'), test.st('EBB'))$$, 'manage_users', 'users: a station manager cannot assign roles');
select test.as_anon();
select test.fails($$select assign_user_role(test.uid('outsider'), test.role('station_manager'), test.st('EBB'))$$, 'permission denied', 'users: anonymous callers cannot assign roles');

select test.as_user('admin');
select test.fails($$select set_user_active(test.uid('admin'), false, 'self')$$, 'yourself', 'users: cannot deactivate yourself');
select test.fails($$select assign_user_role(test.uid('admin'), test.role('station_manager'), test.st('EBB'))$$, 'own roles', 'users: cannot change your own roles');
select test.fails($$select set_user_active(test.uid('asst_abj'), false, '')$$, 'reason', 'users: deactivation needs a reason');
select test.works($$select assign_user_role(test.uid('outsider'), test.role('catering_assistant_base'), test.st('EBB'))$$, 'users: admin can assign a role');
select test.fails($$select assign_user_role(test.uid('outsider'), test.role('catering_assistant_base'), test.st('EBB'))$$, 'already has', 'users: the same assignment twice is refused');
select test.as_root();
select test.eq_int((select count(*) from user_roles where user_id = test.uid('outsider')), 1, 'users: exactly one role row was created');
select test.as_user('outsider');
select test.works($$select 1 from equipment_transfers$$, 'users: the newly assigned user can query as normal');
select test.as_user('admin');
select test.works($$select remove_user_role((select id from user_roles where user_id = test.uid('outsider')))$$, 'users: admin can remove the role again');

-- Deactivation takes effect at once
select test.works($$select set_user_active(test.uid('mgr_abj'), false, 'left the company')$$, 'users: admin can deactivate a user with a reason');
select test.as_user('mgr_abj');
select test.fails($$select request_transfer(test.st('ABJ'), test.st('EBB'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 1)), 'x', 'NORMAL')$$,
  'Missing permission', 'users: a deactivated user immediately loses every permission');
select test.eq_int((select count(*) from inventory_balances), 0, 'users: a deactivated user sees no inventory');
select test.as_user('admin');
select test.works($$select set_user_active(test.uid('mgr_abj'), true, null)$$, 'users: admin can reactivate');
select test.as_user('mgr_abj');
select test.ok((select count(*) from inventory_balances) > 0, 'users: reactivated user sees inventory again');

-- No privilege escalation: a custom role holding only manage_users cannot hand out admin.
select test.as_user('admin');
select test.works($$select create_role('user_manager', 'User manager', 'test role')$$, 'roles: admin can create a role');
select test.works($$select set_role_permission(test.role('user_manager'), 'manage_users', true)$$, 'roles: admin can grant a permission to it');
select test.fails($$select set_role_permission(test.role('system_admin'), 'view_reports', false)$$, 'locked', 'roles: the System Administrator role is locked');
select test.as_root();
insert into test.users values ('usermgr', gen_random_uuid());
insert into auth.users (id, email) values (test.uid('usermgr'), 'usermgr@test.local');
insert into user_profiles (id, organization_id, full_name, email) values (test.uid('usermgr'), (select id from organizations limit 1), 'Usermgr', 'usermgr@test.local');
insert into user_roles (user_id, role_id) values (test.uid('usermgr'), test.role('user_manager'));
select test.as_user('usermgr');
select test.fails($$select assign_user_role(test.uid('outsider'), test.role('system_admin'), null)$$, 'do not hold', 'roles: cannot grant a role carrying permissions you lack (no escalation)');
select test.fails($$select set_role_permission(test.role('user_manager'), 'approve_transfer', true)$$, 'manage_roles', 'roles: manage_users alone cannot edit role permissions');
select test.fails($$select set_user_active(test.uid('admin'), false, 'coup')$$, 'do not hold', 'roles: cannot deactivate an admin you do not out-rank');
select test.fails($$select create_role('X', 'X', null)$$, 'manage_roles', 'roles: manage_users alone cannot create roles');

-- ===== Settings =================================================================
select test.as_user('mgr_ebb');
select test.fails($$select update_setting('transfers.total_overdue_days', 10, 'x')$$, 'manage_configuration', 'settings: station manager cannot change settings');
select test.as_user('admin');
select test.fails($$select update_setting('transfers.total_overdue_days', 0, 'x')$$, 'between', 'settings: below the minimum is refused');
select test.fails($$select update_setting('transfers.total_overdue_days', 1000, 'x')$$, 'between', 'settings: above the maximum is refused');
select test.fails($$select update_setting('no.such.key', 1, 'x')$$, 'Unknown', 'settings: unknown key is refused');
select test.fails($$select update_setting('health.shortage_ratio', 0.3, 'x')$$, 'increase in order', 'settings: stock ratios must stay in order');
select test.works($$select update_setting('transfers.total_overdue_days', 10, 'longer routes')$$, 'settings: a valid change is accepted');
select test.ok(get_setting('transfers.total_overdue_days') = 10, 'settings: get_setting returns the new value');
select test.as_root();
select test.ok(exists (select 1 from audit_logs where action = 'setting.update'), 'settings: change is audited');
select test.as_user('admin');
select test.works($$select reset_setting('transfers.total_overdue_days', 'back')$$, 'settings: reset works');
select test.ok(get_setting('transfers.total_overdue_days') = 7, 'settings: reset restores the default');

-- ===== Dispatch cannot exceed what was approved ==================================
select test.as_user('asst_ebb');
select test.put('D', request_transfer(test.st('EBB'), test.st('ABJ'),
  jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 5)), 'test D', 'NORMAL'));
select test.as_user('mgr_ebb');
select approve_transfer(test.get('D'), jsonb_build_array(jsonb_build_object('item_id', test.line('D','C058'), 'quantity_approved', 5)), null);
select test.as_user('asst_ebb');
select test.fails(format($$select dispatch_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('D','C058'), 'quantity_dispatched', 1000)))$$, test.get('D')),
  'chk_balances_non_negative', 'dispatch: cannot send more than the source holds');
select test.as_root();
select test.eq_int(test.avail('EBB','C058'), 65, 'dispatch: a failed dispatch leaves stock untouched (atomic)');
select test.ok(test.status('D') = 'APPROVED', 'dispatch: a failed dispatch leaves the transfer APPROVED');
-- KNOWN ISSUE (reported, awaiting a decision): dispatch is not limited to the approved quantity.
select test.as_user('asst_ebb');
select test.known(not test.probe(format($$select dispatch_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('D','C058'), 'quantity_dispatched', 30)))$$, test.get('D'))),
  'dispatch: cannot send more than was approved (approved 5, 30 was accepted)');
select test.as_root();

-- ===== v_pending_transfers: overdue logic ========================================
select test.as_root();
insert into equipment_transfers (organization_id, from_station_id, to_station_id, requested_by, status, requested_at, received_at, updated_at)
select (select id from organizations limit 1), test.st('EBB'), test.st('ABJ'), test.uid('asst_ebb'), x.status, now() - x.age, now() - x.age, now() - x.age
from (values ('REQUESTED', interval '49 hours'), ('REQUESTED', interval '47 hours'),
             ('IN_TRANSIT', interval '8 days'), ('IN_TRANSIT', interval '6 days'),
             ('RECEIVED', interval '4 days'), ('RECEIVED', interval '2 days'),
             ('RECONCILIATION', interval '4 days')) as x(status, age);
select test.as_user('admin');
select test.eq_int((select count(*) from v_pending_transfers where is_overdue and status = 'REQUESTED'), 1, 'overdue: requested > 48h is overdue, < 48h is not');
select test.eq_int((select count(*) from v_pending_transfers where is_overdue and status = 'IN_TRANSIT'), 1, 'overdue: in transit > 7 days is overdue, < 7 days is not');
select test.eq_int((select count(*) from v_pending_transfers where is_overdue and status = 'RECEIVED' and overdue_kind = 'RECONCILE'), 1, 'overdue: received > 3 days is flagged RECONCILE');
select test.eq_int((select count(*) from v_pending_transfers where is_overdue and status = 'RECONCILIATION' and overdue_kind = 'CLOSE'), 1, 'overdue: reconciled > 3 days is flagged CLOSE');
select test.as_user('outsider');
select test.eq_int((select count(*) from v_pending_transfers), 0, 'overdue: a user with no roles sees no pending transfers');

select test.as_user('admin');
select test.eq_int((select sum(failures)::bigint from integrity_summary()), 0, 'integrity checks pass at the end of the run');
select test.finish('05_admin_rules.sql');
