# Live browser checklist

Run this on the **live site** (the Vercel app), not on a local copy. Use real phones as well as a desktop browser. Tick each line. Write down anything odd with the page and the time.

**Before starting**
- [ ] The Supabase project the live app uses has migrations 001 to 038 run (SQL editor, in order). Check *Table editor → equipment_transfers* has `below_min_approved_by`.
- [ ] Vercel has the Supabase URL and anon key set; the service-role key is only a server-side variable, never in the code.
- [ ] Test users exist: base assistant, outstation assistant, station manager, catering supervisor, catering manager, admin.
- [ ] Opening balances are loaded for the base station.

## A. Speed and loading
- [ ] First page after sign-in appears within about 3 seconds.
- [ ] Clicking each tab shows the thin loading bar at the top immediately, then the page.
- [ ] Pages without data yet show grey placeholder blocks, not a blank screen.
- [ ] Vercel function region is near the Supabase region (Vercel → Settings → Functions; Supabase → Settings → General).

## B. Sign-in
- [ ] Wrong password shows a clear message.
- [ ] Temporary-password user is forced to set a new password.
- [ ] Log out works; the back button does not show private pages.
- [ ] Signed-out visit to /dashboard goes to the sign-in page.

## C. Navigation and layout
- [ ] Tabs in order: Dashboard, Exchanges, Transfers, Damage & Loss, Reports (Admin only for allowed users).
- [ ] No horizontal scrolling at phone width (390 px).
- [ ] Dark and light themes both readable.

## D. New exchange (base assistant)
- [ ] Destination list shows the outstations.
- [ ] Flight list shows upcoming flights, soonest first.
- [ ] Equipment table lists only what the base holds; **Show all equipment** reveals the rest.
- [ ] Ticking an item moves the cursor to Quantity.
- [ ] Quantity above stock shows a warning.
- [ ] Total line updates; **Clear all** and **Selected only** work.
- [ ] Submitting without a flight or items shows a clear message.
- [ ] Exchange is created and opens.
- [ ] **Repeat last exchange** fills in the previous items and quantities.
- [ ] **Flight not in the list?** saves an unverified flight; station manager sees the alert and **Confirm** works in Admin → Flights.

## E. Approval and dispatch
- [ ] The requester cannot approve their own transfer.
- [ ] Station manager approves; quantities can be lowered.
- [ ] Dispatch with stock above the minimum works; stock moves to in transit.
- [ ] Dispatch that leaves stock below the minimum is blocked and the items are listed.
- [ ] An assistant sees "ask a supervisor or manager"; a station manager cannot approve it.
- [ ] A catering supervisor/manager needs a reason of 10+ characters, then dispatch works.
- [ ] The reason shows on the transfer and in Admin → Audit.

## F. Return and receipt (outstation)
- [ ] Outstation sees only its own station's transfers.
- [ ] **Record return** lists items the outstation holds; "Received from hub" shows in Advice.
- [ ] Receive: nothing pre-filled; counted and damaged accepted.
- [ ] Partial receipt keeps status Partially received; final receipt moves on.
- [ ] Counting more than sent holds the extra units and does not add them to stock.

## G. Reconcile and close
- [ ] Table shows Counted, Accepted, Damaged, Excess held, Short, Missing, Unexplained.
- [ ] Closing is refused while a difference is unexplained.
- [ ] Excess hold can be investigated and released or removed, each with a reason.
- [ ] Balances after closing match: base down, outstation up, nothing negative.

## H. Damage and loss, adjustments
- [ ] Report damage reduces available stock.
- [ ] Confirm loss is refused for roles without permission.
- [ ] Stock adjustment needs a reason and a second person's approval.

## I. Dashboard and reports
- [ ] Cards and alerts show correct counts; clicking opens the matching list.
- [ ] Reports open without errors.

## J. Security spot checks
- [ ] A user from one station cannot open another station's transfer by pasting its address.
- [ ] A non-admin typing /admin sees nothing or is refused.
- [ ] The Network tab shows no service-role key anywhere.
- [ ] Audit log has an entry for every step you just did.

## K. Mobile and offline
- [ ] On a phone: sign in, create an exchange, receive a transfer.
- [ ] Installing to home screen works; offline page appears when there is no signal.

## Sign-off
Tested by: __________  Date: __________  Browser/device: __________  Result: pass / needs fixes
