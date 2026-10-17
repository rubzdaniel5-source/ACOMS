
## Exchange usability (migration 037)
- Flight schedule is continuous (route dates ignored); flights chosen from a dropdown (`upcoming_flights`).
- Flight not in the list: saved as unverified (`create_unverified_flight_leg`), a manager confirms in Admin > Flights (`confirm_flight_leg`); dashboard alert raised.
- Equipment is a table (tick, quantity, advice); shows only items the source holds, with a show-all switch; "Repeat last exchange" button; warning when quantity exceeds stock.
- Exchanges is second in the navigation.
- Migration 038: a dispatch that leaves the source below its minimum level (station level, else equipment default; 0 or none = no minimum) is blocked until a catering supervisor or catering manager approves it with a reason (>=10 chars), audited as transfer.below_min_approve. Panel shows the lines affected.
- Verified: 456 database checks, tsc, npm test, local browser pass.
