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
