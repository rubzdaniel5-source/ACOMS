# Workbook Migration Notes

Source: `Equipment Inventory-LGW.xlsx`

## Sheets
- `INVENTORY REPORT SEPTEMBER` — catalogue plus formula-derived current stock.
- `CABIN LOAD` — reorder amount and received quantity.
- `DAILY MONITORING` — date/station plus product columns for operational monitoring.
- `BREAKAGE` — date/station plus product columns for breakage.

The workbook is an operational reference, not the production data model.

## Mapping
Products → equipment types  
Stations → stations  
Receipts → receipt/inventory transactions  
Monitoring changes → inventory transactions  
Breakage → damage transactions  
Transfers/exchanges → equipment transfers  
Current balances → derived/materialized views

## Critical Rule
Do not reproduce spreadsheet formulas as application logic.

## Validate Before Production Migration
Confirm station list, units of measure, opening balances, threshold meaning, packaged-product counting basis, trolley tracking method, ambiguous codes, aliases/duplicates, aircraft compatibility and required historical period.

## Migration Strategy
1. Stage source catalogue.
2. Validate/normalize.
3. Map to ACOMS equipment types.
4. Establish stations/locations.
5. Convert reliable history to transactions.
6. Recalculate balances.
7. Compare against workbook.
8. Obtain operational sign-off.
9. Freeze migration snapshot.
