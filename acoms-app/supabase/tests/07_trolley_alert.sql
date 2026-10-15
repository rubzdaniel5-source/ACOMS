-- Per-station trolley levels and the "alert on any shortage" flag.
select test.ok((select bool_and(alert_on_any_shortage) from equipment_types where source_code in ('R052','R053')), 'trolleys: alert-on-any-shortage is on for both types');
select test.ok(not (select alert_on_any_shortage from equipment_types where source_code = 'C058'), 'ordinary items: alert-on-any-shortage is off');

-- EBB holds 12 full-size trolleys (14 opened, 2 retired). Require 13 at EBB: one short.
select test.as_user('stores_ebb');
select test.works($$select set_station_stock_levels(test.st('EBB'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('R052'), 'reorder_threshold', 13)))$$, 'trolleys: a station can have its own required level');
select test.as_user('admin');
select test.works($$select set_station_stock_levels(test.st('EBB'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('R052'), 'reorder_threshold', 13)))$$, 'trolleys: admin sets EBB required level to 13');
select test.ok((select status from v_inventory_health where station_code = 'EBB' and source_code = 'R052') = 'SHORTAGE', 'trolleys: 12 against a required 13 is a shortage');
select test.ok((select alert_on_any_shortage from v_inventory_health where station_code = 'EBB' and source_code = 'R052'), 'trolleys: the health view carries the flag for the app');
select test.works($$select set_station_stock_levels(test.st('EBB'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('R052'), 'reorder_threshold', 12)))$$, 'trolleys: required level lowered to 12');
select test.ok((select status from v_inventory_health where station_code = 'EBB' and source_code = 'R052') = 'NORMAL', 'trolleys: at the required level there is no shortage');

select test.as_user('mgr_ebb');
select test.fails($$select set_equipment_shortage_alert(test.eq('C058'), true)$$, 'manage_catalogue', 'flag: a station manager cannot change it');
select test.as_user('admin');
select test.works($$select set_equipment_shortage_alert(test.eq('C058'), true)$$, 'flag: admin can switch it on for any item');
select test.works($$select set_equipment_shortage_alert(test.eq('C058'), false)$$, 'flag: and off again');
select test.as_root();
select test.ok(exists (select 1 from audit_logs where action = 'catalogue.shortage_alert_set'), 'flag: changes are audited');
select test.finish('07_trolley_alert.sql');
