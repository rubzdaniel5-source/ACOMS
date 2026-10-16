-- Exchange cases: outbound and return legs, closure rules, close-without-return exception.
-- NBO is a stock-holding outstation with its own staff; UR200 flies EBB-NBO daily, UR201 NBO-EBB daily.
create temp table if not exists b11(k text primary key, v int);
grant all on b11 to public;

-- ---- Starting an exchange ----
select test.as_user('asst_nbo');
select test.fails(format($$select create_exchange(test.st('NBO'), '[]'::jsonb, 'x', 'NORMAL', 'UR200', %L)$$, test.nextdow(5)), 'hub', 'start: outstation staff cannot start an exchange from the hub');
select test.as_user('asst_ebb');
select test.fails(format($$select create_exchange(test.st('ZNZ'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 5)), 'x', 'NORMAL', 'UR334', %L)$$, test.nextdow(6)), 'holds no stock', 'start: a no-stock turnaround station cannot take part');
select test.fails(format($$select create_exchange(test.st('EBB'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 5)), 'x', 'NORMAL', 'UR200', %L)$$, test.nextdow(5)), 'not the hub', 'start: the destination cannot be the hub');
select test.fails($$select create_exchange(test.st('NBO'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 5)), 'x', 'NORMAL', '', null)$$, 'flight', 'start: a flight is required');
select test.fails(format($$select create_exchange(test.st('NBO'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 5)), 'x', 'NORMAL', 'UR120', %L)$$, test.nextdow(5)), 'No scheduled flight', 'start: a flight that does not serve the route is refused');
select test.as_root();
select test.eq_int((select count(*) from equipment_exchanges), 0, 'start: refused attempts created nothing');
select test.as_user('asst_ebb');
select test.put('X', create_exchange(test.st('NBO'), jsonb_build_array(
  jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 10),
  jsonb_build_object('equipment_type_id', test.eq('C081'), 'quantity', 6)), 'exchange test', 'NORMAL', 'ur200', test.nextdow(5), 'key-1'));
select test.ok(create_exchange(test.st('NBO'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 10)), 'exchange test', 'NORMAL', 'UR200', test.nextdow(5), 'key-1') = test.get('X'), 'start: a repeated submission returns the same exchange');
select test.as_root();
select test.eq_int((select count(*) from equipment_exchanges), 1, 'start: still exactly one exchange');
select test.put('XO', (select id from equipment_transfers where exchange_id = test.get('X') and exchange_leg = 'OUTBOUND'));
select test.ok((select flight_number = 'UR200' and status = 'REQUESTED' from equipment_transfers where id = test.get('XO')), 'start: outbound movement is created with its flight');
select test.ok((select status = 'OUTBOUND' and next_action = 'Approve the outbound movement' and next_station_code = 'EBB' from v_equipment_exchanges where id = test.get('X')), 'state: outbound awaiting approval at the hub');

-- ---- Outbound leg runs through the normal rules ----
select test.as_user('asst_ebb');
select test.fails(format($$select approve_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('XO','C058'), 'quantity_approved', 10)), 'x')$$, test.get('XO')), 'approve_transfer', 'outbound: the requester role cannot approve');
select test.as_user('mgr_ebb');
select test.works(format($$select approve_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('XO','C058'), 'quantity_approved', 10), jsonb_build_object('item_id', test.line('XO','C081'), 'quantity_approved', 6)), 'ok')$$, test.get('XO')), 'outbound: approved');
select test.as_user('asst_ebb');
select test.works(format($$select dispatch_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('XO','C058'), 'quantity_dispatched', 10), jsonb_build_object('item_id', test.line('XO','C081'), 'quantity_dispatched', 6)))$$, test.get('XO')), 'outbound: dispatched');
select test.as_user('asst_nbo');
select test.fails(format($$select start_exchange_return(%L, jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 1)), 'early', 'NORMAL', 'UR201', %L)$$, test.get('X'), test.nextdow(5)), 'only after it has received', 'return: cannot start before the outstation has received the outbound');
select test.works(format($$select receive_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('XO','C058'), 'quantity_received', 10), jsonb_build_object('item_id', test.line('XO','C081'), 'quantity_received', 5)))$$, test.get('XO')), 'outbound: received independently (C081 one short)');
select test.as_root();
select test.eq_int(test.avail('NBO','C058'), 10, 'outbound: NBO holds the 10 it counted');
select test.eq_int(test.avail('NBO','C081'), 5, 'outbound: NBO holds only the 5 it counted');

