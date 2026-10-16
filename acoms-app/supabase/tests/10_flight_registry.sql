-- Flight-leg registry: seeded schedule, validation, one-offs, cancellation, transfer link, history.
create function test.nextdow(p_dow int) returns date language sql as $$
  select d::date from generate_series(greatest(current_date, date '2026-10-26'), greatest(current_date, date '2026-10-26') + 7, interval '1 day') d
  where extract(isodow from d) = p_dow limit 1 $$;

-- Seed
select test.as_root();
select test.eq_int((select count(*) from flight_routes where source like 'WINTER 2026%'), 54, 'seed: 54 scheduled routes loaded from the winter schedule');
select test.ok((select operating_days = array[2,4,5,6,7]::smallint[] from v_flight_routes where flight_number = 'UR120' and origin_code = 'EBB' and destination_code = 'JUB'), 'seed: 120 EBB-JUB operates Tue, Thu, Fri, Sat, Sun');
select test.ok((select operating_days = array[1,2,3,4,5,6,7]::smallint[] from v_flight_routes where flight_number = 'UR200' and origin_code = 'EBB' and destination_code = 'NBO'), 'seed: 200 EBB-NBO operates daily');
select test.ok(exists (select 1 from v_flight_routes where flight_number = 'UR334' and origin_code = 'ZNZ' and destination_code = 'JRO'), 'seed: multi-sector flights are stored as separate sectors');

-- Permissions on the schedule
select test.as_user('stores_ebb');
select test.fails($$select create_flight_route('TST1','EBB','NBO',array[3],date '2026-10-25')$$, 'manage_flights', 'route: stores officer cannot maintain the schedule');
select test.as_user('mgr_ebb');
select test.fails($$select create_flight_route('TST1','EBB','XXX',array[3],date '2026-10-25')$$, 'Unknown', 'route: unknown station refused');
select test.fails($$select create_flight_route('TST1','EBB','NBO',array[8],date '2026-10-25')$$, 'Operating days', 'route: invalid weekday refused');
select test.fails($$select create_flight_route('TST1','EBB','EBB',array[3],date '2026-10-25')$$, 'differ', 'route: origin and destination must differ');
select test.put('RT', create_flight_route('TST1','EBB','NBO',array[3],date '2026-10-25'));

