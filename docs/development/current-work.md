# ACOMS Current Development

## Milestone
**Equipment Control Dashboard v0.1**

## Goal
Establish the complete basic movement path:

**Inventory → Transfer → Approval → Dispatch → In Transit → Receive → Reconcile**

## Status
- [x] Vision
- [x] Platform architecture
- [x] Initial equipment catalogue
- [x] Workbook analysis
- [x] Claude engineering protocol
- [ ] Repository foundation
- [ ] Database schema
- [ ] Authentication
- [ ] Authorization/RLS
- [ ] Catalogue UI/API
- [ ] Inventory ledger
- [ ] Transfer workflow
- [ ] Receiving
- [ ] Reconciliation
- [ ] Dashboard
- [ ] Damage/loss
- [ ] Alerts
- [ ] Basic reports
- [ ] Automated tests

Only mark work complete after implementation, testing, review and documentation.

## UI/UX implementation (ACOMS-DESIGN-001)
Stage 1 done: tokens + Light/Dark/System, two-level header, dashboard 3x2 / 2x3, Action Required restyle, legacy slate/red utilities migrated to tokens, distinct-station count fix. Remaining: sub-KPI links to filtered lists (needs the card restructured so links are not nested), Station Inventory table review on the dashboard, loading/skeleton and stale-data states, per-route visual review in both themes, account-synced theme preference.

Stage 2 done: sub-KPI counts on the six cards open filtered lists (`/transfers?status=`, `/damage-loss?view=`, `/dashboard/station-inventory?status=`), and the dashboard carries the working Station Inventory table (search, station/equipment/status filters, sorting, pagination, Request transfer shown only with `create_transfer`). Known simplification: Equipment Overview counts have no filtered list yet; "Awaiting Receipt" and "Awaiting Reconciliation" follow the existing view definitions.

Stage 3 done: Equipment Overview counts open `?bucket=` views; loading skeletons for the dashboard and list routes; dashboard shows a dash (not zero) plus a warning when a query fails, and shows when data was loaded. Static theme audit found no literal colours left in components. Not yet done: visual review of every route at 320/360/390/768/1024/1440 in both themes (needs a browser pass against the live deployment), account-synced theme preference, restyling the legacy-shaped transfer/damage-loss screens to the new card/spacing language.

Stage 4 done: screenshot review fixes (dark-mode row dividers were near-white because Tailwind borders default to currentColor; now every border uses the theme border; table headings no longer all-caps) and the older screens (transfers list, new transfer, transfer detail and action panel, damage/loss list, report form, detail and panel) moved to shared button/input/alert/panel styles with consistent page widths, 44px targets and labelled fields. Still open: themed confirmation dialogs for dispatch/reconcile/close (reject still uses window.prompt), Reports page layout pass, account-synced theme.

Stage 5 done: themed ConfirmDialog (reject with required reason, dispatch, reconcile, close), Reports page layout pass, account-synced theme (migration 024), larger table headings, section headings and primary tabs. Remaining: admin deactivate/remove prompts still use browser dialogs; full multi-width visual review.

Stage 6 done: Action Required now includes overdue transfers and adjustments awaiting approval, shows station, quantities and next action, is de-duplicated and sorted (ADR-013), has a full list page, and refuses to show a calm empty state when a source query failed.

Stage 7 done: migration 025 adds `transfers.reconciliation_overdue_days` (default 3) and flags received-but-unreconciled and reconciled-but-unclosed transfers as overdue (Action Required shows "Reconciliation overdue"). Inventory, health and report reads now page through all rows (`lib/supabase/fetchAll.ts`) so the 1,000-row API limit can never truncate counts or exports. Tested: 25 migrations apply cleanly on a fresh database; overdue flags verified for each status at boundary ages.
