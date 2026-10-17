-- Receipt with condition, partial receipt and held excess (migration 034).
create temp table if not exists b12(k text primary key, v int);
grant all on b12 to public;

select test.as_user('asst_ebb');
select test.put('R', request_transfer(test.st('EBB'), test.st('ABJ'), jsonb_build_array(
  jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 10),
  jsonb_build_object('equipment_type_id', test.eq('C081'), 'quantity', 5)), 'receipt condition', 'NORMAL'));
select test.as_user('mgr_ebb');
select approve_transfer(test.get('R'), jsonb_build_array(
  jsonb_build_object('item_id', test.line('R','C058'), 'quantity_approved', 10),
  jsonb_build_object('item_id', test.line('R','C081'), 'quantity_approved', 5)), 'ok');
select test.as_user('asst_ebb');
select dispatch_transfer(test.get('R'), jsonb_build_array(
  jsonb_build_object('item_id', test.line('R','C058'), 'quantity_dispatched', 10),
  jsonb_build_object('item_id', test.line('R','C081'), 'quantity_dispatched', 5)));
select test.as_root();
insert into b12 values ('a058', test.avail('ABJ','C058')), ('a081', test.avail('ABJ','C081'));

-- Partial receipt: 4 counted, 1 of them damaged
select test.as_user('asst_abj');
select test.fails(format($$select receive_transfer(%L, '[]'::jsonb, false)$$, test.get('R')), 'at least one item', 'partial: an empty partial receipt is refused');
select test.fails(format($$select receive_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('R','C058'), 'quantity_counted', 4, 'quantity_damaged', 5)), false)$$, test.get('R')), 'cannot exceed', 'partial: damaged cannot exceed counted');
select test.works(format($$select receive_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('R','C058'), 'quantity_counted', 4, 'quantity_damaged', 1)), false, 'first pallet')$$, test.get('R')), 'partial: first receipt recorded');
select test.as_root();
select test.ok(test.status('R') = 'PARTIALLY_RECEIVED', 'partial: transfer stays open as PARTIALLY_RECEIVED');
select test.eq_int(test.avail('ABJ','C058') - (select v from b12 where k='a058'), 3, 'partial: only the undamaged units are available');
select test.eq_int((select damaged_quantity from inventory_balances where station_id = test.st('ABJ') and equipment_type_id = test.eq('C058')), 1, 'partial: damaged unit is in the damaged bucket');
select test.ok(exists (select 1 from damage_reports where station_id = test.st('ABJ') and quantity = 1 and reason like 'Found damaged on receipt%'), 'partial: a damage report was opened');
select test.ok((select count(*) from v_pending_transfers where id = test.get('R')) = 1, 'partial: still on the open-transfers list');

-- Final receipt: C058 counted 7 (only 6 expected, so 1 excess); C081 counted 5
select test.as_user('mgr_abj');
select test.fails(format($$select receive_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('R','C058'), 'quantity_counted', 6)))$$, test.get('R')), 'must be counted', 'final: every item must be counted at the final receipt');
select test.works(format($$select receive_transfer(%L, jsonb_build_array(
  jsonb_build_object('item_id', test.line('R','C058'), 'quantity_counted', 7),
  jsonb_build_object('item_id', test.line('R','C081'), 'quantity_counted', 5)))$$, test.get('R')), 'final: receipt recorded');
select test.as_root();
select test.ok(test.status('R') = 'RECEIVED', 'final: transfer is RECEIVED');
select test.eq_int(test.avail('ABJ','C058') - (select v from b12 where k='a058'), 9, 'final: excess unit is NOT available (3 + 6 accepted)');
select test.eq_int((select held_quantity from inventory_balances where station_id = test.st('ABJ') and equipment_type_id = test.eq('C058')), 1, 'final: excess unit is in the held bucket');
select test.eq_int(test.avail('ABJ','C081') - (select v from b12 where k='a081'), 5, 'final: the other line is fully available');
select test.ok((select quantity_counted = 11 and quantity_received = 9 and quantity_damaged_on_receipt = 1 and quantity_excess_held = 1 and quantity_short = 0 and quantity_dispatched = 10
                 from equipment_transfer_items where id = test.line('R','C058')), 'evidence: counted, accepted, damaged, excess and dispatched all kept separately');
