# Equipment exchange MVP: requirement-to-test map and verification record

Database tests are in `acoms-app/supabase/tests` (run with `tests/run.sh`; 405 checks at the last run).
Browser checks were run on 17 Oct 2026 against a local database built from migrations 001 to 035 (harness in `acoms-app/e2e`).

| Requirement | Database tests | Browser check |
|---|---|---|
| Cancel a transfer; new stock posted as a ledger receipt | 08_cancel_and_receipts | Not repeated |
| Concurrent safety, ownership, line membership, quantities, no double posting, atomic failure | 09_transfer_safety (row locks checked structurally) | Not repeated |
| Flight registry: UR numbers, through-flights, cancel, validated dated legs, history kept | 10_flight_registry | Admin > Flights lists 54 sectors and dated flights; flight picker on New Transfer and New Exchange |
| Exchange case: outbound hub to outstation, return outstation to hub, one active leg each, closure rules | 11_exchange_cases | Full exchange EX-2026-000001 created, outbound and return completed, closed |
| Close without a return: reason, two people, audited | 11_exchange_cases | Requested by one user (cannot decide), approved by another, closed; exchange shows "Closed without return" |
| Return needs no hub approval; one person dispatches | 11_exchange_cases | Return started as Approved, dispatched by the outstation assistant alone |
| Receiver's own count, damaged separate, nothing pre-filled | 12_receipt_condition | Form inputs empty on load; counted and damaged entered separately |
| Partial receipt | 12_receipt_condition | Partly received status and "already counted" shown; final receipt completed |
| Excess held, not available; investigate then independent authorisation; preserved figures | 12_receipt_condition | Held shown, investigator told someone else must authorise, admin accepted (and in a second case removed) |
| Shortage is not a confirmed loss | 12_receipt_condition, 11_exchange_cases | Short and missing shown separately; open loss report on the dashboard |
| Stock conservation and integrity | integrity checks in 09 and 12 | After all runs: zero integrity failures; total stock agrees with the ledger |
| Dashboard and list counts | 13_dashboard_counts | Exchanges card, Awaiting Receipt, Excess Held, damaged and missing counts checked for admin, hub and outstation users |
| Station scoping | 03 to 07 | Hub user sees only hub stock; outstation user sees outstation stock |
| Mobile layout | not applicable | No horizontal page scroll at 390 px on dashboard, transfer, exchange and new transfer |

## Found and fixed during the browser check
- A sender could see the receive form (and a receiver the dispatch form) on a transfer; the database refused the action, but the form should not show. Now hidden by station.
- A transfer in Discrepancy with held excess said "unexplained discrepancy beyond tolerance" and offered a resolve button that could not work. It now says to investigate and authorise the excess first, and the button is disabled.
- The transfer table was cut off at the right on desktop; the page is wider.
- Receive form said "Already received" for counted units; it now says "Already counted". The reconcile form shows short and damaged-on-receipt per line.

## Not covered (be honest about readiness)
- The browser check ran against a local stand-in for Supabase (PostgREST plus a sign-in stub), not the live Supabase project or Vercel. Run migrations 030 to 035 in the live project and repeat a short pass there.
- No two-session concurrency test; no check of Light/Dark themes or widths other than 1280 and 390.
- Existing behaviour observed, not changed: a short quantity within an item's tolerance that nobody explains is released from transit without a loss record. Operations should confirm this is intended.
- Open items: `request_transfer` does not verify the destination station's organisation; no notifications; thresholds and tolerances still need operations sign-off; user guide and backup plan.
