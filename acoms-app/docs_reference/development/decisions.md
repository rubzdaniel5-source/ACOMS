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

## ADR-007 — Requester/Approver Separation
A transfer requester can never approve their own request. Enforced server-side in the approval function, not merely hidden in the UI.

## ADR-008 — Reconciliation Tolerance
Fixed-unit tolerance, not percentage: 0 for serialized/individually-tracked items, ±1 unit for bulk equipment, ±2 units for high-volume consumables. Configurable per equipment type. Provisional pending operational validation against real data.

## ADR-009 — Individual/Serialized Trolley Tracking from MVP
Trolleys (Atlas FS/HS) are tracked as individual `equipment_items` with unique identifiers from Phase 1, not deferred to a later phase, avoiding a costly retrofit migration.

## ADR-010 — Single Organization, Multi-Tenant-Ready Schema
Production use is single-organization today. Every table is organization-scoped from the start so future adoption by other airlines does not require schema redesign. No multi-org management UI exists yet.

## ADR-011 — User Affiliation Distinct from Role
`user_profiles.affiliation` (`internal` / `external_provider`) tracks whether a user is an airline employee (e.g. base/hub Catering Assistant) or outstation service-provider staff, independent of their functional role. This supports differentiated audit visibility and security posture later without a schema change.
