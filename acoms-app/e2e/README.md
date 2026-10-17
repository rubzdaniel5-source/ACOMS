# Browser check harness (local only)

Runs the real app in Chromium against a local Postgres built from the migrations, with PostgREST serving the REST API
and `gateway.mjs` standing in for Supabase sign-in (password `pw` for the fixture users, e.g. `mgr_ebb@test.local`).
It does not touch any Supabase project. Nothing here ships to Vercel.

1. `su postgres -c "bash e2e/build_db.sh"` builds database `acoms_e2e` (migrations, fixture users, EBB opening stock).
2. Start PostgREST (v12) with `e2e/pgrst.conf`, then `node e2e/gateway.mjs` (prints the anon key).
3. `NEXT_PUBLIC_SUPABASE_URL=http://localhost:54321 NEXT_PUBLIC_SUPABASE_ANON_KEY=<key> npx next dev -p 3100`.
4. Drive it with Playwright (`lib.mjs`, `lib2.mjs`, `flow.mjs` hold the login, form and step helpers).

Paths inside the scripts (`/tmp/e2e`, `/tmp/pgrst`) are those of the sandbox this was built in; adjust as needed.
