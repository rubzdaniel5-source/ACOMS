-- request_transfer validation (migration 036).
select test.as_root();
insert into organizations (id, code, name) values ('00000000-0000-0000-0000-0000000000a1', 'OTHER_ORG', 'Other Airline') on conflict do nothing;
insert into stations (id, organization_id, code, name) values ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a1', 'XXX', 'Foreign station') on conflict do nothing;
insert into stations (id, organization_id, code, name, is_active) values ('00000000-0000-0000-0000-0000000000b2', (select organization_id from stations where code = 'EBB'), 'ZZZ', 'Closed station', false) on conflict do nothing;

select test.as_user('asst_ebb');
select test.fails(format($$select request_transfer(test.st('EBB'), %L, jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 1)))$$, '00000000-0000-0000-0000-0000000000b1'::uuid), 'your organisation', 'request: a destination in another organisation is refused');
select test.fails(format($$select request_transfer(test.st('EBB'), %L, jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 1)))$$, '00000000-0000-0000-0000-0000000000b2'::uuid), 'not active', 'request: an inactive destination is refused');
select test.fails($$select request_transfer(test.st('EBB'), gen_random_uuid(), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 1)))$$, 'does not exist', 'request: an unknown destination is refused');
select test.fails($$select request_transfer(test.st('EBB'), test.st('EBB'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 1)))$$, 'must be different', 'request: same source and destination is refused');
select test.fails($$select request_transfer(test.st('EBB'), test.st('NBO'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 1), jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 2)))$$, 'only be listed once', 'request: the same item twice is refused');
select test.fails($$select request_transfer(test.st('EBB'), test.st('NBO'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 0)))$$, 'greater than zero', 'request: a zero quantity is refused');
select test.fails($$select request_transfer(test.st('EBB'), test.st('NBO'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 'abc')))$$, 'whole number', 'request: a non-numeric quantity is refused');
select test.fails($$select request_transfer(test.st('EBB'), test.st('NBO'), jsonb_build_array(jsonb_build_object('equipment_type_id', gen_random_uuid(), 'quantity', 1)))$$, 'Unknown equipment', 'request: an unknown item is refused');
select test.fails($$select request_transfer(test.st('EBB'), test.st('NBO'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 1)), null, 'WHENEVER')$$, 'Unknown priority', 'request: an unknown priority is refused');
select test.as_root();
select test.eq_int((select count(*)::int from equipment_transfers where reason is null and to_station_id in ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b2')), 0, 'request: refused calls leave no transfer behind');
select test.as_user('asst_ebb');
select test.works($$select request_transfer(test.st('EBB'), test.st('NBO'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 1)), 'valid request', 'HIGH')$$, 'request: a valid request still works');
select test.as_anon();
select test.fails($$select request_transfer(test.st('EBB'), test.st('NBO'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 1)))$$, 'permission denied', 'request: signed-out callers are refused');
select test.finish('14_request_validation.sql');
