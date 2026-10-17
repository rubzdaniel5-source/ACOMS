-- Dashboard count views (migration 035). Uses the transfers left behind by earlier test files.
select test.as_user('admin');
select test.ok((select open_exchanges >= 0 and open_exchanges = outbound_in_progress + awaiting_return + return_in_progress + ready_to_close
                   + (select count(*) from v_equipment_exchanges where status = 'OUTBOUND_RECONCILIATION')
                from v_exchange_funnel), 'exchange funnel: open exchanges equal the sum of their stages');
select test.ok((select count(*) from v_equipment_exchanges where status = 'AWAITING_RETURN') = (select awaiting_return from v_exchange_funnel), 'exchange funnel: awaiting-return count matches the list');
select test.ok((select awaiting_receipt = in_transit + partially_received from v_movement_funnel), 'movement funnel: awaiting receipt = in transit + partly received');
select test.ok((select open_holds = awaiting_investigation + awaiting_authorisation from v_excess_summary), 'excess summary: open holds = awaiting investigation + awaiting authorisation');
select test.ok((select held_units = (select coalesce(sum(held_quantity),0) from inventory_balances) from v_excess_summary), 'excess summary: held units agree with the held bucket');
select test.as_user('asst_ebb');
select test.ok((select held_units >= 0 from v_excess_summary), 'excess summary: readable by an assistant');
select test.as_anon();
select test.fails($$select * from v_excess_summary$$, 'permission denied', 'excess summary: not readable when signed out');
select test.fails($$select * from v_exchange_funnel$$, 'permission denied', 'exchange funnel: not readable when signed out');
select test.finish('13_dashboard_counts.sql');