select test.eq_int((select count(*)::int from equipment_transfer_receipts where transfer_id = test.get('R')), 2, 'evidence: both receipts are kept');
select test.eq_int((select count(*)::int from equipment_transfer_receipt_lines rl join equipment_transfer_receipts r on r.id = rl.receipt_id where r.transfer_id = test.get('R')), 3, 'evidence: every counted line is kept');
select test.ok((select count(*) from excess_holds where transfer_id = test.get('R') and status = 'HELD' and quantity = 1) = 1, 'excess: a hold was opened');
select test.as_user('admin');
select test.eq_int((select sum(failures)::bigint from integrity_summary()), 0, 'integrity: balanced with a held unit');
select test.as_root();

-- Reconcile cannot close the books while excess is unexplained
select test.as_user('mgr_abj');
select test.works(format($$select reconcile_transfer(%L, jsonb_build_array(
  jsonb_build_object('item_id', test.line('R','C058'), 'quantity_damaged', 0, 'quantity_missing', 0),
  jsonb_build_object('item_id', test.line('R','C081'), 'quantity_damaged', 0, 'quantity_missing', 0)), 'checked')$$, test.get('R')), 'reconcile: runs');
select test.as_root();
select test.ok(test.status('R') = 'DISCREPANCY', 'reconcile: open excess keeps the transfer in DISCREPANCY');

-- Investigation then independent authorisation
select test.as_user('asst_abj');
select test.fails(format($$select record_excess_investigation(%L, 'looks like a mix-up')$$, (select id from excess_holds where transfer_id = test.get('R'))), 'reconcile_transfer', 'excess: an assistant cannot investigate');
select test.as_user('mgr_abj');
select test.fails(format($$select resolve_excess_hold(%L, 'ACCEPT_AS_STOCK', 'accept it please')$$, (select id from excess_holds where transfer_id = test.get('R'))), 'investigated', 'excess: cannot be resolved before investigation');
select test.fails(format($$select record_excess_investigation(%L, 'short')$$, (select id from excess_holds where transfer_id = test.get('R'))), 'at least 10', 'excess: findings are required');
select test.works(format($$select record_excess_investigation(%L, 'Checked the packing list; unit belongs to this load')$$, (select id from excess_holds where transfer_id = test.get('R'))), 'excess: investigation recorded');
select test.fails(format($$select resolve_excess_hold(%L, 'ACCEPT_AS_STOCK', 'accepting after review')$$, (select id from excess_holds where transfer_id = test.get('R'))), 'cannot authorise', 'excess: the investigator cannot authorise');
select test.as_user('admin');
select test.fails(format($$select resolve_discrepancy(%L, 'trying to skip the excess')$$, test.get('R')), 'still held', 'excess: the discrepancy cannot be resolved while excess is held');
select test.works(format($$select resolve_excess_hold(%L, 'ACCEPT_AS_STOCK', 'Packing list confirms an extra unit was loaded')$$, (select id from excess_holds where transfer_id = test.get('R'))), 'excess: an independent person authorises the treatment');
select test.as_root();
select test.eq_int((select held_quantity from inventory_balances where station_id = test.st('ABJ') and equipment_type_id = test.eq('C058')), 0, 'excess: held bucket is cleared');
select test.eq_int(test.avail('ABJ','C058') - (select v from b12 where k='a058'), 10, 'excess: accepted unit becomes available only now');
select test.as_user('admin');
select test.eq_int((select sum(failures)::bigint from integrity_summary()), 0, 'integrity: balanced after the excess is released');
select test.as_root();
select test.ok(exists (select 1 from audit_logs where action = 'excess.investigate') and exists (select 1 from audit_logs where action = 'excess.resolve'), 'audit: investigation and decision recorded');
select test.as_user('admin');
select test.works(format($$select resolve_discrepancy(%L, 'Excess investigated and accepted')$$, test.get('R')), 'discrepancy: can now be resolved');

select test.finish('12_receipt_condition.sql');
