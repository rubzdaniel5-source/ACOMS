-- Transfer safety: validation, retries, atomicity and row locking (migration 030).
create temp table if not exists b9(k text primary key, v int);
grant all on b9 to public;

-- Two EBB -> ABJ transfers, both dispatched. P: C058 x6 + C081 x4.  Q: C058 x2 (used for "foreign line" checks).
select test.as_user('asst_ebb');
select test.put('P', request_transfer(test.st('EBB'), test.st('ABJ'), jsonb_build_array(
  jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 6),
  jsonb_build_object('equipment_type_id', test.eq('C081'), 'quantity', 4)), 'safety P', 'NORMAL'));
select test.put('Q', request_transfer(test.st('EBB'), test.st('ABJ'), jsonb_build_array(
  jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 2)), 'safety Q', 'NORMAL'));

-- ---- Approval validation ----
select test.as_user('mgr_ebb');
select test.fails(format($$select approve_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('Q','C058'), 'quantity_approved', 2)), 'x')$$, test.get('P')),
  'does not belong', 'approve: a line from another transfer is refused');
select test.fails(format($$select approve_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('P','C058'), 'quantity_approved', -1)), 'x')$$, test.get('P')),
  'negative', 'approve: negative approved quantity is refused');
select test.fails(format($$select approve_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('P','C058'), 'quantity_approved', 99)), 'x')$$, test.get('P')),
  'more than requested', 'approve: approving more than was requested is refused');
select test.works(format($$select approve_transfer(%L, jsonb_build_array(
  jsonb_build_object('item_id', test.line('P','C058'), 'quantity_approved', 6),
  jsonb_build_object('item_id', test.line('P','C081'), 'quantity_approved', 4)), 'ok')$$, test.get('P')), 'approve P');
select test.works(format($$select approve_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('Q','C058'), 'quantity_approved', 2)), 'ok')$$, test.get('Q')), 'approve Q');

-- ---- Dispatch validation ----
select test.as_user('asst_ebb');
select test.fails(format($$select dispatch_transfer(%L, jsonb_build_array(
  jsonb_build_object('item_id', test.line('P','C058'), 'quantity_dispatched', 3),
  jsonb_build_object('item_id', test.line('P','C058'), 'quantity_dispatched', 3)))$$, test.get('P')),
  'listed once', 'dispatch: the same line listed twice is refused (no double posting)');
select test.as_root();
select test.eq_int((select coalesce(sum(quantity_dispatched),0) from equipment_transfer_items where transfer_id = test.get('P')), 0, 'dispatch: nothing recorded by the refused call');
select test.as_user('asst_ebb');
select test.works(format($$select dispatch_transfer(%L, jsonb_build_array(
  jsonb_build_object('item_id', test.line('P','C058'), 'quantity_dispatched', 6),
  jsonb_build_object('item_id', test.line('P','C081'), 'quantity_dispatched', 4)))$$, test.get('P')), 'dispatch P');
select test.fails(format($$select dispatch_transfer(%L, jsonb_build_array(
  jsonb_build_object('item_id', test.line('P','C058'), 'quantity_dispatched', 6),
  jsonb_build_object('item_id', test.line('P','C081'), 'quantity_dispatched', 4)))$$, test.get('P')),
  'must be APPROVED', 'dispatch: a repeated submission is refused');
select test.works(format($$select dispatch_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('Q','C058'), 'quantity_dispatched', 2)))$$, test.get('Q')), 'dispatch Q');
select test.as_root();
insert into b9 values ('abj058', test.avail('ABJ','C058')), ('abj081', test.avail('ABJ','C081'));

-- ---- Receipt validation ----
select test.as_user('asst_abj');
select test.fails(format($$select receive_transfer(%L, jsonb_build_array(
  jsonb_build_object('item_id', test.line('P','C058'), 'quantity_received', 7),
  jsonb_build_object('item_id', test.line('P','C081'), 'quantity_received', 4)))$$, test.get('P')),
  'exceeds', 'receive: more than was dispatched is refused (no stock created from nothing)');
select test.fails(format($$select receive_transfer(%L, jsonb_build_array(
  jsonb_build_object('item_id', test.line('P','C058'), 'quantity_received', -1),
  jsonb_build_object('item_id', test.line('P','C081'), 'quantity_received', 4)))$$, test.get('P')),
  'negative', 'receive: a negative quantity is refused');
select test.fails(format($$select receive_transfer(%L, jsonb_build_array(
  jsonb_build_object('item_id', test.line('P','C058'), 'quantity_received', 6),
  jsonb_build_object('item_id', test.line('Q','C058'), 'quantity_received', 2)))$$, test.get('P')),
  'does not belong', 'receive: a line from another transfer is refused');
select test.fails(format($$select receive_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('P','C058'), 'quantity_received', 6)))$$, test.get('P')),
  'every item', 'receive: every line must be counted');
