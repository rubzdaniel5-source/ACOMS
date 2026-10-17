set -e
M=/home/claude/ACOMS/acoms-app/supabase
P="psql -v ON_ERROR_STOP=1 -q -X"
dropdb --if-exists acoms_e2e; createdb acoms_e2e
$P -d acoms_e2e -f $M/tests/bootstrap.sql
$P -d acoms_e2e -c "grant usage on schema public, auth to anon, authenticated, service_role; alter default privileges in schema public grant all on tables to anon, authenticated, service_role; alter default privileges in schema public grant all on sequences to anon, authenticated, service_role; alter default privileges in schema public grant execute on functions to anon, authenticated, service_role; grant select on auth.users to authenticated;" >/dev/null
for f in $M/migrations/*.sql; do $P -d acoms_e2e -f $f >/dev/null; done
$P -d acoms_e2e -f $M/tests/helpers.sql
$P -d acoms_e2e -o /dev/null -f $M/tests/01_fixtures.sql
$P -d acoms_e2e -c "grant usage on schema test to public; grant all on all tables in schema test to public;" 
# opening stock
$P -d acoms_e2e -o /dev/null <<'SQL'
select test.as_user('stores_ebb');
select record_opening_balances(test.st('EBB'), jsonb_build_array(jsonb_build_object('equipment_type_id', test.eq('C058'), 'quantity', 100), jsonb_build_object('equipment_type_id', test.eq('C081'), 'quantity', 50)), 'e2e opening');
select test.as_root();
SQL
$P -d acoms_e2e -c "select email, id from auth.users order by email"
