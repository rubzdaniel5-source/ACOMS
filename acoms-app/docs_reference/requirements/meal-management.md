# Meal Management Requirements

Meal management is part of the platform architecture but follows equipment control in implementation priority.

## Catalogue
Meal ID, name, description, meal type, cabin, dietary category, active status, effective dates and supplier/caterer.

## Orders
Flight/operation, date, station, cabin, meal, quantity, special meal requirements, status, requester, approval and timestamps.

## Lifecycle
`DRAFT → SUBMITTED → APPROVED → IN_PRODUCTION → READY → DISPATCHED → LOADED → COMPLETED`

Exceptions: MODIFIED, CANCELLED, PARTIALLY_FULFILLED.

Future: production planning, dispatch, aircraft loading, passenger-linked demand, waste/consumption, supplier workflows and forecasting.
