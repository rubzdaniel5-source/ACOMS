-- Continuous schedule, upcoming flights and unverified flights (migration 037).
select test.as_root();
select test.ok(not exists (select 1 from flight_routes where source <> 'MANUAL' and (valid_from > date '2000-01-01' or valid_to is not null)), 'schedule: every route is continuous (no season start or end)');
select test.ok(exists (select 1 from flight_routes where flight_number = 'UR200'), 'schedule: UR200 still present');

select test.as_user('asst_ebb');
select test.ok((select count(*) from upcoming_flights(test.st('EBB'), test.st('NBO'), 7)) >= 7, 'upcoming: EBB to NBO has flights every day this week');
select test.ok((select count(distinct flight_date) from upcoming_flights(test.st('EBB'), test.st('NBO'), 7)) = 8, 'upcoming: one date per day, today included');
select test.ok((select min(flight_date) from upcoming_flights(test.st('EBB'), test.st('NBO'), 3)) = (now() at time zone 'Africa/Kampala')::date, 'upcoming: starts today in Kampala time');
select test.ok((select count(*) from upcoming_flights(test.st('EBB'), test.st('ABJ'), 14)) = 0, 'upcoming: nothing to a station no scheduled flight serves');
select test.ok((select count(*) from upcoming_flights(test.st('EBB'), test.st('LUN'), 14)) > 0, 'upcoming: through-flights are listed (EBB to LUN)');
select test.ok((select count(*) from upcoming_flights(test.st('EBB'), test.st('NBO'), 500)) <= 61 * 20, 'upcoming: the window is capped');

-- cancelled flights drop out
select test.as_user('mgr_ebb');
select test.works(format($$select cancel_flight_leg(ensure_flight_leg('UR200', %L, test.st('EBB'), test.st('NBO')), 'aircraft change')$$, (now() at time zone 'Africa/Kampala')::date + 1), 'setup: cancel tomorrow''s UR200');
select test.ok(not exists (select 1 from upcoming_flights(test.st('EBB'), test.st('NBO'), 7) where flight_number = 'UR200' and flight_date = (now() at time zone 'Africa/Kampala')::date + 1), 'upcoming: a cancelled flight is not offered');

-- unverified flights
select test.as_user('asst_ebb');
select test.fails(format($$select create_unverified_flight_leg('UR999', %L, test.st('EBB'), test.st('NBO'), '')$$, (now() at time zone 'Africa/Kampala')::date + 2), 'why this flight', 'unverified: a note is required');
select test.fails(format($$select create_unverified_flight_leg('UR999', %L, test.st('EBB'), test.st('NBO'), 'extra flight')$$, (now() at time zone 'Africa/Kampala')::date - 5), 'in the past', 'unverified: not in the past');
select test.works(format($$select test.put('U1', create_unverified_flight_leg('999', %L, test.st('EBB'), test.st('NBO'), 'Extra charter flight'))$$, (now() at time zone 'Africa/Kampala')::date + 2), 'unverified: base staff can enter a flight not in the schedule (number gets the UR prefix)');
select test.as_root();
select test.ok((select is_unverified and flight_number = 'UR999' and is_one_off from flight_legs where id = test.get('U1')), 'unverified: saved flagged, with the UR prefix');
select test.as_user('asst_ebb');
select test.ok(create_unverified_flight_leg('UR999', (now() at time zone 'Africa/Kampala')::date + 2, test.st('EBB'), test.st('NBO'), 'again') = test.get('U1'), 'unverified: entering it again reuses the same flight');
select test.ok(create_unverified_flight_leg('UR201', (now() at time zone 'Africa/Kampala')::date + 3, test.st('NBO'), test.st('EBB'), 'typed by hand') = ensure_flight_leg('UR201', (now() at time zone 'Africa/Kampala')::date + 3, test.st('NBO'), test.st('EBB')), 'unverified: a scheduled flight typed by hand is reused as a normal flight');
select test.as_root();
select test.ok(not (select is_unverified from flight_legs where flight_number = 'UR201' and operating_date = (now() at time zone 'Africa/Kampala')::date + 3), 'unverified: a scheduled flight is never flagged');

-- it can be used on a transfer
select test.as_user('asst_ebb');
select test.works(format($$select test.put('T15', request_transfer(test.st('EBB'), test.st('NBO'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 1)), 'unverified flight', 'NORMAL'))$$), 'setup: a transfer');
select test.works(format($$select set_transfer_flight(%L, %L)$$, test.get('T15'), test.get('U1')), 'unverified: can be linked to a transfer');

-- confirmation
select test.fails(format($$select confirm_flight_leg(%L)$$, test.get('U1')), 'manage_flights', 'confirm: base staff cannot confirm');
select test.as_user('mgr_ebb');
select test.works(format($$select confirm_flight_leg(%L, 'seen the load sheet')$$, test.get('U1')), 'confirm: a station manager confirms it');
select test.fails(format($$select confirm_flight_leg(%L)$$, test.get('U1')), 'already confirmed', 'confirm: not twice');
select test.as_root();
select test.ok((select not is_unverified and verified_by is not null from flight_legs where id = test.get('U1')), 'confirm: verifier recorded');
select test.ok(exists (select 1 from audit_logs where action = 'flight.leg_unverified') and exists (select 1 from audit_logs where action = 'flight.leg_confirm'), 'audit: entry and confirmation recorded');
select test.as_user('outsider');
select test.fails(format($$select create_unverified_flight_leg('UR998', %L, test.st('EBB'), test.st('NBO'), 'x extra')$$, (now() at time zone 'Africa/Kampala')::date + 2), 'Permission denied', 'unverified: a user without the permission is refused');
select test.as_anon();
select test.fails($$select * from upcoming_flights(test.st('EBB'), test.st('NBO'))$$, 'permission denied', 'upcoming: signed-out callers are refused');
select test.finish('15_flight_picker.sql');
