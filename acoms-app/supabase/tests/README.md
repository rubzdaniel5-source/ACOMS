# Database tests

These tests apply **every migration** to a throwaway Postgres database and then act as real
users (switching into the `authenticated` role, exactly as Supabase does) to check the business
rules that live in the database: the stock ledger, the transfer lifecycle, stock adjustments,
roles and users, settings, audit and the overdue logic.

Run them (needs a Postgres superuser connection; each run creates and drops its own database):

    PGHOST=localhost PGUSER=postgres PGPASSWORD=... npm run test:db

Files run in order. `01_fixtures.sql` creates one user per role and scope. A failing check stops
the run with a non-zero exit code.

`test.known(...)` marks a bug that has been reported but not fixed yet (none at the moment). It never fails the run;
when the bug is fixed the line prints `FIXED (promote to a normal check)`.

Add a test for every new migration that changes a business rule.
