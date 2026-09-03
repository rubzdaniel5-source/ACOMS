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