-- ---- Return leg: different items and quantities from the outbound ----
select test.as_user('mgr_ebb');
select test.fails(format($$select start_exchange_return(%L, jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 1)), 'x', 'NORMAL', 'UR201', %L)$$, test.get('X'), test.nextdow(5)), 'No station access to the outstation', 'return: hub staff cannot record the outstation''s return');
select test.as_user('asst_nbo');
select test.fails(format($$select start_exchange_return(%L, jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 4)), 'x', 'NORMAL', 'UR200', %L)$$, test.get('X'), test.nextdow(5)), 'No scheduled flight', 'return: the outbound flight cannot be used for the return route');
select test.put('XR', start_exchange_return(test.get('X'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 4)), 'returning soiled stock', 'NORMAL', 'UR201', test.nextdow(5)));
select test.fails(format($$select start_exchange_return(%L, jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 1)), 'again', 'NORMAL', 'UR201', %L)$$, test.get('X'), test.nextdow(5)), 'already has a return', 'return: only one active return per exchange');
select test.as_root();
select test.ok((select exchange_leg = 'RETURN' and from_station_id = test.st('NBO') and to_station_id = test.st('EBB') from equipment_transfers where id = test.get('XR')), 'return: runs NBO to EBB');
select test.ok((select return_flight = 'UR201' and status = 'RETURN_IN_PROGRESS' and next_action = 'Approve the return movement' from v_equipment_exchanges where id = test.get('X')), 'state: return in progress, awaiting approval');

-- ---- Closure rules ----
select test.as_user('mgr_ebb');
select test.fails(format($$select close_exchange(%L)$$, test.get('X')), 'outbound movement must be reconciled', 'close: refused while the outbound is open');
select test.as_user('mgr_nbo');
select test.works(format($$select reconcile_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('XO','C058'), 'quantity_damaged', 0, 'quantity_missing', 0), jsonb_build_object('item_id', test.line('XO','C081'), 'quantity_damaged', 0, 'quantity_missing', 1)), 'one short')$$, test.get('XO')), 'outbound: reconciled with the shortage reported as missing (not a confirmed loss)');
select test.as_root();
select test.ok(test.status('XO') = 'RECONCILIATION', 'outbound: explained difference moves to RECONCILIATION');
select test.ok(exists (select 1 from loss_reports where quantity = 1 and circumstances like 'Not received%'), 'outbound: shortage is an open loss report, not an automatic write-off');
select test.as_user('mgr_nbo');
select test.works(format($$select close_transfer(%L)$$, test.get('XO')), 'outbound: closed');
select test.as_user('mgr_ebb');
select test.fails(format($$select close_exchange(%L)$$, test.get('X')), 'return movement must be reconciled', 'close: refused while the return is open');
-- run the return leg
select test.fails(format($$select approve_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('XR','C058'), 'quantity_approved', 4)), 'ok')$$, test.get('XR')), 'source station', 'return: the hub manager cannot approve a movement leaving the outstation');
select test.as_user('mgr_nbo');
select test.works(format($$select approve_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('XR','C058'), 'quantity_approved', 4)), 'ok')$$, test.get('XR')), 'return: outstation manager approves (not the requester)');
select test.as_user('asst_nbo');
select test.works(format($$select dispatch_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('XR','C058'), 'quantity_dispatched', 4)))$$, test.get('XR')), 'return: dispatched from the outstation');
select test.as_root();
select test.eq_int(test.avail('NBO','C058'), 6, 'return: NBO stock reduced (10 - 4)');
select test.as_user('asst_ebb');
select test.works(format($$select receive_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('XR','C058'), 'quantity_received', 4)))$$, test.get('XR')), 'return: received independently at the hub');
select test.as_user('mgr_ebb');
select test.fails(format($$select close_exchange(%L)$$, test.get('X')), 'return movement must be reconciled', 'close: refused until the return is reconciled and closed');
select test.works(format($$select reconcile_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('XR','C058'), 'quantity_damaged', 0, 'quantity_missing', 0)), 'all good')$$, test.get('XR')), 'return: reconciled');
select test.works(format($$select close_transfer(%L)$$, test.get('XR')), 'return: closed');
select test.as_user('asst_ebb');
select test.fails(format($$select close_exchange(%L)$$, test.get('X')), 'reconcile_transfer', 'close: needs the reconcile permission');
select test.as_user('mgr_ebb');
select test.works(format($$select close_exchange(%L, 'both legs closed')$$, test.get('X')), 'close: allowed once both legs are closed');
select test.fails(format($$select close_exchange(%L)$$, test.get('X')), 'already closed', 'close: cannot be closed twice');
select test.as_root();
select test.ok((select status = 'CLOSED' and not has_open_discrepancy from v_equipment_exchanges where id = test.get('X')), 'state: exchange shows CLOSED');
select test.eq_int((select quantity_dispatched from equipment_transfer_items where id = test.line('XO','C081')), 6, 'evidence: dispatched figure kept after reconciliation');
select test.eq_int((select quantity_received from equipment_transfer_items where id = test.line('XO','C081')), 5, 'evidence: received figure kept after reconciliation');

