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

## Visual review (Stage 9)
Reviewed the main screens at 360, 390, 768 and 1280 px in light and dark against a local copy of the app with demo data. Fixed: Admin menu squeezed its content on phones (now a scrolling strip above full-width content); Transfers list clipped its Status column on phones (now scrolls); the same clipping guard added to three dashboard detail tables; stock numbers in the Station Inventory table now use thousands separators like the alerts; spacing on the New transfer equipment heading. Wide tables on phones scroll sideways by design. Nothing else known; re-check after real data is loaded.

## Cancel a transfer and book new stock (migration 029)
- **Cancel a transfer.** A transfer can be cancelled with a required reason while it is REQUESTED (by the requester, or an approver at the source station) or APPROVED (approver at the source only). Never after dispatch; use receive and reconcile instead. No stock moves; the action is audited as `transfer.cancel`.
- **New stock received.** New reason `NEW_STOCK_RECEIVED` on the two-person stock adjustment (increase only). On approval it posts to the ledger as `RECEIPT`, not `ADJUSTMENT`.
- Tests: `supabase/tests/08_cancel_and_receipts.sql`. Database suite is now 218 checks, all passing.
- **Run migration 029 in the Supabase project the live app uses.**

## Equipment Exchange MVP — Step 1: transfer safety fixes (migration 030)
Audit defects found by regression tests (`tests/09_transfer_safety.sql`, 26 checks failed before the fix, all pass after):
- Approval accepted a line from another transfer, negative or above-requested quantities.
- Dispatch and reconcile posted stock twice if a line was listed twice.
- Receipt accepted any quantity (over-receipt created stock), negatives, foreign lines, partial line lists.
- No row locking, so simultaneous clicks could both pass the status check.
Fixes: row locks on all eight transfer functions, validation as above, "each line once" guard, receipt capped at dispatched (over-receipt refused for now; the controlled excess-hold state is Step 4). Function bodies only, no schema change. Database suite: 248 checks.
Not yet covered: true two-session concurrency test (the lock is verified structurally); receive form still pre-fills dispatched numbers (changes in Step 4); request_transfer does not yet verify the destination station's organisation.

## Equipment Exchange MVP — Step 2: flight-leg registry (migration 031)
- **Source:** Winter 2026 schedule (effective 25 Oct 2026), main sheet "WINTER SCH": 54 sector entries (flight, origin, destination, operating weekdays) seeded into `flight_routes`. Every station in it exists in the station registry; ABJ and DXB are not served this season. The other sheets (With CAN, With additional routes, Options 2/3/206, cost saving) are alternative proposals and were not loaded.
- **Two levels:** `flight_routes` (recurring schedule) and `flight_legs` (one dated flight on one sector, created on demand only if it matches an active route's weekday and season, or as a one-off with a reason). Legs can never be edited or deleted, only cancelled with a reason. Multi-sector flights are separate sectors.
- **Transfers:** `set_transfer_flight` links a leg while REQUESTED or APPROVED; route must match the transfer's stations; cancelled legs refused; details are copied onto the transfer so history survives registry changes. A cancelled leg blocks dispatch. A flight is optional for now (made mandatory for hub exchanges in Step 3).
- **Permission:** new `manage_flights` (system admin, station manager). Audited: route create/deactivate, one-off, cancel, set flight.
- **UI:** Admin > Flights (schedule, upcoming dated flights, add flight, one-off, cancel); optional flight picker on New Transfer; flight shown on the transfer page.
- Tests: `tests/10_flight_registry.sql`; database suite 288 checks. Not yet checked in a browser (done in the final stage).
- **Run migration 031 after 030 in the project the live app uses.**

### Step 2 follow-up (migration 032): UR prefix and through-flights
- All flight numbers carry `UR` (UR110, UR200). Existing entries renamed; numbers typed without it are stored with it. Schedule is continuous (no end date). New flight numbers, routes and stations are added in Admin > Flights and Admin > Stations.
- Through-flights: a transfer's two stations may both lie on one flight's chain of sectors (EBB to LUN on UR722, which flies EBB-HRE-LUN-EBB). Every sector is linked (`flight_leg_ids`); cancelling any sector blocks dispatch. The New Transfer flight list now comes from `available_flights()` in the database.
- Station stock status (migration 006): stock-holding ABJ ACC DAR DXB JNB FIH LGW LOS LUN BOM NBO plus hub EBB; no-stock turnaround BJM HRE JUB KGL JRO MGQ MBA ZNZ. The ledger refuses stock at a no-stock station.
- Database suite: 299 checks.

## Equipment Exchange MVP — Step 3: exchange cases (migration 033)
- **Model:** `equipment_exchanges` is the parent case. Its outbound (hub to outstation) and return (outstation to hub) movements are ordinary transfers linked by `exchange_id` and `exchange_leg`, so every transfer rule applies unchanged. Status and next action are derived in `v_equipment_exchanges`, never typed in.
- **Rules:** a flight is required on both legs; only stock-holding outstations take part (turnaround stations are loaded by the hub for both sectors); the return can start only after the outstation has received the outbound; return items and quantities are independent of the outbound; one active leg of each kind per exchange; a repeated "start" with the same key returns the same exchange.
- **Closing:** `close_exchange` needs `reconcile_transfer` and both legs CLOSED. Close without a return is a two-person exception: someone with `create_transfer` requests it with a reason of 10+ characters; a different person with `approve_transfer` approves or declines with a note; approval needs the outbound closed and no return. Both steps are audited.
- **Screens:** Exchanges list, New exchange, and an exchange page with both legs, progress steps, next action and actions. Transfer pages link back to their exchange.
- **Tests:** `tests/11_exchange_cases.sql`, 64 checks. Suite: 363. Fixtures gained two NBO users.
- **Open policy question:** return movements use the normal approval (a second person at the outstation). A one-person outstation may need a different rule.
- **Not done yet:** receipt with condition, partial receipt and held excess (Step 4); a browser check of all screens (final stage).
- **Run migrations 030, 031, 032, 033 in that order in the project the live app uses.**
