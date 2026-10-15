# ACOMS Architecture Decisions

## ADR-001 — Platform Architecture
Build ACOMS as a modular platform from the beginning while implementing incrementally.

## ADR-002 — Progressive Development
Use Progressive Systems Development / Vertical Slice Development to avoid delaying validation with an oversized upfront specification.

## ADR-003 — Transaction-Driven Inventory
Inventory is based on traceable transactions rather than freely editable stock numbers.

## ADR-004 — Station-Scoped Authorization
Permissions include station scope where appropriate because operations are distributed.

## ADR-005 — Human-Controlled AI
AI recommendations do not autonomously perform consequential operational actions initially.

## ADR-006 — Workbook as Source Reference
The workbook informs migration but does not define the production relational data model.

## ADR-010 — UI/UX Design System (ACOMS-DESIGN-001)
Two complete themes, Aero Blue (light, default) and Slate Modern (dark), driven by central semantic tokens in `globals.css` and switched by `data-theme` on `<html>`. Settings → Appearance offers Light / Dark / System. The preference is stored only in `localStorage` (key `acoms-theme`) and applied by an inline head script before first paint; account-level sync is a later option. Legacy colour names (`--navy`, `--steel`, etc.) are aliases of the theme tokens. Documented tuning: solid action fills use `--color-action` (dark mode uses the lighter blue with dark text to meet contrast). Icons are inline SVG (`components/ui/Icon.tsx`); no new dependency. Full spec: `docs/development/ACOMS_UI_UX_Specification.md`.

## ADR-011 — Header branding
Product name is "ACOMS — Airline Catering Operations Management System". The header shows ACOMS (about 26–29 px, bold) above the full name (12–13 px). New tokens `--color-header-bg/-border/-text/-text-muted/-hover` give a light Aero Blue band in Light mode and a deep slate band in Dark mode; the tab bar below stays on the surface colour.

## ADR-012 — Theme preference is account-synced
Migration 024 adds `user_profiles.theme_preference` and `set_my_theme_preference(text)` (SECURITY DEFINER, own row only). Precedence: account preference, then this device's saved choice, then Light. The device copy in `localStorage` still drives the pre-paint script so there is no flash. Saving to the account is best-effort and never blocks the theme change. Supersedes the local-only storage note in ADR-010.

## ADR-013 — Action Required rules
Alerts are built in `features/dashboard/alerts.ts` from RLS-scoped views, one alert per unresolved condition. Critical: critical shortage, transfer discrepancy. Warning: overdue transfer (thresholds from system settings), open loss report, open damage report, critical surplus. Attention: stock adjustment awaiting approval, shown only to holders of `approve_adjustment` and never for their own request. Sorted by severity, then kind, then urgency (shortfall units for stock, age for the rest). Plain shortages are not alerts. The dashboard shows 8; `/dashboard/action-required` lists all.

## ADR-014: Phone install and offline behaviour

- ACOMS is an installable web app (manifest, icons, service worker). It opens full-screen from a phone's home screen.
- The service worker stores only the app's own static build files and a static offline screen. It never stores pages or data belonging to a signed-in user, so a shared or lost phone exposes nothing, and stock figures are never shown from memory.
- Writes are never queued while offline. A banner says the screen may be out of date and changes cannot be saved. Reason: approvals, dispatches and counts depend on current stock; replaying them later could act on stale figures and break the requester ≠ approver and quantity rules.
- Revisit queued offline writes only for a specific, low-risk action (for example saving a count as a draft) once operations asks for it.

## ADR-015: Trolleys are counted in batches (supersedes ADR-009)

- Atlas trolleys, full size (R052) and half size (R053), are counted by type like any other equipment, not one by one. Decided by the product owner on 15 Oct 2026. No individual trolley register and no QR codes for now.
- Opening stock is entered per station as counts per type. Transfers, damage, loss and adjustments (two-person approval) work on counts exactly as for other items.
- Life-cycle words map to what exists: in service = available, in transit, damaged, repair and retired = steps of the damage report, missing = loss report.
- Retiring equipment needs the new `retire_equipment` permission (catering manager, catering supervisor, system administrator). Changeable in Roles & permissions.
- Trolley tolerance stays 0: any count difference on a transfer is a discrepancy. Editable in the catalogue.
- Revisit individual tracking only if operations later needs trolley-level history.
