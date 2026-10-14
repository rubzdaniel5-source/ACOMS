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
