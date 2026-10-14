-- Stock adjustments: two-person approval, ledger effect, stock-changed protection.
-- Stock at EBB before this file: C058 = 80, C081 = 30.

select test.as_user('stores_ebb');
select test.put('ADJ1', request_stock_adjustment(test.st('EBB'), test.eq('C058'), 'INCREASE', 5, 'COUNT_CORRECTION', 'Physical count found five extra'));
select test.fails($$select request_stock_adjustment(test.st('EBB'), test.eq('C058'), 'INCREASE', 5, 'COUNT_CORRECTION', 'short')$$,
  'at least 10', 'adjustment: a too-short explanation is refused');
select test.fails($$select request_stock_adjustment(test.st('EBB'), test.eq('C058'), 'INCREASE', 0, 'COUNT_CORRECTION', 'zero quantity here')$$,
  'greater than zero', 'adjustment: zero quantity is refused');
select test.fails($$select request_stock_adjustment(test.st('EBB'), test.eq('C058'), 'DECREASE', 500, 'WRITE_OFF', 'more than we hold here')$$,
  'Only 80 available', 'adjustment: cannot request a decrease larger than available stock');
select test.fails($$select request_stock_adjustment(test.st('JUB'), test.eq('C058'), 'INCREASE', 1, 'OTHER', 'turnaround station test')$$,
  'access', 'adjustment: station outside your scope is refused');
select test.as_user('admin');
select test.fails($$select request_stock_adjustment(test.st('JUB'), test.eq('C058'), 'INCREASE', 1, 'OTHER', 'turnaround station test')$$,
  'holds no stock', 'adjustment: no-stock turnaround station is refused');
select test.as_user('asst_ebb');
select test.fails($$select request_stock_adjustment(test.st('EBB'), test.eq('C058'), 'INCREASE', 1, 'OTHER', 'assistants cannot adjust')$$,
  'request_adjustment', 'adjustment: a role without request_adjustment cannot request');

-- Approval rules
select test.as_user('stores_ebb');
select test.fails(format($$select approve_stock_adjustment(%L)$$, test.get('ADJ1')), 'approve_adjustment', 'adjustment: stores officer cannot approve');
select test.as_user('mgr_abj');
select test.fails(format($$select approve_stock_adjustment(%L)$$, test.get('ADJ1')), 'no access', 'adjustment: approver must have access to the station');
select test.as_user('mgr_ebb');
select test.put('ADJ_SELF', request_stock_adjustment(test.st('EBB'), test.eq('C058'), 'INCREASE', 1, 'OTHER', 'my own request test'));
select test.fails(format($$select approve_stock_adjustment(%L)$$, test.get('ADJ_SELF')), 'you requested', 'adjustment: requester cannot approve their own');
select test.fails(format($$select reject_stock_adjustment(%L, 'nope')$$, test.get('ADJ_SELF')), 'you requested', 'adjustment: requester cannot reject their own');
select test.works(format($$select cancel_stock_adjustment(%L)$$, test.get('ADJ_SELF')), 'adjustment: requester can cancel their own');
select test.as_user('sup_ebb');
select test.fails(format($$select approve_stock_adjustment(%L)$$, test.get('ADJ_SELF')), 'already cancelled', 'adjustment: a cancelled request cannot be approved');
select test.as_user('stores_ebb');
select test.fails(format($$select cancel_stock_adjustment(%L)$$, test.get('ADJ1')), 'x', 'placeholder') where false;