-- ---- Close without a return (exception) ----
select test.as_user('asst_ebb');
select test.put('Y', create_exchange(test.st('NBO'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 3)), 'no-return test', 'NORMAL', 'UR200', test.nextdow(6)));
select test.put('YO', (select id from equipment_transfers where exchange_id = test.get('Y') and exchange_leg = 'OUTBOUND'));
select test.as_user('mgr_ebb');
select approve_transfer(test.get('YO'), jsonb_build_array(jsonb_build_object('item_id', test.line('YO','C058'), 'quantity_approved', 3)), 'ok');
select test.as_user('asst_ebb');
select dispatch_transfer(test.get('YO'), jsonb_build_array(jsonb_build_object('item_id', test.line('YO','C058'), 'quantity_dispatched', 3)));
select test.as_user('asst_nbo');
select receive_transfer(test.get('YO'), jsonb_build_array(jsonb_build_object('item_id', test.line('YO','C058'), 'quantity_received', 3)));
select test.as_user('mgr_nbo');
select reconcile_transfer(test.get('YO'), jsonb_build_array(jsonb_build_object('item_id', test.line('YO','C058'), 'quantity_damaged', 0, 'quantity_missing', 0)), 'ok');
select close_transfer(test.get('YO'));
select test.fails(format($$select close_exchange(%L)$$, test.get('Y')), 'No return movement', 'exception: a normal close is refused with no return recorded');
select test.as_root();
select test.ok((select status = 'AWAITING_RETURN' and next_action = 'Record the return movement' from v_equipment_exchanges where id = test.get('Y')), 'state: awaiting the return');
select test.as_user('mgr_ebb');
select test.fails(format($$select request_exchange_no_return(%L, 'short')$$, test.get('Y')), 'at least 10', 'exception: a real reason is required');
select test.works(format($$select request_exchange_no_return(%L, 'Outstation keeps the equipment for the charter programme')$$, test.get('Y')), 'exception: request recorded');
select test.fails(format($$select decide_exchange_no_return(%L, true, 'approved')$$, test.get('Y')), 'cannot decide', 'exception: the requester cannot approve their own request');
select test.fails(format($$select request_exchange_no_return(%L, 'Outstation keeps the equipment for the charter programme')$$, test.get('Y')), 'already waiting', 'exception: only one pending request');
select test.as_user('asst_nbo');
select test.fails(format($$select start_exchange_return(%L, jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 1)), 'x', 'NORMAL', 'UR201', %L)$$, test.get('Y'), test.nextdow(6)), 'waiting for a decision', 'exception: a return cannot start while the request is pending');
select test.as_user('asst_ebb');
select test.fails(format($$select decide_exchange_no_return(%L, true, 'approved')$$, test.get('Y')), 'approve_transfer', 'exception: a role without approval rights cannot decide');
select test.as_user('sup_ebb');
select test.fails(format($$select decide_exchange_no_return(%L, false, '')$$, test.get('Y')), 'note is required', 'exception: a decision needs a note');
select test.works(format($$select decide_exchange_no_return(%L, false, 'Not enough justification, return it')$$, test.get('Y')), 'exception: an independent approver can reject');
select test.as_user('mgr_ebb');
select test.works(format($$select request_exchange_no_return(%L, 'Operations confirmed the equipment stays at NBO permanently')$$, test.get('Y')), 'exception: can be requested again after a rejection');
select test.as_user('sup_ebb');
select test.works(format($$select decide_exchange_no_return(%L, true, 'Confirmed with operations')$$, test.get('Y')), 'exception: an independent approver can approve');
select test.as_root();
select test.ok((select status = 'CLOSED_NO_RETURN' and close_kind = 'NO_RETURN_EXCEPTION' and close_note like 'Operations confirmed%' from v_equipment_exchanges where id = test.get('Y')), 'exception: exchange closes as CLOSED_NO_RETURN with the reason kept');
select test.as_user('asst_nbo');
select test.fails(format($$select start_exchange_return(%L, jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 1)), 'x', 'NORMAL', 'UR201', %L)$$, test.get('Y'), test.nextdow(6)), 'already closed', 'exception: no return can be added to a closed exchange');

