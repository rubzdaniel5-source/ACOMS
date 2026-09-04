# Equipment Transfer and Exchange Requirements

## Lifecycle
`DRAFT → REQUESTED → APPROVED → DISPATCHED → IN_TRANSIT → RECEIVED → RECONCILIATION → CLOSED`

Exceptions: REJECTED, CANCELLED, PARTIALLY_RECEIVED, DISPUTED, DISCREPANCY.

## Required Data
Transfer ID; source/destination station/location; requester; dates; approval; dispatch; receiving; reason; priority; related flight/operation; equipment lines; requested/approved/dispatched/received quantities; discrepancy; attachments; state timestamps.

## Workflow
1. Request
2. Approval
3. Dispatch with actual quantity
4. In transit
5. Receive actual quantity/condition
6. Reconcile
7. Close only when resolved

## Reconciliation
`Dispatched = Received + Damaged + Missing + Other Approved Explanation`

Unexplained differences remain open.

## Exchange
Exchange is a controlled transfer process. Future optimization may recommend exchanges based on shortage and surplus.

## Integrity
Prevent bypassing approval, over-receiving without authorized exception, and silent closure or alteration of completed transactions.