-- Dated legs, validated against the schedule
select test.as_user('asst_ebb');
select test.put('L200', ensure_flight_leg('200', test.nextdow(2), test.st('EBB'), test.st('NBO')));
select test.ok(ensure_flight_leg('200', test.nextdow(2), test.st('EBB'), test.st('NBO')) = test.get('L200'), 'leg: asking again returns the same leg (no duplicates)');
select test.fails(format($$select ensure_flight_leg('120', %L, test.st('EBB'), test.st('JUB'))$$, test.nextdow(1)), 'No scheduled flight', 'leg: 120 does not operate on a Monday');
select test.fails(format($$select ensure_flight_leg('200', %L, test.st('NBO'), test.st('EBB'))$$, test.nextdow(2)), 'No scheduled flight', 'leg: 200 does not fly NBO to EBB (that is 201)');
select test.fails($$select ensure_flight_leg('200', date '2026-10-20', test.st('EBB'), test.st('NBO'))$$, 'No scheduled flight', 'leg: before the season starts is refused');
select test.fails(format($$select ensure_flight_leg('999', %L, test.st('EBB'), test.st('NBO'))$$, test.nextdow(2)), 'No scheduled flight', 'leg: an unknown flight number is never invented');
-- Prefix and through-flights (migration 032)
select test.ok((select array_agg(flight_number) from available_flights(test.st('EBB'), test.st('LUN'), test.nextdow(3))) @> array['UR722'], 'offer: the flight list includes through-flights for the route');
select test.ok((select count(*) from available_flights(test.st('EBB'), test.st('ABJ'), test.nextdow(3))) = 0, 'offer: no flights are offered where none are scheduled');
select test.ok(normalize_flight_number(' 200 ') = 'UR200' and normalize_flight_number('ur200') = 'UR200' and normalize_flight_number('UR200') = 'UR200', 'prefix: numbers are stored with the UR prefix');
select test.ok(not exists (select 1 from flight_routes where source like 'WINTER%' and flight_number not like 'UR%'), 'prefix: every scheduled flight carries UR');
select test.put('LTH', ensure_flight_leg('722', test.nextdow(3), test.st('EBB'), test.st('LUN')));
select test.eq_int((select count(*) from flight_legs where flight_number = 'UR722' and operating_date = test.nextdow(3)), 2, 'through: both sectors (EBB-HRE and HRE-LUN) are created');
select test.as_user('admin');
select test.fails(format($$select ensure_flight_leg('110', %L, test.st('LGW'), test.st('EBB'))$$, test.nextdow(2)), 'No scheduled flight', 'through: the chain only runs in the flight''s direction (UR110 flies EBB to LGW only)');
select test.as_user('asst_ebb');
select test.put('TT', request_transfer(test.st('EBB'), test.st('LUN'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 1)), 'through flight', 'NORMAL'));
select test.works(format($$select set_transfer_flight(%L, %L)$$, test.get('TT'), test.get('LTH')), 'through: EBB to LUN can ride UR722 via HRE');
select test.as_root();
select test.eq_int((select cardinality(flight_leg_ids) from equipment_transfers where id = test.get('TT')), 2, 'through: both sectors are linked to the transfer');
select test.as_user('mgr_ebb');
select test.works(format($$select cancel_flight_leg((select id from flight_legs where flight_number = 'UR722' and operating_date = %L and origin_station_id = test.st('HRE')), 'Aircraft swap')$$, test.nextdow(3)), 'through: the second sector can be cancelled');
select test.works(format($$select approve_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('TT','C058'), 'quantity_approved', 1)), 'ok')$$, test.get('TT')), 'through: approve');
select test.as_user('asst_ebb');
select test.fails(format($$select dispatch_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('TT','C058'), 'quantity_dispatched', 1)))$$, test.get('TT')), 'cancelled', 'through: a cancelled later sector blocks dispatch');
select test.as_user('outsider');
select test.fails(format($$select ensure_flight_leg('200', %L, test.st('EBB'), test.st('NBO'))$$, test.nextdow(3)), 'Permission denied', 'leg: a user without transfer rights cannot create legs');
select test.as_user('mgr_ebb');
select test.works(format($$select set_flight_route_active(%L, false, 'schedule test')$$, test.get('RT')), 'route: can be deactivated with a reason');
select test.fails(format($$select ensure_flight_leg('TST1', %L, test.st('EBB'), test.st('NBO'))$$, test.nextdow(3)), 'No scheduled flight', 'leg: an inactive route cannot create new legs');

-- One-off flights
select test.as_user('asst_ebb');
select test.fails(format($$select create_one_off_flight_leg('900X', %L, test.st('EBB'), test.st('NBO'), 'charter')$$, test.nextdow(4)), 'manage_flights', 'one-off: an assistant cannot add one');
select test.as_user('mgr_ebb');
select test.fails(format($$select create_one_off_flight_leg('900X', %L, test.st('EBB'), test.st('NBO'), '')$$, test.nextdow(4)), 'reason', 'one-off: a reason is required');
select test.works(format($$select create_one_off_flight_leg('900X', %L, test.st('EBB'), test.st('NBO'), 'Charter requested by operations')$$, test.nextdow(4)), 'one-off: a station manager can add one with a reason');

-- Link to a transfer
select test.as_user('asst_ebb');
select test.put('T1', request_transfer(test.st('EBB'), test.st('NBO'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 2)), 'flight test 1', 'NORMAL'));
select test.put('T2', request_transfer(test.st('EBB'), test.st('ABJ'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 2)), 'flight test 2', 'NORMAL'));
select test.fails(format($$select set_transfer_flight(%L, %L)$$, test.get('T2'), test.get('L200')), 'does not match', 'transfer flight: the flight must match the transfer''s stations');
select test.works(format($$select set_transfer_flight(%L, %L)$$, test.get('T1'), test.get('L200')), 'transfer flight: a matching flight is accepted');
select test.as_user('asst_abj');
select test.fails(format($$select set_transfer_flight(%L, %L)$$, test.get('T1'), test.get('L200')), 'Only the requester', 'transfer flight: another station cannot change it');
select test.as_root();
select test.ok((select flight_number = 'UR200' and flight_date = test.nextdow(2) and flight_origin_code = 'EBB' and flight_destination_code = 'NBO' from equipment_transfers where id = test.get('T1')), 'transfer flight: details are copied onto the transfer');

