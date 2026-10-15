-- Damage and loss workflow, retire permission, station scope, trolleys as batches.

-- ===== Trolleys are counted in batches by type ===================================
select test.ok((select bool_and(tracking_method = 'BATCH') from equipment_types where source_code in ('R052','R053')), 'trolleys: full and half size are tracked in batches, not one by one');
select test.as_user('stores_ebb');
select test.works($$select record_opening_balances(test.st('EBB'), jsonb_build_array(
  jsonb_build_object('equipment_type_id', test.eq('R052'), 'quantity', 14), jsonb_build_object('equipment_type_id', test.eq('R053'), 'quantity', 6)), 'trolley opening')$$,
  'trolleys: opening stock is entered as counts per type');
select test.as_root();
select test.eq_int(test.avail('EBB','R052'), 14, 'trolleys: full-size count recorded');
select test.eq_int(test.avail('EBB','R053'), 6, 'trolleys: half-size count recorded');

-- ===== Damage: repair path ========================================================
select test.as_user('asst_ebb');
select test.put('DM1', report_damage(test.eq('C058'), test.st('EBB'), 3, 'Cracked in wash'));
select test.as_root();
select test.eq_int(test.avail('EBB','C058'), 62, 'damage: reporting moves stock out of available (65 -> 62)');
select test.eq_int(test.bal('EBB','C058','damaged_quantity'), 3, 'damage: and into the damaged bucket');

select test.as_user('asst_abj');
select test.fails(format($$select start_damage_review(%L)$$, test.get('DM1')), 'station access', 'damage: staff at another station cannot move this report along');
select test.as_user('outsider');
select test.fails(format($$select start_damage_review(%L)$$, test.get('DM1')), 'station access', 'damage: a user with no roles cannot');
select test.as_user('asst_ebb');
select test.works(format($$select start_damage_review(%L)$$, test.get('DM1')), 'damage: own-station assistant can start the review');
select test.fails(format($$select assess_damage(%L, 'RETIRE', 'beyond repair')$$, test.get('DM1')), 'retire_equipment', 'damage: an assistant cannot assess a report as RETIRE');
select test.works(format($$select assess_damage(%L, 'REPAIRABLE', 'minor')$$, test.get('DM1')), 'damage: an assistant can assess as repairable');
select test.works(format($$select start_repair(%L)$$, test.get('DM1')), 'damage: repair can start');
select test.works(format($$select return_to_service(%L)$$, test.get('DM1')), 'damage: repaired equipment returns to service');
select test.as_root();
select test.eq_int(test.avail('EBB','C058'), 65, 'damage: returned stock is available again (62 -> 65)');
select test.eq_int(test.bal('EBB','C058','damaged_quantity'), 0, 'damage: damaged bucket is empty again');

-- ===== Damage: retirement needs a manager or supervisor =============================
select test.as_user('asst_ebb');
select test.put('DM2', report_damage(test.eq('R052'), test.st('EBB'), 2, 'Frame bent beyond repair'));
select start_damage_review(test.get('DM2'));
select test.as_user('mgr_abj');
select test.fails(format($$select assess_damage(%L, 'RETIRE', 'x')$$, test.get('DM2')), 'station access', 'retire: a manager from another station cannot assess it');
select test.as_user('sup_ebb');
select test.works(format($$select assess_damage(%L, 'RETIRE', 'Frame bent beyond repair')$$, test.get('DM2')), 'retire: a catering supervisor can assess a report as RETIRE');
select test.as_user('asst_ebb');
select test.fails(format($$select retire_equipment(%L)$$, test.get('DM2')), 'retire_equipment', 'retire: an assistant cannot retire equipment');
select test.as_user('sup_ebb');
select test.works(format($$select retire_equipment(%L)$$, test.get('DM2')), 'retire: a catering supervisor can retire equipment');
select test.as_user('sup_ebb');
select test.fails(format($$select dispose_equipment(%L)$$, test.get('DM2')), 'manage_catalogue', 'retire: disposal is a separate, catalogue-level permission');
select test.as_user('stores_ebb');
select test.works(format($$select dispose_equipment(%L)$$, test.get('DM2')), 'retire: stores officer can record disposal');
select test.as_root();
select test.eq_int(test.avail('EBB','R052'), 12, 'retire: retired trolleys are gone from available stock (14 -> 12)');
select test.eq_int(test.bal('EBB','R052','damaged_quantity'), 0, 'retire: and no longer counted as damaged once disposed');

-- ===== Loss workflow and station scope ===============================================
select test.as_user('mgr_ebb');
select test.put('LS1', report_loss(test.eq('C081'), test.st('EBB'), 4, 'Not found at stock count'));
select test.as_root();
select test.eq_int(test.bal('EBB','C081','missing_quantity'), 4, 'loss: reported quantity is shown as missing');
select test.as_user('mgr_abj');
select test.fails(format($$select start_loss_investigation(%L)$$, test.get('LS1')), 'station access', 'loss: another station cannot investigate it');
select test.as_user('asst_ebb');
select test.fails(format($$select start_loss_investigation(%L)$$, test.get('LS1')), 'Missing permission', 'loss: an assistant cannot investigate');
select test.as_user('mgr_ebb');
select test.works(format($$select start_loss_investigation(%L)$$, test.get('LS1')), 'loss: a manager can start the investigation');
select test.fails(format($$select confirm_loss(%L, '  ')$$, test.get('LS1')), 'reason', 'loss: confirming needs a written reason');
select test.works(format($$select recover_loss(%L, 'Found in the cold room')$$, test.get('LS1')), 'loss: recovered stock is returned');
select test.as_root();
select test.eq_int(test.bal('EBB','C081','missing_quantity'), 0, 'loss: recovery clears the missing bucket');

select test.as_user('admin');
select test.eq_int((select sum(failures)::bigint from integrity_summary()), 0, 'integrity checks pass after the damage and loss workflows');
select test.finish('06_damage_loss_trolleys.sql');