-- ---- Cancel before dispatch ----
select test.as_user('asst_ebb');
select test.put('Z', create_exchange(test.st('NBO'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 2)), 'cancel test', 'NORMAL', 'UR200', test.nextdow(7)));
select test.put('ZO', (select id from equipment_transfers where exchange_id = test.get('Z') and exchange_leg = 'OUTBOUND'));
select test.works(format($$select cancel_transfer(%L, 'Raised in error')$$, test.get('ZO')), 'cancel: the outbound can be withdrawn before dispatch');
select test.as_root();
select test.ok((select status = 'CANCELLED' and next_action is null from v_equipment_exchanges where id = test.get('Z')), 'cancel: the exchange reads as cancelled');
select test.as_user('asst_nbo');
select test.fails(format($$select start_exchange_return(%L, jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 1)), 'x', 'NORMAL', 'UR201', %L)$$, test.get('Z'), test.nextdow(7)), 'no active outbound', 'cancel: a cancelled exchange cannot get a return');

-- ---- Visibility, audit, integrity ----
select test.as_user('asst_abj');
select test.eq_int((select count(*) from v_equipment_exchanges), 0, 'visibility: staff at an unrelated station see no exchanges');
select test.as_user('outsider');
select test.eq_int((select count(*) from v_equipment_exchanges), 0, 'visibility: a user with no role sees none');
select test.as_user('asst_nbo');
select test.ok((select count(*) from v_equipment_exchanges) >= 3, 'visibility: the outstation sees its own exchanges');
select test.as_root();
select test.ok(exists (select 1 from audit_logs where action = 'exchange.create') and exists (select 1 from audit_logs where action = 'exchange.return_start')
  and exists (select 1 from audit_logs where action = 'exchange.close') and exists (select 1 from audit_logs where action = 'exchange.no_return_request')
  and exists (select 1 from audit_logs where action = 'exchange.no_return_approve') and exists (select 1 from audit_logs where action = 'exchange.no_return_reject'), 'audit: exchange actions are recorded');
select test.as_user('admin');
select test.eq_int((select sum(failures)::bigint from integrity_summary()), 0, 'integrity: no failures after exchange cases');
select test.finish('11_exchange_cases.sql');