-- Cancelling a leg blocks dispatch; history survives
select test.as_user('mgr_ebb');
select test.works(format($$select approve_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('T1','C058'), 'quantity_approved', 2)), 'ok')$$, test.get('T1')), 'approve T1');
select test.as_user('asst_ebb');
select test.fails(format($$select cancel_flight_leg(%L, 'weather')$$, test.get('L200')), 'manage_flights', 'cancel leg: an assistant cannot');
select test.as_user('mgr_ebb');
select test.fails(format($$select cancel_flight_leg(%L, '')$$, test.get('L200')), 'reason', 'cancel leg: a reason is required');
select test.works(format($$select cancel_flight_leg(%L, 'Aircraft grounded')$$, test.get('L200')), 'cancel leg: a station manager can cancel with a reason');
select test.fails(format($$select cancel_flight_leg(%L, 'again')$$, test.get('L200')), 'already cancelled', 'cancel leg: cannot cancel twice');
select test.as_user('asst_ebb');
select test.fails(format($$select dispatch_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('T1','C058'), 'quantity_dispatched', 2)))$$, test.get('T1')),
  'flight for this transfer has been cancelled', 'dispatch: refused while the transfer''s flight leg is cancelled');
select test.put('T3', request_transfer(test.st('EBB'), test.st('NBO'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 1)), 'flight test 3', 'NORMAL'));
select test.fails(format($$select set_transfer_flight(%L, %L)$$, test.get('T3'), test.get('L200')), 'cancelled', 'transfer flight: a cancelled leg cannot be chosen');
select test.as_root();
select test.ok((select flight_number = 'UR200' from equipment_transfers where id = test.get('T1')), 'history: the transfer still shows its original flight');
select test.fails($$delete from flight_legs$$, 'cannot be deleted', 'history: flight legs cannot be deleted');
select test.fails(format($$update flight_legs set flight_number = '201' where id = %L$$, test.get('L200')), 'cannot be changed', 'history: a leg''s flight, date and route cannot be edited');
select test.ok((select status = 'CANCELLED' and cancel_reason = 'Aircraft grounded' from flight_legs where id = test.get('L200')), 'history: cancellation reason retained');
select test.ok(exists (select 1 from audit_logs where action = 'flight.leg_cancel') and exists (select 1 from audit_logs where action = 'flight.leg_one_off')
  and exists (select 1 from audit_logs where action = 'flight.route_create') and exists (select 1 from audit_logs where action = 'transfer.set_flight'), 'audit: flight actions are recorded');

-- A healthy flight dispatches normally
select test.as_user('asst_ebb');
select test.put('L201', ensure_flight_leg('200', test.nextdow(3), test.st('EBB'), test.st('NBO')));
select test.works(format($$select set_transfer_flight(%L, %L)$$, test.get('T3'), test.get('L201')), 'transfer flight: T3 gets a valid flight');
select test.as_user('mgr_ebb');
select test.works(format($$select approve_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('T3','C058'), 'quantity_approved', 1)), 'ok')$$, test.get('T3')), 'approve T3');
select test.as_user('asst_ebb');
select test.works(format($$select dispatch_transfer(%L, jsonb_build_array(jsonb_build_object('item_id', test.line('T3','C058'), 'quantity_dispatched', 1)))$$, test.get('T3')), 'dispatch: proceeds with a valid flight');
select test.fails(format($$select set_transfer_flight(%L, %L)$$, test.get('T3'), test.get('L201')), 'requested or approved', 'transfer flight: cannot be changed after dispatch');
select test.as_user('admin');
select test.eq_int((select sum(failures)::bigint from integrity_summary()), 0, 'integrity: no failures');
select test.finish('10_flight_registry.sql');
