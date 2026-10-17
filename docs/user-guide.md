# ACOMS User Guide

For catering staff, supervisors and managers. This guide covers daily work. System setup is in the Admin section at the end.

## 1. Signing in
- Sign in with the email and password you were given. If you were given a temporary password, ACOMS asks you to choose your own before anything else.
- The top bar shows your name, **Settings** (theme, password) and **Log out**. Tabs: Dashboard, Exchanges, Transfers, Damage & Loss, Reports (and Admin if you are allowed in).
- You only see and change stations you have been assigned to.
- A thin bar at the top of the screen means a page is loading. Wait for it to finish before clicking again.

## 2. Who can do what
| Role | Typical actions |
|---|---|
| Catering assistant (base / outstation) | Request, dispatch, receive, report damage |
| Stores officer | Same as assistants, plus the equipment catalogue |
| Station manager | Approve, dispatch, receive, reconcile, confirm loss |
| Catering supervisor | Approve, dispatch, receive, confirm loss, **approve dispatches below the minimum level** |
| Catering manager | All of the above across the network |
| System administrator | Users, roles, stations, settings |

The person who requests a transfer cannot approve it.

## 3. Equipment exchange (the main daily task)
An exchange sends equipment from the base to an outstation and brings back what the flight returns. The base starts it.

### 3.1 Start a new exchange (base)
1. **Exchanges → New exchange.**
2. Choose the **destination** (outstation).
3. Choose the **flight** from the list. It shows the next 14 days of flights on that route, for example "Sat, 17 Oct · UR200".
   - Flight not in the list? Open **Flight not in the list?**, enter the date, number and a short reason. The flight is saved as *unverified* and a station manager confirms it later. You can carry on.
4. Fill in the **equipment table**:
   - Tick **Send** for each item going out. The cursor jumps to **Quantity**; type the number.
   - **Advice** shows what the base holds, what the outstation holds and, on a return, what was received from the hub.
   - A warning appears if you ask for more than the base holds.
   - Only items the base holds are listed. Switch on **Show all equipment** to see the rest.
   - Use **Search**, **Selected only** or **Clear all** to find your way around.
   - **Repeat last exchange to {station}** copies the last exchange's items and quantities. Check them, then change what differs.
5. Add a reason if you want (optional) and press **Start exchange**.

### 3.2 The exchange page
It shows the outbound transfer, the return transfer (once recorded) and where the exchange stands. Use the buttons it offers for the next step.

### 3.3 Record the return (outstation)
1. Open the exchange and choose **Record return**.
2. Choose the flight, then tick what is being returned and the quantity. The list shows items the outstation holds. **Received from hub** in the Advice column shows what came out.
3. Press the submit button. A return needs no approval.

## 4. Transfers (any single movement)
Lifecycle: **Requested → Approved → In transit → Received → Reconciliation → Closed**. Other outcomes: Rejected, Cancelled, Partially received.

1. **Request** (Transfers → New transfer): destination, items, priority, flight (optional).
2. **Approve** (manager or supervisor, not the requester). Quantities can be lowered. A request can be rejected or cancelled before dispatch.
3. **Dispatch** (source station): confirm the quantities actually sent. Stock moves to *in transit*.
4. **Receive** (destination): count what is in front of you. Nothing is pre-filled.
5. **Reconcile**: the system compares sent and received.
6. **Close**, once every difference is explained.

### 4.1 Dispatch below the minimum level
If sending would leave the source under its minimum level, ACOMS blocks the dispatch and lists the items affected.
- A **catering supervisor or catering manager** types a clear reason (at least 10 characters) and presses **Approve dispatch below minimum**. The reason is saved in the audit log.
- Anyone else asks them, or lowers the quantities.
- Once approved, dispatch as normal.

### 4.2 Receiving
For each line enter:
- **Counted**: all units you physically counted.
- **Damaged**: how many of those are damaged.

You can receive in parts. The transfer stays *Partially received* until you tick **This is the final receipt**.
- Counting **more** than was sent: the extra units are *held for investigation*, not added to stock.
- Counting **less**: the gap stays open until it is explained.

### 4.3 Reconciling and closing
Sent = received + damaged + missing. A gap that is not explained is shown as **Unexplained**.
- Short items are **not** treated as lost automatically. They stay open until investigated.
- Items within the equipment's tolerance may close with no loss record; they are still shown as Unexplained.

### 4.4 Excess held for investigation
Open the transfer and use the **Excess** panel to move each hold through investigation to *released to stock* or *removed*. Give a reason each time.

## 5. Damage & Loss
- **Report damage**: choose the item, quantity and reason.
- **Confirm loss**: only after an investigation, by someone allowed to (station manager, supervisor, manager).
- Damaged and missing stock stays out of "available".

## 6. Dashboard and reports
- **Dashboard** cards show: Exchanges, Awaiting receipt, Excess held, shortages, and alerts that need action.
- Click a card or alert to open the matching list.
- **Reports** gives management reports.
- Alerts you may see: transfers waiting for you, excess awaiting investigation, *Flight awaiting confirmation* (station managers), stock below minimum.

## 7. Settings
Choose light, dark or system theme, and change your password.

## 8. Admin (administrators and managers)
- **Users and Roles**: create users, assign roles and stations, deactivate people.
- **Stations**, **Catalogue** (equipment), **Stock levels** (minimum levels per station), **Opening balances**.
- **Flights**: routes run every week with no end date. Add one-off flights, cancel a flight, and **Confirm** unverified flights.
- **Adjustments**: stock corrections need a reason and a second person's approval.
- **Ledger**, **Audit**: read-only history of every stock movement and action. Nothing is ever edited or deleted.
- **Integrity** and **Data quality**: checks that the figures add up.

## 9. If something goes wrong
- **Message "permission denied" or "no station access"**: you are not assigned to that station or role. Ask your manager.
- **Page seems frozen**: wait for the top bar to disappear. If it stays, reload.
- **Wrong quantity entered**: before dispatch, cancel and re-request. After dispatch, record it correctly at receipt; the difference is investigated.
- **Anything else**: tell your supervisor with the transfer number (for example EX-2026-000001).
