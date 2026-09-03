# ACOMS System Architecture

ACOMS is a modular operational platform.

## Modules
- Equipment: catalogue, inventory, movement, transfer, exchange, receiving, reconciliation, damage, loss.
- Meals: catalogue, menus, orders, production, dispatch, special meals.
- Flights: flights, aircraft, routes/sectors, passenger/cabin context.
- Reporting: operational and management reporting.
- Notifications: alerts and action notifications.
- AI: future analytics, forecasting, recommendations and natural-language access.

## Shared Services
Authentication, authorization, audit, storage, notifications, configuration, observability.

## Rules
Clear module boundaries; stable ownership of shared entities; avoid circular dependencies; business logic outside UI; preserve history; explicit state transitions; integration adapters.
