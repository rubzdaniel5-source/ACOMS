# ACOMS — Master System Specification

**Version:** 1.0  
**Status:** Living Specification

## 1. Product Definition
ACOMS is a modular operational management platform for airline catering. It provides control over equipment, inventory, movement/exchange, receiving, reconciliation, damage/loss, meals, flights, dispatch, reporting, alerts, and future analytics/AI.

Implementation is incremental, but the architecture is platform-wide from the beginning.

## 2. Problems
ACOMS addresses equipment imbalance, shortages/surpluses, poor movement visibility, loss/damage, manual reconciliation, delayed reporting, spreadsheet dependence, weak accountability, poor historical traceability, and reactive operations.

## 3. Objectives
- Single source of operational truth
- Station/location visibility
- Equipment lifecycle and movement tracking
- Chain of custody
- Receiving and reconciliation
- Damage/loss control
- Automated reporting
- Shortage/surplus visibility
- Actionable alerts
- Flight and meal operational context
- Reliable analytics/AI foundation
- Reduced manual work
- Better accountability

## 4. Users
System Administrator; Catering Manager; Catering Planner; Equipment/Stores Officer; Dispatch Officer; Receiving Officer; Station Officer; Production Staff; Finance; Auditor; Management.

Permissions are capability-based and station-scoped.

## 5. Logical Architecture
```text
Users / Roles
      |
Application
  |-- Equipment
  |    |-- Catalogue
  |    |-- Inventory
  |    |-- Movement
  |    |-- Exchange
  |    |-- Damage
  |    |-- Loss
  |    `-- Reconciliation
  |-- Meals
  |    |-- Menus
  |    |-- Orders
  |    |-- Production
  |    |-- Dispatch
  |    `-- Special Meals
  |-- Flight Catering
  |    |-- Flights
  |    |-- Aircraft
  |    |-- Routes
  |    `-- Passenger/Cabin Context
  |-- Reporting / Analytics
  |-- Notifications / Alerts
  `-- Future AI
      |
Shared Services
  |-- Authentication
  |-- Authorization
  |-- Audit
  |-- Storage
  `-- Notifications
      |
