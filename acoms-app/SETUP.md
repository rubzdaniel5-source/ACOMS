# ACOMS — Phase 0 Setup Instructions

## What's in this delivery
- Next.js 15 + TypeScript + Tailwind app shell (App Router, `src/` layout)
- Supabase client wiring (browser, server, middleware session refresh)
- `supabase/migrations/` — 4 migrations: identity foundation, RLS, audit
  foundation, seed data (roles/permissions/stations)
- `docs_reference/development/decisions.md` — updated with ADR-007 to ADR-011
  reflecting the decisions from our planning session

## 1. Push this to GitHub
I can't push directly to your repo (I only have read access to the public
repo). From your machine:

```bash
# unzip the delivered folder, then inside it:
git init   # if not already a git repo
git remote add origin https://github.com/rubzdaniel5-source/ACOMS.git
git add .
git commit -m "feat: Phase 0 foundation - Next.js shell, Supabase wiring, identity schema"
git push origin main
```

(If `git push` conflicts with the existing docs-only commit history, use
`git pull origin main --allow-unrelated-histories` first, resolve any file
overlaps — there shouldn't be any — then push.)

## 2. Run the migrations against Supabase
Easiest path — Supabase Dashboard SQL Editor:
1. Go to your project → SQL Editor
2. Run each file in `supabase/migrations/` **in order** (0001 → 0004)
3. Confirm no errors before moving to the next file

Alternative — Supabase CLI (if you have it installed locally):
```bash
supabase link --project-ref lnmzlnwwfctcwgiegmkh
supabase db push
```

## 3. Before running migration 0004 (seed data)
Open it and change:
```sql
insert into organizations (code, name) values
  ('AIRLINE01', 'Primary Airline Organization');
```
to your actual airline's code/name.

## 4. Run locally
```bash
npm install
npm run dev
```
`.env.local` is already populated with your Supabase URL and anon key
(not committed — confirmed in `.gitignore`).

## What's NOT done yet (intentionally — see CLAUDE.md, vertical slices)
- No auth UI (login/signup pages) yet
- No equipment catalogue tables yet (next migration)
- No transfer workflow yet — this is the next vertical slice
- No PWA manifest/service worker yet (deferred until after Equipment Control
  slice proves out, per ACOMS_MASTER_SPEC.md §23)

## Known limitations / review needed
- Reconciliation tolerance values (0 / ±1 / ±2) are my proposed defaults per
  ADR-008 — flagged as provisional pending your sign-off once real data is
  in the system.
- Role → permission mapping in migration 0004 is a reasonable starting point,
  not confirmed with catering management — expect to adjust.
- I could not execute/lint the SQL against a real Postgres instance in this
  sandbox (no local Postgres, no network access to install one). Please run
  migrations in a Supabase staging/dev project first, not directly against
  a production dataset, and report back if anything errors.
