-- Cancel a transfer, and book new stock received (posts as RECEIPT).
select test.as_root();
create temp table if not exists base(k text primary key, v int);
grant all on base to public;
insert into base values ('c058', test.avail('EBB','C058'));

-- ---- Cancel: REQUESTED, by the requester ----
select test.as_user('asst_ebb');
select test.put('X1', request_transfer(test.st('EBB'), test.st('ABJ'),
  jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 4)), 'cancel test 1', 'NORMAL'));
select test.fails(format($$select cancel_transfer(%L, '')$$, test.get('X1')), 'reason', 'cancel: a reason is required');
select test.as_user('outsider');
select test.fails(format($$select cancel_transfer(%L, 'not mine to cancel')$$, test.get('X1')), 'Only the requester', 'cancel: an outsider cannot cancel');
select test.as_user('asst_abj');
select test.fails(format($$select cancel_transfer(%L, 'wrong station user')$$, test.get('X1')), 'Only the requester', 'cancel: a user at another station cannot cancel');
select test.as_user('asst_ebb');
select test.works(format($$select cancel_transfer(%L, 'Raised in error')$$, test.get('X1')), 'cancel: the requester can withdraw a requested transfer');
select test.as_root();
select test.ok(test.status('X1') = 'CANCELLED', 'cancel: status is CANCELLED');
select test.ok((select cancel_reason from equipment_transfers where id = test.get('X1')) = 'Raised in error', 'cancel: reason stored');
select test.eq_int(test.avail('EBB','C058'), (select v from base where k='c058'), 'cancel: stock unchanged');
select test.ok(exists (select 1 from audit_logs where action = 'transfer.cancel' and entity_id = test.get('X1')), 'cancel: audited');
select test.as_user('mgr_ebb');
select test.fails(format($$select cancel_transfer(%L, 'again')$$, test.get('X1')), 'requested or approved', 'cancel: cannot cancel twice');
select test.fails(format($$select approve_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('X1','C058'), 'quantity_approved', 4)), 'x')$$, test.get('X1')), 'REQUESTED', 'cancel: a cancelled transfer cannot be approved');

-- ---- Cancel: APPROVED ----
select test.as_user('stores_ebb');
select test.put('X2', request_transfer(test.st('EBB'), test.st('ABJ'),
  jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 3)), 'cancel test 2', 'NORMAL'));
select test.as_user('mgr_ebb');
select test.works(format($$select approve_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('X2','C058'), 'quantity_approved', 3)), 'ok')$$, test.get('X2')), 'cancel: approve X2');
select test.as_user('stores_ebb');
select test.fails(format($$select cancel_transfer(%L, 'requester wants out')$$, test.get('X2')), 'approver', 'cancel: requester cannot cancel once approved');
select test.as_user('mgr_ebb');
select test.works(format($$select cancel_transfer(%L, 'No longer needed at ABJ')$$, test.get('X2')), 'cancel: an approver can cancel an approved transfer');
select test.fails(format($$select dispatch_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('X2','C058'), 'quantity_dispatched', 3)))$$, test.get('X2')), 'APPROVED', 'cancel: a cancelled transfer cannot be dispatched');
select test.as_root();
select test.eq_int(test.avail('EBB','C058'), (select v from base where k='c058'), 'cancel: stock still unchanged');

-- ---- Cancel after dispatch is refused ----
select test.as_user('stores_ebb');
select test.put('X3', request_transfer(test.st('EBB'), test.st('ABJ'),
  jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 2)), 'cancel test 3', 'NORMAL'));
select test.as_user('mgr_ebb');
select approve_transfer(test.get('X3'), jsonb_build_array(jsonb_build_object('item_id', test.line('X3','C058'), 'quantity_approved', 2)), 'ok');
select dispatch_transfer(test.get('X3'), jsonb_build_array(jsonb_build_object('item_id', test.line('X3','C058'), 'quantity_dispatched', 2)));
select test.fails(format($$select cancel_transfer(%L, 'too late')$$, test.get('X3')), 'requested or approved', 'cancel: refused after dispatch');

-- ---- New stock received ----
select test.as_user('stores_ebb');
select test.fails($$select request_stock_adjustment(test.st('EBB'), test.eq('C081'), 'DECREASE', 1, 'NEW_STOCK_RECEIVED', 'new stock cannot decrease')$$, 'only increase', 'receipt: decrease is refused');
select test.put('R1', request_stock_adjustment(test.st('EBB'), test.eq('C081'), 'INCREASE', 12, 'NEW_STOCK_RECEIVED', 'Purchase order delivery, 12 units'));
select test.as_root();
insert into base values ('c081', test.avail('EBB','C081'));
select test.as_user('stores_ebb');
select test.fails(format($$select approve_stock_adjustment(%L)$$, test.get('R1')), 'approve_adjustment', 'receipt: requester role cannot approve');
select test.as_user('mgr_ebb');
select test.works(format($$select approve_stock_adjustment(%L, 'delivery note seen')$$, test.get('R1')), 'receipt: a second person approves');
select test.as_root();
select test.eq_int(test.avail('EBB','C081'), (select v from base where k='c081') + 12, 'receipt: stock increased by 12');
select test.eq_int((select count(*) from inventory_transactions where transaction_type = 'RECEIPT' and quantity = 12 and equipment_type_id = test.eq('C081')), 1, 'receipt: posted to the ledger as RECEIPT');
select test.eq_int((select count(*) from inventory_transactions where transaction_type = 'ADJUSTMENT' and quantity = 12), 0, 'receipt: not posted as ADJUSTMENT');
select test.as_user('admin');
select test.eq_int((select sum(failures)::bigint from integrity_summary()), 0, 'integrity: no failures after cancel and receipt');
select test.finish('08_cancel_and_receipts.sql');
