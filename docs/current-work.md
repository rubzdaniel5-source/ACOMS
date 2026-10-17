
## Exchange usability (migration 037)
- Flight schedule is continuous (route dates ignored); flights chosen from a dropdown (`upcoming_flights`).
- Flight not in the list: saved as unverified (`create_unverified_flight_leg`), a manager confirms in Admin > Flights (`confirm_flight_leg`); dashboard alert raised.
- Equipment is a table (tick, quantity, advice); shows only items the source holds, with a show-all switch; "Repeat last exchange" button; warning when quantity exceeds stock.
- Exchanges is second in the navigation.
- NOT yet built: supervisor/manager approval with reason at dispatch (awaiting clarification of what it covers).
- Verified: 443 database checks, tsc, npm test, local browser pass.