select test.fails(format($$select receive_transfer(%L, jsonb_build_array(
  jsonb_build_object('item_id', test.line('P','C058'), 'quantity_received', 3),
  jsonb_build_object('item_id', test.line('P','C058'), 'quantity_received', 3),
  jsonb_build_object('item_id', test.line('P','C081'), 'quantity_received', 4)))$$, test.get('P')),
  'listed once', 'receive: the same line listed twice is refused');
-- Atomicity: line 1 is valid, line 2 is not. Nothing may be posted for line 1.
select test.fails(format($$select receive_transfer(%L, jsonb_build_array(
  jsonb_build_object('item_id', test.line('P','C058'), 'quantity_received', 6),
  jsonb_build_object('item_id', test.line('P','C081'), 'quantity_received', 40)))$$, test.get('P')),
  'exceeds', 'receive: a failure on a later line is refused');
select test.as_root();
select test.eq_int(test.avail('ABJ','C058'), (select v from b9 where k='abj058'), 'atomic: C058 at ABJ unchanged after refused receipts');
select test.eq_int(test.avail('ABJ','C081'), (select v from b9 where k='abj081'), 'atomic: C081 at ABJ unchanged after refused receipts');
select test.ok(test.status('P') = 'IN_TRANSIT', 'atomic: transfer still IN_TRANSIT');
select test.ok((select bool_and(quantity_received is null) from equipment_transfer_items where transfer_id = test.get('P')), 'atomic: no received quantity was saved');

-- Authorisation boundaries
select test.as_user('asst_ebb');
select test.fails(format($$select receive_transfer(%L, jsonb_build_array(
  jsonb_build_object('item_id', test.line('P','C058'), 'quantity_received', 6),
  jsonb_build_object('item_id', test.line('P','C081'), 'quantity_received', 4)))$$, test.get('P')),
  'destination station', 'receive: the sending side cannot receive');
select test.as_user('outsider');
select test.fails(format($$select receive_transfer(%L, jsonb_build_array(
  jsonb_build_object('item_id', test.line('P','C058'), 'quantity_received', 6),
  jsonb_build_object('item_id', test.line('P','C081'), 'quantity_received', 4)))$$, test.get('P')),
  'receive_transfer', 'receive: a user without the permission cannot receive');

-- Good receipt, then a retry
select test.as_user('asst_abj');
select test.works(format($$select receive_transfer(%L, jsonb_build_array(
  jsonb_build_object('item_id', test.line('P','C058'), 'quantity_received', 6),
  jsonb_build_object('item_id', test.line('P','C081'), 'quantity_received', 3)))$$, test.get('P')), 'receive: a correct count is accepted (C081 one short)');
select test.fails(format($$select receive_transfer(%L, jsonb_build_array(
  jsonb_build_object('item_id', test.line('P','C058'), 'quantity_received', 6),
  jsonb_build_object('item_id', test.line('P','C081'), 'quantity_received', 3)))$$, test.get('P')),
  'must be IN_TRANSIT', 'receive: a repeated submission is refused');
select test.as_root();
select test.eq_int(test.avail('ABJ','C058'), (select v from b9 where k='abj058') + 6, 'retry: C058 posted exactly once');
select test.eq_int(test.avail('ABJ','C081'), (select v from b9 where k='abj081') + 3, 'retry: C081 posted exactly once');

-- ---- Reconcile: duplicate lines would double-credit damaged units ----
select test.as_user('mgr_abj');
select test.fails(format($$select reconcile_transfer(%L, jsonb_build_array(
  jsonb_build_object('item_id', test.line('P','C081'), 'quantity_damaged', 0, 'quantity_missing', 1),
  jsonb_build_object('item_id', test.line('P','C081'), 'quantity_damaged', 0, 'quantity_missing', 1),
  jsonb_build_object('item_id', test.line('P','C058'), 'quantity_damaged', 0, 'quantity_missing', 0)), 'x')$$, test.get('P')),
  'listed once', 'reconcile: the same line listed twice is refused');
select test.as_root();
select test.ok(test.status('P') = 'RECEIVED', 'reconcile: refused call left the transfer RECEIVED');

-- ---- Row locking: every state-changing transfer function must lock the row ----
select test.ok((select bool_and(pg_get_functiondef(p.oid) ilike '%from equipment_transfers where id = p_transfer_id%for update%')
  from pg_proc p where p.pronamespace = 'public'::regnamespace
  and p.proname in ('approve_transfer','reject_transfer','dispatch_transfer','receive_transfer','reconcile_transfer','close_transfer','resolve_discrepancy','cancel_transfer')),
  'locking: all eight transfer functions lock the transfer row before checking its status');
select test.as_user('admin');
select test.eq_int((select sum(failures)::bigint from integrity_summary()), 0, 'integrity: no failures after the safety checks');
select test.finish('09_transfer_safety.sql');
