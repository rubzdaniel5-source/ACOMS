-- Equipment transfer lifecycle, permissions, station scope and discrepancy rules.
-- Stock at EBB after 02_ledger: C058 = 100, C081 = 50.

-- ===== Scenario A: a clean transfer, EBB -> ABJ, C058 x 20 ====================
select test.as_user('asst_ebb');
select test.put('A', request_transfer(test.st('EBB'), test.st('ABJ'),
  jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 20)), 'test A', 'NORMAL'));
select test.as_root();
select test.ok(test.status('A') = 'REQUESTED', 'A: new transfer starts as REQUESTED');
select test.eq_int(test.avail('EBB','C058'), 100, 'A: requesting does not move stock');

select test.as_user('asst_ebb');
select test.fails(format($$select approve_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('A','C058'), 'quantity_approved', 20)), 'x')$$, test.get('A')),
  'approve_transfer', 'A: an assistant without approve permission cannot approve');
select test.fails(format($$select dispatch_transfer(%L, '[]'::jsonb)$$, test.get('A')),
  'must be APPROVED', 'A: cannot dispatch before approval');
select test.fails(format($$select receive_transfer(%L, '[]'::jsonb)$$, test.get('A')),
  'must be IN_TRANSIT', 'A: cannot receive before dispatch');

-- Requester cannot approve their own request (ADR-007): use a requester who also has the permission.
select test.as_user('mgr_ebb');
select test.put('A2', request_transfer(test.st('EBB'), test.st('ABJ'),
  jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 5)), 'self approve attempt', 'NORMAL'));
select test.fails(format($$select approve_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('A2','C058'), 'quantity_approved', 5)), 'x')$$, test.get('A2')),
  'ADR-007', 'A: requester cannot approve their own request');
select test.fails(format($$select reject_transfer(%L, 'no')$$, test.get('A2')),
  'ADR-007', 'A: requester cannot reject their own request either');
select test.as_user('sup_ebb');
select test.works(format($$select reject_transfer(%L, 'not needed')$$, test.get('A2')), 'A: a different approver can reject');
select test.as_root();
select test.ok(test.status('A2') = 'REJECTED', 'A: rejected transfer has status REJECTED');
select test.as_user('sup_ebb');
select test.fails(format($$select approve_transfer(%L, '[]'::jsonb, 'x')$$, test.get('A2')),
  'must be REQUESTED', 'A: a rejected transfer cannot be approved afterwards');

-- Station scope: the ABJ manager cannot approve a transfer leaving EBB.
select test.as_user('mgr_abj');
select test.fails(format($$select approve_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('A','C058'), 'quantity_approved', 20)), 'x')$$, test.get('A')),
  'source station', 'A: approver must have access to the SOURCE station');
select test.as_user('inactive');
select test.fails(format($$select approve_transfer(%L, '[]'::jsonb, 'x')$$, test.get('A')),
  'Missing permission', 'A: a deactivated user has no permissions');
select test.as_user('outsider');
select test.fails($$select request_transfer(test.st('EBB'), test.st('ABJ'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 1)), 'x', 'NORMAL')$$,
  'Missing permission', 'A: a user with no roles cannot request a transfer');
select test.as_user('asst_abj');
select test.fails($$select request_transfer(test.st('EBB'), test.st('ABJ'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 1)), 'x', 'NORMAL')$$,
  'No station access', 'A: cannot request a transfer out of a station you do not work at');
select test.fails($$select request_transfer(test.st('ABJ'), test.st('EBB'), '[]'::jsonb, 'x', 'NORMAL')$$,
  'at least one item', 'A: a transfer with no items is refused');

-- Approve, dispatch, receive, reconcile, close.
select test.as_user('mgr_ebb');
select test.works(format($$select approve_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('A','C058'), 'quantity_approved', 20)), 'ok')$$, test.get('A')),
  'A: a different manager can approve');
