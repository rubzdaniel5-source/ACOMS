-- Dispatch below minimum level needs supervisor/manager approval (migration 038).
select test.as_root();
select test.eq_int((select count(*)::int from pg_proc where proname = 'dispatch_below_minimum'), 1, 'below-min: function exists');
-- EBB holds C058; set its minimum so dispatching 2 leaves it under.
select test.as_root();
select test.as_user('admin');
select set_station_stock_levels(test.st('EBB'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'reorder_threshold', test.avail('EBB','C058'))));
select test.as_user('asst_ebb');
select test.put('BM', request_transfer(test.st('EBB'), test.st('ABJ'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 2)), 'below minimum', 'NORMAL'));
select test.as_user('mgr_ebb');
select test.works(format($$select approve_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('BM','C058'), 'quantity_approved', 2)), 'ok')$$, test.get('BM')), 'below-min: transfer approved');
select test.as_user('asst_ebb');
select test.fails(format($$select dispatch_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('BM','C058'), 'quantity_dispatched', 2)))$$, test.get('BM')), 'below the minimum', 'below-min: dispatch is blocked without approval');
select test.ok((select count(*) from dispatch_below_minimum(test.get('BM'), jsonb_build_array(jsonb_build_object('item_id', test.line('BM','C058'), 'quantity_dispatched', 2)))) = 1, 'below-min: the warning lists the line');
select test.fails(format($$select approve_below_minimum_dispatch(%L, 'stock needed urgently at ABJ')$$, test.get('BM')), 'Only a catering supervisor', 'below-min: an assistant cannot approve');
select test.as_user('mgr_ebb');
select test.fails(format($$select approve_below_minimum_dispatch(%L, 'stock needed urgently at ABJ')$$, test.get('BM')), 'Only a catering supervisor', 'below-min: a station manager cannot approve');
select test.as_user('sup_ebb');
select test.fails(format($$select approve_below_minimum_dispatch(%L, 'short')$$, test.get('BM')), 'clear reason', 'below-min: a reason is required');
select test.works(format($$select approve_below_minimum_dispatch(%L, 'stock needed urgently at ABJ')$$, test.get('BM')), 'below-min: supervisor approves with reason');
select test.as_root();
select test.ok(exists (select 1 from audit_logs where action = 'transfer.below_min_approve' and reason = 'stock needed urgently at ABJ'), 'below-min: approval is audited with the reason');
select test.as_user('asst_ebb');
select test.works(format($$select dispatch_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('BM','C058'), 'quantity_dispatched', 2)))$$, test.get('BM')), 'below-min: dispatch works once approved');
-- A dispatch that stays above the minimum needs no approval and cannot be "approved".
select test.as_user('asst_ebb');
select test.put('OK', request_transfer(test.st('EBB'), test.st('ABJ'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C081'), 'quantity', 1)), 'fine', 'NORMAL'));
select test.as_user('mgr_ebb');
select test.works(format($$select approve_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('OK','C081'), 'quantity_approved', 1)), 'ok')$$, test.get('OK')), 'below-min: second transfer approved');
select test.as_user('sup_ebb');
select test.fails(format($$select approve_below_minimum_dispatch(%L, 'not really needed here')$$, test.get('OK')), 'no approval is needed', 'below-min: nothing to approve when above the minimum');
select test.as_anon();
select test.fails($$select dispatch_below_minimum(gen_random_uuid(), '[]'::jsonb)$$, 'permission denied', 'below-min: signed-out callers are refused');
select test.finish('16_dispatch_below_minimum.sql');
