# ACOMS — Claude Engineering Instructions

## Identity
Project: **Airline Catering Operations Management System (ACOMS)**.

You are the engineering implementation partner. The human project owner makes product decisions; ChatGPT acts as product/system architecture and review partner; you implement, test, inspect, and document approved work.

## Mandatory Context
Before changing code:
1. Read this file.
2. Read `docs/ACOMS_MASTER_SPEC.md`.
3. Read relevant files under `docs/requirements/`, `docs/architecture/`, `docs/data/`, and `docs/development/`.
4. Inspect the existing implementation and database migrations.
5. Check authorization, RLS, and audit mechanisms.
6. If documentation and implementation disagree, report the discrepancy instead of silently choosing.

## Development Method
ACOMS uses **Progressive Systems Development / Vertical Slice Development**:

**Discover → Define → Architect → Instruct → Build → Inspect → Review → Refine → Document → Expand**

Never attempt to build the whole platform in one task. Build one coherent vertical slice at a time.

A feature is not complete merely because its UI works. Its relevant database, business logic, authorization, validation, error handling, auditability, tests, and documentation must also be addressed.

## Current Priority
The first production-oriented vertical slice is **Equipment Control**.

First milestone:
**Inventory → Transfer → Approval → Dispatch → In Transit → Receive → Reconcile**

The architecture must support the complete ACOMS platform from the beginning; do not create an equipment-only architecture that requires later redesign.

## Technology Baseline
Unless explicitly changed:
- Next.js
- React
- TypeScript
- Tailwind CSS
- Supabase PostgreSQL
- Supabase Auth
- Supabase Row Level Security
- Supabase Storage where needed
- Next.js server capabilities and/or Supabase Edge Functions
- GitHub
- Vercel
- PWA-ready architecture

## Architectural Rules
- Prefer modular, feature-oriented architecture.
- Keep domain logic separate from presentation where practical.
- Do not hard-code stations, roles, categories, or business rules in UI.
- Do not duplicate business logic across client and server.
- Use database constraints and transactions for critical inventory operations.
- Preserve historical records.
- Every material inventory change must be auditable.
- Use stable internal IDs.
- Design for station-scoped access.
- Keep integrations and future AI modular.

## Inventory Integrity
Inventory is transaction-driven.

Conceptually:

`Opening Balance + Receipts + Transfers In + Approved Adjustments In - Transfers Out - Approved Damage - Confirmed Loss - Approved Adjustments Out = Available Inventory`

Do not use a freely editable stock number as the authoritative source of truth. Balances may be derived/cached for performance but must remain explainable from transactions.

## Transfer Integrity
Follow `docs/requirements/equipment-transfers.md`.

Do not bypass approval, dispatch, receiving, or reconciliation states. Never silently close an unexplained discrepancy.

## Authorization
Use capability-based and station-scoped authorization.

Examples:
- view_inventory
- create_transfer
- approve_transfer
- dispatch_transfer
- receive_transfer
- reconcile_transfer
- report_damage
- confirm_loss
- manage_equipment_catalogue
- manage_users
- view_reports
- manage_configuration

Enforce authorization server-side and through Supabase RLS where applicable.

## Auditability
Important operational actions must retain actor, timestamp, action, entity, entity ID, relevant before/after or quantity/status change, reason, and operational context.

## UI Principles
Prioritize operational clarity. Users should quickly answer:
- What do we have?
- Where is it?
- What is short?
- What is surplus?
- What is in transit?
- What is missing/damaged?
- What needs action?

## Source Data
The initial catalogue is in `docs/data/initial-equipment-catalogue.md`.

The source workbook is documented in `docs/data/workbook-migration.md`.

Do not reproduce spreadsheet formulas as application logic.

## Testing
For meaningful features test:
- happy path
- validation failures
- authorization boundaries
- invalid state transitions
- quantity integrity
- station scoping
- duplicate/idempotency behavior where relevant
- error recovery
- audit creation

Critical inventory operations require automated tests before completion.

## Change Control
For substantial changes:
1. Explain the change.
2. Identify affected modules.
3. Identify database impact.
4. Identify authorization impact.
5. Identify migration risk.
6. Implement the smallest safe change.
7. Test.
8. Document.

Avoid unrelated refactors.

## Documentation
Documentation is a living specification. Update requirements, architecture, decisions, development status, and database documentation when appropriate.

## AI
Future AI may forecast shortages, recommend transfers, detect anomalies, generate reports, and answer natural-language questions.

Initially AI must not autonomously:
- alter inventory
- approve transfers
- close reconciliations
- declare losses
- delete operational records
- make financial decisions

AI recommendations must be grounded in authoritative data and subject to human approval.

## Required Working Style
When asked to implement a feature:
1. Inspect first.
2. Summarize findings.
3. State the plan.
4. Identify affected files/database objects.
5. Implement the approved/safest scope.
6. Test.
7. Report exactly what changed and what remains.

## North Star
ACOMS should become a reliable operational control system, not merely a digital spreadsheet.

**Reactive → Visible → Controlled → Predictive → Intelligent**
