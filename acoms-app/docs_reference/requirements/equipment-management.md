# Equipment Management Requirements

## Catalogue
Equipment types require stable ID, code, name, category, description, unit of measure, ownership, active status, minimum/target/maximum stock where needed, reorder threshold, tracking model, notes and aliases/source descriptions.

## Inventory
Support station/location inventory, available/reserved/in-transit/damaged/missing quantities, historical balances, ledger, search and filtering.

## Tracking
Support quantity/bulk and individual/serialized tracking. Do not force serialization on quantity-managed consumables.

## Business Rules
1. Inventory changes require transactions.
2. Normal operations cannot use unexplained direct balance edits.
3. Thresholds are configurable.
4. Station-scoped users cannot automatically perform unrestricted cross-station actions.
5. Retired/disposed equipment requires authorized lifecycle transition.
6. Material changes are auditable.

## Filters
Station, category, equipment, status, shortage/surplus, date, transfer and condition.
