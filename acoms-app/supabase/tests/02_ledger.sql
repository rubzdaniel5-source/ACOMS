-- Inventory ledger: opening balances, lock-down of the write function, immutability.
select test.as_user('stores_ebb');
select test.works($$select record_opening_balances(test.st('EBB'),
  jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 100),
                    jsonb_build_object('equipment_type_id', test.eq('C081'), 'quantity', 50)), 'test opening')$$,
  'stores officer can record opening balances at own station');
select test.as_root();
select test.eq_int(test.avail('EBB','C058'), 100, 'opening balance sets available stock (C058)');
select test.eq_int(test.avail('EBB','C081'), 50,  'opening balance sets available stock (C081)');
select test.eq_int((select count(*) from inventory_transactions where transaction_type = 'OPENING_BALANCE'), 2, 'one ledger entry per line');

select test.as_user('stores_ebb');
select test.fails($$select record_opening_balances(test.st('EBB'),
  jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 5)), 'again')$$,
  '', 'a second opening balance for the same station and item is refused');
select test.fails($$select record_opening_balances(test.st('ABJ'),
  jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 5)), 'x')$$,
  'no access', 'cannot record opening balance at a station outside your scope');
select test.fails($$select record_opening_balances(test.st('LOS'),
  jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 5),
                    jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 6)), 'x')$$,
  '', 'duplicate item in one batch is refused');

select test.as_user('admin');
select test.fails($$select record_opening_balances(test.st('JUB'),
  jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 5)), 'x')$$,
  'turnaround', 'no-stock turnaround station cannot hold stock');
select test.fails($$select record_opening_balances(test.st('LOS'),
  jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 5),
                    jsonb_build_object('equipment_type_id', test.eq('C081'), 'quantity', 0)), 'x')$$,
  'positive', 'a zero quantity is refused');
select test.as_root();
select test.eq_int(test.avail('LOS','C058'), 0, 'a refused batch leaves no partial stock (atomic)');

select test.as_user('outsider');
select test.fails($$select record_opening_balances(test.st('EBB'),
  jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C1001'), 'quantity', 5)), 'x')$$,
  'denied', 'user without the permission cannot record opening balances');

-- The only door into the ledger is closed to signed-in users.
select test.as_user('admin');
select test.fails($$select apply_inventory_transaction(test.eq('C058'), test.st('EBB'), 'RECEIPT', 10)$$,
  'permission denied', 'signed-in admin cannot call apply_inventory_transaction directly');
select test.as_anon();
select test.fails($$select apply_inventory_transaction(test.eq('C058'), test.st('EBB'), 'RECEIPT', 10)$$,
  'permission denied', 'anonymous caller cannot call apply_inventory_transaction');
select test.as_user('admin');
update inventory_balances set available_quantity = 9999;
select test.as_root();
select test.eq_int(test.avail('EBB','C058'), 100, 'a direct UPDATE of balances changes nothing (no write policy)');

-- Immutability (even for the superuser path used by the app's service role)
select test.fails($$update inventory_transactions set quantity = 1$$, 'append-only', 'ledger rows cannot be modified');
select test.fails($$delete from inventory_transactions$$, 'append-only', 'ledger rows cannot be deleted');
select test.fails($$update audit_logs set action = 'x'$$, 'append-only', 'audit rows cannot be modified');
select test.fails($$delete from audit_logs$$, 'append-only', 'audit rows cannot be deleted');

-- Balance can never go negative
select test.fails($$select apply_inventory_transaction(test.eq('C058'), test.st('EBB'), 'TRANSFER_OUT', 101)$$,
  'chk_balances_non_negative', 'ledger refuses to take stock below zero');
select test.fails($$select apply_inventory_transaction(test.eq('C058'), test.st('EBB'), 'BOGUS', 1)$$,
  'Unrecognized', 'unknown transaction types are refused');
select test.fails($$select apply_inventory_transaction(test.eq('C058'), test.st('EBB'), 'RECEIPT', -1)$$,
  'positive magnitude', 'negative quantities are refused (sign is derived)');
select test.eq_int(test.avail('EBB','C058'), 100, 'failed ledger calls leave the balance untouched');
select test.finish('02_ledger.sql');
