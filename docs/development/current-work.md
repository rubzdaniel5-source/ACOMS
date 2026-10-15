# ACOMS Current Development

## Milestone
**Equipment Control Dashboard v0.1**

## Goal
Establish the complete basic movement path:

**Inventory → Transfer → Approval → Dispatch → In Transit → Receive → Reconcile**

## Status (15 Oct 2026)
Equipment Control v0.1 is built end to end and in use on the live deployment.
- [x] Vision, platform architecture, catalogue, workbook analysis, engineering protocol
- [x] Repository foundation, database schema (27 migrations), authentication, authorization/RLS
- [x] Catalogue and station admin (UI and API)
- [x] Inventory ledger (append-only, balances derived and checked)
- [x] Transfer workflow: request, approval, dispatch, receive, reconcile, close, discrepancy resolution
- [x] Damage and loss workflows, with retire restricted to manager or supervisor
- [x] Stock adjustments with two-person approval; opening balances
- [x] Dashboard, Action Required alerts, reports, CSV export
- [x] Admin: users, roles and permissions, settings, audit log, integrity checks
- [x] Design system (light/dark, account-synced) and phone install with offline screen
- [x] Automated tests: 183 database checks, 17 app tests, CI on every push
- [x] Trolleys counted in batches (ADR-015)

Still to do: operations sign-off on provisional thresholds and tolerances, real opening stock and some placeholder equipment codes, a visual review at every screen width, a reorder level for half-size trolleys (R053), and the later phases in the roadmap. No email or SMS notifications yet.

Only mark work complete after implementation, testing, review and documentation.

## UI/UX implementation (ACOMS-DESIGN-001)
Stage 1 done: tokens + Light/Dark/System, two-level header, dashboard 3x2 / 2x3, Action Required restyle, legacy slate/red utilities migrated to tokens, distinct-station count fix. Remaining: sub-KPI links to filtered lists (needs the card restructured so links are not nested), Station Inventory table review on the dashboard, loading/skeleton and stale-data states, per-route visual review in both themes, account-synced theme preference.

Stage 2 done: sub-KPI counts on the six cards open filtered lists (`/transfers?status=`, `/damage-loss?view=`, `/dashboard/station-inventory?status=`), and the dashboard carries the working Station Inventory table (search, station/equipment/status filters, sorting, pagination, Request transfer shown only with `create_transfer`). Known simplification: Equipment Overview counts have no filtered list yet; "Awaiting Receipt" and "Awaiting Reconciliation" follow the existing view definitions.

Stage 3 done: Equipment Overview counts open `?bucket=` views; loading skeletons for the dashboard and list routes; dashboard shows a dash (not zero) plus a warning when a query fails, and shows when data was loaded. Static theme audit found no literal colours left in components. Not yet done: visual review of every route at 320/360/390/768/1024/1440 in both themes (needs a browser pass against the live deployment), account-synced theme preference, restyling the legacy-shaped transfer/damage-loss screens to the new card/spacing language.

Stage 4 done: screenshot review fixes (dark-mode row dividers were near-white because Tailwind borders default to currentColor; now every border uses the theme border; table headings no longer all-caps) and the older screens (transfers list, new transfer, transfer detail and action panel, damage/loss list, report form, detail and panel) moved to shared button/input/alert/panel styles with consistent page widths, 44px targets and labelled fields. Still open: themed confirmation dialogs for dispatch/reconcile/close (reject still uses window.prompt), Reports page layout pass, account-synced theme.

Stage 5 done: themed ConfirmDialog (reject with required reason, dispatch, reconcile, close), Reports page layout pass, account-synced theme (migration 024), larger table headings, section headings and primary tabs. Remaining at the time: admin deactivate/remove prompts (done in Stage 8); full multi-width visual review.

Stage 6 done: Action Required now includes overdue transfers and adjustments awaiting approval, shows station, quantities and next action, is de-duplicated and sorted (ADR-013), has a full list page, and refuses to show a calm empty state when a source query failed.

Stage 7 done: migration 025 adds `transfers.reconciliation_overdue_days` (default 3) and flags received-but-unreconciled and reconciled-but-unclosed transfers as overdue (Action Required shows "Reconciliation overdue"). Inventory, health and report reads now page through all rows (`lib/supabase/fetchAll.ts`) so the 1,000-row API limit can never truncate counts or exports. Tested: 25 migrations apply cleanly on a fresh database; overdue flags verified for each status at boundary ages.

## Automated tests

- **Database** (`acoms-app/supabase/tests/`, `npm run test:db`): applies all migrations to a throwaway Postgres and acts as real users. 152 checks cover the ledger (lock-down, immutability, opening balances), the transfer lifecycle (permissions, station scope, requester ≠ approver, discrepancy blocks closing), stock adjustments (two-person approval, stock-changed guard), users and roles (no escalation, deactivation, locked admin role), settings validation, the overdue view and audit rows.
- **App** (`acoms-app/tests/`, `npm test`): Action Required rules (`alerts.ts`) and the 1,000-row paging helper (`fetchAll.ts`).
- **CI**: `.github/workflows/tests.yml` runs both, plus `tsc`, on every push and pull request.

### Bugs found by the tests (fixed in migration 026)

1. **Reconciliation double-deducted damaged/missing units** from the destination's available stock and left the damaged/missing buckets at zero. Now each unit is credited as found, then moved out by a DAMAGE/LOSS entry, and a real damage or loss report is opened. Transfers reconciled before 026 keep their old figures; correct them with a stock adjustment if any exist.
2. **Dispatch was not limited to the approved quantity** (and accepted items from other transfers). Now refused.

## Phone and offline use (ADR-014)

Installable app (`manifest.ts`, icons in `public/icons`), service worker `public/sw.js` (static files only), static `public/offline.html`, and an offline/back-online banner (`PwaClient`). Tested in Chromium: with the server down, navigation shows the offline screen. Production build only; the worker is not registered in `next dev`.

## Trolleys in batches (ADR-015, migration 027)

R052 and R053 switched from INDIVIDUAL to BATCH. New permission `retire_equipment`. Damage and loss workflow steps now enforce station scope (previously only the permission was checked). 6 test files, 183 database checks.

## Stage 8
Admin remove-role, deactivate-user and deactivate-station now use the themed confirmation dialog (station deactivation asks for a reason in the dialog). No browser confirm/prompt dialogs remain.

## Trolley shortage alerts (migration 028)
Each station keeps its own required level per item (station stock levels). Items marked "alert on any shortage" (both trolley types; switchable per item in the catalogue side panel) raise a "Below required level" alert when a station is even one unit under. Other items still alert only on critical shortage. A station with no stock record for the item shows no data, not an alert.