select test.as_user('mgr_ebb');
select test.fails(format($$select cancel_stock_adjustment(%L)$$, test.get('ADJ1')), 'Only the requester', 'adjustment: only the requester can cancel');
select test.fails(format($$select reject_stock_adjustment(%L, '')$$, test.get('ADJ1')), 'reason', 'adjustment: rejecting needs a reason');
select test.works(format($$select approve_stock_adjustment(%L, 'verified')$$, test.get('ADJ1')), 'adjustment: a different manager can approve');
select test.as_root();
select test.eq_int(test.avail('EBB','C058'), 85, 'adjustment: approved increase adds to stock (80 -> 85)');
select test.eq_int((select count(*) from inventory_transactions where transaction_type = 'ADJUSTMENT' and quantity = 5), 1, 'adjustment: approval writes one ledger entry');
select test.eq_int((select balance_before from stock_adjustments where id = test.get('ADJ1')), 80, 'adjustment: balance_before recorded');
select test.eq_int((select balance_after from stock_adjustments where id = test.get('ADJ1')), 85, 'adjustment: balance_after recorded');
select test.as_user('sup_ebb');
select test.fails(format($$select approve_stock_adjustment(%L)$$, test.get('ADJ1')), 'already approved', 'adjustment: cannot be approved twice (no double ledger entry)');
select test.as_root();
select test.eq_int(test.avail('EBB','C058'), 85, 'adjustment: stock unchanged by the refused second approval');

-- Rejected requests never touch stock
select test.as_user('stores_ebb');
select test.put('ADJ2', request_stock_adjustment(test.st('EBB'), test.eq('C058'), 'DECREASE', 10, 'WRITE_OFF', 'Written off after audit'));
select test.as_user('sup_ebb');
select test.works(format($$select reject_stock_adjustment(%L, 'Not supported by evidence')$$, test.get('ADJ2')), 'adjustment: approver can reject with a reason');
select test.as_root();
select test.eq_int(test.avail('EBB','C058'), 85, 'adjustment: rejection leaves stock unchanged');
select test.as_user('mgr_ebb');
select test.fails(format($$select approve_stock_adjustment(%L)$$, test.get('ADJ2')), 'already rejected', 'adjustment: a rejected request cannot be approved');

-- Decrease, and the "stock changed since the request" guard
select test.as_user('stores_ebb');
select test.put('ADJ3', request_stock_adjustment(test.st('EBB'), test.eq('C058'), 'DECREASE', 80, 'WRITE_OFF', 'Large write off request'));
select test.put('ADJ4', request_stock_adjustment(test.st('EBB'), test.eq('C058'), 'DECREASE', 20, 'WRITE_OFF', 'Smaller write off request'));
select test.as_user('mgr_ebb');
select test.works(format($$select approve_stock_adjustment(%L)$$, test.get('ADJ4')), 'adjustment: approved decrease works (85 -> 65)');
select test.fails(format($$select approve_stock_adjustment(%L)$$, test.get('ADJ3')), 'Stock has changed', 'adjustment: approval is refused if stock fell since the request');
select test.as_root();
select test.eq_int(test.avail('EBB','C058'), 65, 'adjustment: stock is 65 after one decrease and one refusal');
select test.eq_int((select count(*) from inventory_transactions where transaction_type = 'ADJUSTMENT_DECREASE'), 1, 'adjustment: decrease uses the ADJUSTMENT_DECREASE ledger type');

select test.ok(exists (select 1 from audit_logs where action = 'adjustment.approve'), 'adjustment: approval is audited');
select test.ok(exists (select 1 from audit_logs where action = 'adjustment.reject'), 'adjustment: rejection is audited');
select test.ok(exists (select 1 from audit_logs where action = 'adjustment.request'), 'adjustment: request is audited');

-- Visibility: a user from another station cannot see the request
select test.as_user('mgr_abj');
select test.eq_int((select count(*) from stock_adjustments), 0, 'adjustment: ABJ manager cannot see EBB adjustments (RLS)');
select test.as_user('outsider');
select test.eq_int((select count(*) from stock_adjustments), 0, 'adjustment: a user with no roles sees none');

select test.as_user('admin');
select test.eq_int((select sum(failures)::bigint from integrity_summary()), 0, 'adjustment: integrity checks still pass');
select test.finish('04_adjustments.sql');
