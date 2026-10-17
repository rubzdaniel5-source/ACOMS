-- ============================================================================
-- ACOMS Migration 035: dashboard counts for exchanges and held excess (step 5)
-- Read-only views. security_invoker: each user sees counts only for what their
-- station access lets them read.
-- ============================================================================

-- Exchange cases by what needs doing next.
create or replace view v_exchange_funnel with (security_invoker = true) as
select
  count(*) filter (where status not in ('CLOSED', 'CLOSED_NO_RETURN', 'CANCELLED')) as open_exchanges,
  count(*) filter (where status = 'OUTBOUND') as outbound_in_progress,
  count(*) filter (where status = 'AWAITING_RETURN') as awaiting_return,
  count(*) filter (where status = 'RETURN_IN_PROGRESS') as return_in_progress,
  count(*) filter (where status = 'READY_TO_CLOSE') as ready_to_close,
  count(*) filter (where no_return_pending and status not in ('CLOSED', 'CLOSED_NO_RETURN', 'CANCELLED')) as no_return_pending,
  count(*) filter (where has_open_discrepancy and status not in ('CLOSED', 'CLOSED_NO_RETURN', 'CANCELLED')) as with_discrepancy
from v_equipment_exchanges;

-- Excess counted at receipt and still held (never available stock).
create or replace view v_excess_summary with (security_invoker = true) as
select
  count(*) filter (where status in ('HELD', 'INVESTIGATING')) as open_holds,
  coalesce(sum(quantity) filter (where status in ('HELD', 'INVESTIGATING')), 0)::bigint as held_units,
  count(*) filter (where status = 'HELD') as awaiting_investigation,
  count(*) filter (where status = 'INVESTIGATING') as awaiting_authorisation
from excess_holds;

-- Awaiting receipt now includes partly received transfers; partly received is also shown on its own.
create or replace view v_movement_funnel as
select
  count(*) filter (where status = 'REQUESTED') as awaiting_approval,
  count(*) filter (where status = 'APPROVED') as awaiting_dispatch,
  count(*) filter (where status = 'IN_TRANSIT') as in_transit,
  count(*) filter (where status in ('IN_TRANSIT', 'PARTIALLY_RECEIVED')) as awaiting_receipt,
  count(*) filter (where status = 'RECEIVED') as awaiting_reconciliation,
  count(*) filter (where status = 'DISCREPANCY') as disputed,
  count(*) filter (where status not in ('CLOSED', 'REJECTED', 'CANCELLED')) as total_requiring_action,
  count(*) filter (where status = 'PARTIALLY_RECEIVED') as partially_received
from equipment_transfers;
alter view v_movement_funnel set (security_invoker = true);

revoke all on v_exchange_funnel, v_excess_summary from public, anon;
grant select on v_exchange_funnel, v_excess_summary to authenticated;
