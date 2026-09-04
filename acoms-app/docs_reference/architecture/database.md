# ACOMS Database Architecture

## Domains
Identity: organizations, users, roles, permissions, role_permissions, user_roles.

Locations: stations, locations, warehouses.

Equipment: equipment_types, equipment_items, inventory transactions/balances, movements, transfers, transfer lines, receipts, receipt lines, reconciliations, damage reports, loss reports.

Flight: aircraft_types, aircraft, flights, flight_sectors.

Meals: meals, meal_types, menus, meal_orders, meal_order_items.

Platform: notifications, attachments, audit_logs.

## Ledger
Prefer transaction/ledger records as the source of operational truth. Balances may be derived/materialized for performance but must be explainable.

## Constraints
Use foreign keys, unique identifiers, quantity constraints where appropriate, status constraints, timestamps and transactional updates for critical inventory operations.

## RLS
Supabase RLS must enforce station/user access boundaries. Application and database authorization complement each other.