select test.as_user('mgr_ebb');
select test.fails(format($$select approve_transfer(%L, '[]'::jsonb, 'x')$$, test.get('A')),
  'must be REQUESTED', 'A: an approved transfer cannot be approved twice');

select test.as_user('asst_abj');
select test.fails(format($$select dispatch_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('A','C058'), 'quantity_dispatched', 20)))$$, test.get('A')),
  'source station', 'A: destination staff cannot dispatch from the source station');
select test.as_user('asst_ebb');
select test.works(format($$select dispatch_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('A','C058'), 'quantity_dispatched', 20)))$$, test.get('A')),
  'A: source assistant can dispatch');
select test.as_root();
select test.eq_int(test.avail('EBB','C058'), 80, 'A: dispatch takes stock out of the source (100 -> 80)');
select test.eq_int(test.bal('EBB','C058','in_transit_quantity'), 20, 'A: dispatched stock is shown in transit at the source');
select test.eq_int(test.avail('ABJ','C058'), 0, 'A: destination has nothing until it receives');

select test.as_user('asst_ebb');
select test.fails(format($$select receive_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('A','C058'), 'quantity_received', 20)))$$, test.get('A')),
  'destination station', 'A: source staff cannot confirm receipt at the destination');
select test.as_user('asst_abj');
select test.works(format($$select receive_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('A','C058'), 'quantity_received', 20)))$$, test.get('A')),
  'A: destination assistant can receive');
select test.as_root();
select test.eq_int(test.avail('ABJ','C058'), 20, 'A: receipt adds stock at the destination');

select test.as_user('asst_abj');
select test.fails(format($$select reconcile_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('A','C058'), 'quantity_damaged', 0, 'quantity_missing', 0)), 'x')$$, test.get('A')),
  'reconcile_transfer', 'A: an assistant cannot reconcile');
select test.fails(format($$select close_transfer(%L)$$, test.get('A')),
  'RECONCILIATION', 'A: cannot close before reconciliation');
select test.as_user('mgr_abj');
select test.ok((select reconcile_transfer(test.get('A'), jsonb_build_array(jsonb_build_object('item_id', test.line('A','C058'), 'quantity_damaged', 0, 'quantity_missing', 0)), 'all good')) = 'RECONCILIATION',
  'A: a fully matching transfer reconciles straight to RECONCILIATION');
select test.works(format($$select close_transfer(%L)$$, test.get('A')), 'A: reconciled transfer can be closed');
select test.as_root();
select test.eq_int(test.bal('EBB','C058','in_transit_quantity'), 0, 'A: nothing left in transit after close');
select test.ok(test.status('A') = 'CLOSED', 'A: status is CLOSED');
select test.as_user('mgr_abj');
select test.fails(format($$select close_transfer(%L)$$, test.get('A')), 'RECONCILIATION', 'A: a closed transfer cannot be closed again');

