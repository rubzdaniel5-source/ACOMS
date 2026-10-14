#!/usr/bin/env bash
# Runs the ACOMS database business-rule tests against a throwaway Postgres database.
# Usage: PGHOST=... PGUSER=... PGPASSWORD=... ./run.sh   (needs a superuser connection)
set -euo pipefail
cd "$(dirname "$0")"
DB="acoms_test_$$"
PSQL="psql -v ON_ERROR_STOP=1 -q -X"
createdb "$DB"
trap 'dropdb --if-exists "$DB" >/dev/null 2>&1 || true' EXIT
$PSQL -d "$DB" -f bootstrap.sql
# Supabase gives the API roles default privileges on everything created in public.
# Set them BEFORE the migrations run so the migrations' own REVOKEs are tested for real.
$PSQL -d "$DB" -c "grant usage on schema public, auth to anon, authenticated, service_role;
  alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
  alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
  alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;
  grant select on auth.users to authenticated;" >/dev/null
for f in ../migrations/*.sql; do $PSQL -d "$DB" -f "$f" >/dev/null; done
$PSQL -d "$DB" -f helpers.sql
fail=0
for t in [0-9]*.sql; do
  echo "== $t"
  if ! $PSQL -d "$DB" -o /dev/null -f "$t" 2>&1 | sed -e "s/^psql:[^ ]* NOTICE:  //" -e "s/^NOTICE:  //"; then fail=1; fi
done
if [ $fail -ne 0 ]; then echo "TESTS FAILED"; exit 1; fi
echo "ALL DATABASE TESTS PASSED"