Supabase
```

## 6. Technology
Next.js, React, TypeScript, Tailwind CSS, Supabase PostgreSQL/Auth/RLS/Storage, Next.js server capabilities and/or Edge Functions, GitHub, Vercel, PWA-ready design.

## 7. Core Entities
Organization; User; Role; Permission; Station; Location; Warehouse; Aircraft; Aircraft Type; Aircraft Configuration; Flight; Flight Sector; Equipment Type; Equipment Item; Equipment Inventory; Inventory Transaction; Equipment Movement; Equipment Transfer; Equipment Receipt; Damage Report; Loss Report; Reconciliation; Meal; Meal Type; Menu; Meal Order; Meal Order Item; Supplier; Caterer; Notification; Attachment; Audit Log.

## 8. Equipment
Support catalogue, station inventory, location inventory, bulk quantities, individual/serialized tracking, movement, transfers/exchange, approval, dispatch, receiving, reconciliation, damage, loss, retirement/disposal, thresholds, alerts, and audit history.

Tracking models:
1. Quantity/bulk
2. Individual/serialized
3. Future batch/lot where useful

Trolleys are candidates for individual tracking. QR/barcode/RFID must be future-compatible.

## 9. Inventory
Inventory is transaction-based:

`Opening + Receipts + Transfers In + Approved In - Transfers Out - Approved Damage - Confirmed Loss - Approved Out = Available`

The system must be able to explain any balance from its transaction history.

## 10. Status
Possible equipment states:
AVAILABLE, RESERVED, IN_USE, IN_TRANSIT, RECEIVED, DAMAGED, MISSING, UNDER_INVESTIGATION, RETIRED, DISPOSED.

## 11. Thresholds
Support configurable minimum, target, maximum and reorder threshold.

Classifications:
CRITICAL SHORTAGE, SHORTAGE, NORMAL, SURPLUS, CRITICAL SURPLUS.

## 12. Transfers
Lifecycle:
`DRAFT → REQUESTED → APPROVED → DISPATCHED → IN_TRANSIT → RECEIVED → RECONCILIATION → CLOSED`

Exceptions:
REJECTED, CANCELLED, PARTIALLY_RECEIVED, DISPUTED, DISCREPANCY.

Receiving records actual quantities.

## 13. Reconciliation
For each line:

`Dispatched = Received + Damaged + Missing + Other Approved Explanation`

Unexplained differences cannot be silently closed.

## 14. Damage
Lifecycle:
`REPORTED → UNDER_REVIEW → ASSESSED → REPAIR → RETURNED_TO_SERVICE`

or:
`ASSESSED → RETIRED → DISPOSED`

## 15. Loss
Lifecycle:
`REPORTED → INVESTIGATION → RECOVERED`

or:
`REPORTED → INVESTIGATION → CONFIRMED_LOSS → CLOSED`

## 16. Flights
Support flight number/date, aircraft registration/type, departure/arrival, sectors, passenger count, cabin configuration, catering station, and catering status.

## 17. Meals
Support meal catalogue, types, menus, cabins, dietary categories, effective dates, orders, production, dispatch, loading, and special meals.

Suggested lifecycle:
`DRAFT → SUBMITTED → APPROVED → IN_PRODUCTION → READY → DISPATCHED → LOADED → COMPLETED`

Exceptions: MODIFIED, CANCELLED, PARTIALLY_FULFILLED.

## 18. Dispatch
Record what, quantity, source, destination, flight/operation, time, dispatcher, receiver and status.

## 19. Reporting
Equipment: inventory, station/location, movement, transfers, pending/in-transit, missing, damaged, reconciliation, utilization, loss, shortage/surplus.

Meals: orders, production, dispatch, special meals, fulfillment, waste/consumption where data exists.

Management: station performance, shortage/surplus trends, loss/damage trends, transfer activity, unresolved exceptions.

## 20. Dashboard
Initial dashboard: total equipment, available, in transit, damaged, missing, awaiting reconciliation, pending transfers, critical shortages, surplus locations, alerts.

## 21. Alerts
Critical shortage, critical surplus, overdue transfer, reconciliation discrepancy, unusual loss, excessive damage, excess inventory.

## 22. Security
Secure authentication; least privilege; station scope; RLS; server validation; protected secrets; encrypted connections; audit logs; controlled file access; backups; session management.

## 23. PWA
PWA-ready. Complex offline synchronization is deferred unless operational evidence requires it.

## 24. Scalability
Design for growth from one airline/few stations/tens of equipment types to multiple stations/caterers, hundreds of equipment types, thousands of users and millions of transactions without fundamental redesign.

## 25. Integrations
Future scheduling, passenger/reservation systems, finance, procurement, external caterers, QR/barcode, RFID.

## 26. AI
Future forecasting, surplus prediction, transfer recommendations, anomaly detection, report generation, natural-language queries and summaries. Human approval remains required for consequential actions.

## 27. MVP
Equipment catalogue; inventory; ledger; movement; transfers; approval; dispatch; receiving; reconciliation; damage; loss; dashboard; alerts; basic reports; audit; users/roles/stations/permissions.

Advanced AI, RFID, complex integrations, advanced forecasting, meal optimization, procurement, finance and complex offline sync are deferred.

## 28. First Milestone
**Equipment Control Dashboard v0.1**

Authorized users must be able to view station inventory, identify shortage/surplus, see in-transit and pending transfers, see missing/damaged equipment and unresolved discrepancies, and execute the controlled transfer lifecycle with auditability.

## 29. Product Evolution
**Reactive → Visible → Controlled → Predictive → Intelligent**