-- ===== Scenario B: unexplained difference blocks closing =======================
-- C081 has tolerance 2. Send 10, receive 6, claim nothing damaged/missing => 4 unexplained.
select test.as_user('asst_ebb');
select test.put('B', request_transfer(test.st('EBB'), test.st('ABJ'),
  jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C081'), 'quantity', 10)), 'test B', 'NORMAL'));
select test.as_user('mgr_ebb');
select approve_transfer(test.get('B'), jsonb_build_array(jsonb_build_object('item_id', test.line('B','C081'), 'quantity_approved', 10)), null);
select test.as_user('asst_ebb');
select dispatch_transfer(test.get('B'), jsonb_build_array(jsonb_build_object('item_id', test.line('B','C081'), 'quantity_dispatched', 10)));
select test.as_user('asst_abj');
select receive_transfer(test.get('B'), jsonb_build_array(jsonb_build_object('item_id', test.line('B','C081'), 'quantity_received', 6)));
select test.as_user('mgr_abj');
select test.ok((select reconcile_transfer(test.get('B'), jsonb_build_array(jsonb_build_object('item_id', test.line('B','C081'), 'quantity_damaged', 0, 'quantity_missing', 0)), 'short')) = 'DISCREPANCY',
  'B: difference beyond tolerance puts the transfer in DISCREPANCY');
select test.fails(format($$select close_transfer(%L)$$, test.get('B')), 'RECONCILIATION', 'B: a discrepancy cannot be closed');
select test.fails(format($$select resolve_discrepancy(%L, '  ')$$, test.get('B')), 'reason', 'B: resolving needs a written reason');
select test.as_user('asst_abj');
select test.fails(format($$select resolve_discrepancy(%L, 'because')$$, test.get('B')), 'reconcile_transfer', 'B: an assistant cannot resolve a discrepancy');
select test.as_user('mgr_abj');
select test.works(format($$select resolve_discrepancy(%L, 'Investigated: stock left at EBB dock')$$, test.get('B')), 'B: a reconciler can resolve it with a reason');
select test.works(format($$select close_transfer(%L)$$, test.get('B')), 'B: then it can be closed');

-- ===== Scenario C: damaged and missing are explained, tolerance respected =======
select test.as_user('asst_ebb');
select test.put('C', request_transfer(test.st('EBB'), test.st('ABJ'),
  jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C081'), 'quantity', 10)), 'test C', 'NORMAL'));
select test.as_user('mgr_ebb');
select approve_transfer(test.get('C'), jsonb_build_array(jsonb_build_object('item_id', test.line('C','C081'), 'quantity_approved', 10)), null);
select test.as_user('asst_ebb');
select dispatch_transfer(test.get('C'), jsonb_build_array(jsonb_build_object('item_id', test.line('C','C081'), 'quantity_dispatched', 10)));
select test.as_user('asst_abj');
select receive_transfer(test.get('C'), jsonb_build_array(jsonb_build_object('item_id', test.line('C','C081'), 'quantity_received', 7)));
select test.as_user('mgr_abj');
select test.ok((select reconcile_transfer(test.get('C'), jsonb_build_array(jsonb_build_object('item_id', test.line('C','C081'), 'quantity_damaged', 1, 'quantity_missing', 2)), 'explained')) = 'RECONCILIATION',
  'C: 10 sent = 7 received + 1 damaged + 2 missing reconciles');
select test.as_root();
-- KNOWN ISSUE (reported, awaiting a decision): reconcile_transfer debits DAMAGE/LOSS from the
-- destination's AVAILABLE stock, but those units were never received into it, so they are
-- deducted twice, and the damaged/missing buckets are never filled. ABJ should hold 6 + 7 = 13.
select test.known(test.avail('ABJ','C081') = 13, 'C: destination available stock is not double-deducted for damaged/missing units (got ' || test.avail('ABJ','C081') || ', expected 13)');
select test.known(test.bal('ABJ','C081','damaged_quantity') = 1, 'C: the damaged unit appears in the damaged bucket');
select test.known(test.bal('ABJ','C081','missing_quantity') = 2, 'C: the missing units appear in the missing bucket');
select test.eq_int(test.bal('EBB','C081','in_transit_quantity'), 0, 'C: in-transit is cleared at the source');

-- ===== Whole-system consistency =================================================
select test.as_user('admin');
select test.eq_int((select sum(failures)::bigint from integrity_summary()), 0, 'integrity checks all pass after three full transfers');
select test.as_root();
select test.ok(exists (select 1 from audit_logs where action = 'transfer.approve'), 'audit rows exist for approvals');
select test.ok(exists (select 1 from audit_logs where action = 'transfer.dispatch'), 'audit rows exist for dispatches');
select test.ok(exists (select 1 from audit_logs where action = 'transfer.close'), 'audit rows exist for closes');


select 1;
select test.finish('03_transfers.sql');
