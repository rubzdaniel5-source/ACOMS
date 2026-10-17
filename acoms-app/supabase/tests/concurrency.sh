#!/usr/bin/env bash
# Two real database sessions race on the same transfer. The row lock must make the second one wait,
# then refuse because the first already changed the status. Needs a superuser connection, like run.sh.
# Usage: PGHOST=... PGUSER=... ./concurrency.sh
set -euo pipefail
cd "$(dirname "$0")"
DB="acoms_conc_$$"
P="psql -v ON_ERROR_STOP=1 -q -X -t -A"
createdb "$DB"; trap 'dropdb --if-exists "$DB" >/dev/null 2>&1 || true' EXIT
$P -d "$DB" -f bootstrap.sql
$P -d "$DB" -c "grant usage on schema public, auth to anon, authenticated, service_role; alter default privileges in schema public grant all on tables to anon, authenticated, service_role; alter default privileges in schema public grant all on sequences to anon, authenticated, service_role; alter default privileges in schema public grant execute on functions to anon, authenticated, service_role; grant select on auth.users to authenticated;" >/dev/null
for f in ../migrations/*.sql; do $P -d "$DB" -f "$f" >/dev/null 2>&1; done
$P -d "$DB" -f helpers.sql >/dev/null; $P -d "$DB" -f 01_fixtures.sql >/dev/null 2>&1
$P -d "$DB" >/dev/null <<'SQL'
select test.as_user('stores_ebb');
select record_opening_balances(test.st('EBB'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 100)), 'conc');
select test.as_user('asst_ebb');
select test.put('A', request_transfer(test.st('EBB'), test.st('NBO'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 10)), 'race A', 'NORMAL'));
select test.put('B', request_transfer(test.st('EBB'), test.st('NBO'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 10)), 'race B', 'NORMAL'));
select test.as_user('mgr_ebb');
select approve_transfer(test.get('A'), jsonb_build_array(jsonb_build_object('item_id', test.line('A','C058'), 'quantity_approved', 10)), 'ok');
select approve_transfer(test.get('B'), jsonb_build_array(jsonb_build_object('item_id', test.line('B','C058'), 'quantity_approved', 10)), 'ok');
SQL
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok    $1"; else echo "FAIL  $1 (expected $3, got $2)"; fail=1; fi; }

# ---- Race 1: two dispatches of the same approved transfer ----
dispatch_sql() { echo "select test.as_user('asst_ebb'); begin; select dispatch_transfer(test.get('A'), jsonb_build_array(jsonb_build_object('item_id', test.line('A','C058'), 'quantity_dispatched', 10)));"; }
( { dispatch_sql; echo "select pg_sleep(3); commit;"; } | $P -d "$DB" > /tmp/conc_a.$$ 2>&1 || true ) &
sleep 1
start=$(date +%s)
{ dispatch_sql; echo "commit;"; } | $P -d "$DB" > /tmp/conc_b.$$ 2>&1 || true
waited=$(( $(date +%s) - start )); wait
okc=$(cat /tmp/conc_a.$$ /tmp/conc_b.$$ | grep -c "must be APPROVED" || true)
check "dispatch race: exactly one session was refused" "$okc" "1"
check "dispatch race: the second session had to wait for the lock (>= 2 s)" "$([ $waited -ge 2 ] && echo yes || echo no)" "yes"
check "dispatch race: stock left EBB exactly once (100 -> 90)" "$($P -d "$DB" -c "select available_quantity from inventory_balances b join stations s on s.id=b.station_id where s.code='EBB'")" "90"

# ---- Race 2: two receipts of the same in-transit transfer ----
recv_sql() { echo "select test.as_user('asst_nbo'); begin; select receive_transfer(test.get('A'), jsonb_build_array(jsonb_build_object('item_id', test.line('A','C058'), 'quantity_counted', 10, 'quantity_damaged', 0)));"; }
( { recv_sql; echo "select pg_sleep(3); commit;"; } | $P -d "$DB" > /tmp/conc_c.$$ 2>&1 || true ) &
sleep 1
start=$(date +%s)
{ recv_sql; echo "commit;"; } | $P -d "$DB" > /tmp/conc_d.$$ 2>&1 || true
waited=$(( $(date +%s) - start )); wait
refused=$(cat /tmp/conc_c.$$ /tmp/conc_d.$$ | grep -c "IN_TRANSIT or PARTIALLY_RECEIVED" || true)
check "receipt race: exactly one session was refused" "$refused" "1"
check "receipt race: the second session had to wait for the lock (>= 2 s)" "$([ $waited -ge 2 ] && echo yes || echo no)" "yes"
check "receipt race: stock arrived at NBO exactly once (10)" "$($P -d "$DB" -c "select available_quantity from inventory_balances b join stations s on s.id=b.station_id where s.code='NBO'")" "10"
check "receipt race: one receipt record" "$($P -d "$DB" -c "select count(*) from equipment_transfer_receipts")" "1"
rm -f /tmp/conc_?.$$
if [ $fail -ne 0 ]; then echo "CONCURRENCY TESTS FAILED"; exit 1; fi
echo "ALL CONCURRENCY TESTS PASSED"
