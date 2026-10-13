-- ============================================================================
-- ACOMS Migration 015: Equipment Control Dashboard Views
--
-- Per ACOMS_MASTER_SPEC.md §20 and current-work.md's "first major milestone".
-- These are read-only views composing data that already exists — no new
-- business logic, just answering the dashboard's core questions:
-- What do we have? Where is it? What needs attention? What's happening?
--
-- Alerts scope decision (Change Control): rather than a separate persisted
-- alerts table (risks staleness, adds schema complexity for no real benefit
-- yet), alerts are implemented as LIVE-COMPUTED sections on the dashboard,
-- reading directly from these views (shortages, overdue transfers,
-- unresolved exceptions). Satisfies master spec §50's alert categories
-- without over-engineering (CLAUDE.md > Do Not Over-Engineer). Revisit with
-- a real persisted/dismissible alerts table if operational usage shows a
-- need for acknowledgment tracking or notification delivery later.
-- ============================================================================

-- Network-wide position per equipment type: total available, in transit,
-- damaged, missing across all stations. Answers "what do we have?" at the
-- network level (master spec §39).
create or replace view v_network_inventory_summary as
select
  et.id as equipment_type_id,
  et.source_code,
  et.name,
  ec.name as category_name,
  coalesce(sum(ib.available_quantity), 0) as total_available,
  coalesce(sum(ib.in_transit_quantity), 0) as total_in_transit,
  coalesce(sum(ib.damaged_quantity), 0) as total_damaged,
  coalesce(sum(ib.missing_quantity), 0) as total_missing,
  et.reorder_threshold
from equipment_types et
join equipment_categories ec on ec.id = et.category_id
left join inventory_balances ib on ib.equipment_type_id = et.id
where et.is_active
group by et.id, et.source_code, et.name, ec.name, et.reorder_threshold;

-- Per-station position: answers "where is it?" and flags shortage/surplus
-- against the workbook-derived reorder_threshold (master spec §40 —
-- classification is threshold-based, not an invented percentage).
create or replace view v_station_inventory_status as
select
  s.id as station_id,
  s.code as station_code,
  s.name as station_name,
  s.station_type,
  et.id as equipment_type_id,
  et.source_code,
  et.name as equipment_name,
  ib.available_quantity,
  ib.in_transit_quantity,
  ib.damaged_quantity,
  ib.missing_quantity,
  et.reorder_threshold,
  case
    when ib.available_quantity is null then 'NO_DATA'
    when et.reorder_threshold is null then 'NO_THRESHOLD_SET'
    when ib.available_quantity < et.reorder_threshold then 'SHORTAGE'
    when ib.available_quantity > et.reorder_threshold * 3 then 'SURPLUS'
    else 'NORMAL'
  end as stock_status
from stations s
cross join equipment_types et
left join inventory_balances ib on ib.station_id = s.id and ib.equipment_type_id = et.id
where s.is_active and et.is_active and s.station_type <> 'NO_STOCK_TURNAROUND';

comment on view v_station_inventory_status is
  'SURPLUS threshold (3x reorder_threshold) is a placeholder heuristic, not an operationally confirmed rule — flagged per master spec §40 "do not invent arbitrary percentages". Revisit once real usage patterns are known.';

-- Pending / overdue transfers — answers "what needs action?"
create or replace view v_pending_transfers as
select
  t.id,
  t.transfer_number,
  t.status,
  t.priority,
  fs.code as from_station_code,
  ts.code as to_station_code,
  t.requested_at,
  extract(epoch from (now() - t.requested_at)) / 3600 as hours_since_requested,
  case
    when t.status = 'REQUESTED' and now() - t.requested_at > interval '48 hours' then true
    when t.status in ('APPROVED', 'DISPATCHED', 'IN_TRANSIT') and now() - t.requested_at > interval '7 days' then true
    else false
  end as is_overdue
from equipment_transfers t
join stations fs on fs.id = t.from_station_id
join stations ts on ts.id = t.to_station_id
where t.status not in ('CLOSED', 'REJECTED', 'CANCELLED');

comment on view v_pending_transfers is
  'Overdue thresholds (48h for approval, 7 days total) are provisional defaults, not operationally confirmed — adjust once real transfer cadence is known.';

-- Unresolved discrepancies and open damage/loss — answers "what needs attention?"
create or replace view v_unresolved_exceptions as
select 'TRANSFER_DISCREPANCY' as exception_type, t.id, t.transfer_number as reference, t.to_station_id as station_id, t.updated_at
from equipment_transfers t where t.status = 'DISCREPANCY'
union all
select 'DAMAGE_PENDING' as exception_type, d.id, et.source_code as reference, d.station_id, d.updated_at
from damage_reports d join equipment_types et on et.id = d.equipment_type_id
where d.status not in ('RETURNED_TO_SERVICE', 'DISPOSED')
union all
select 'LOSS_PENDING' as exception_type, l.id, et.source_code as reference, l.station_id, l.updated_at
from loss_reports l join equipment_types et on et.id = l.equipment_type_id
where l.status not in ('RECOVERED', 'CLOSED');

-- Recent activity feed — answers "what is happening?"
create or replace view v_recent_activity as
select action, entity_type, entity_id, station_id, actor_label, reason, created_at
from audit_logs
order by created_at desc
limit 100;

-- RLS on views: Postgres views run with the querying user's own permissions
-- by default (security_invoker), so the underlying table RLS (inventory_
-- balances, equipment_transfers, damage_reports, loss_reports, audit_logs)
-- already applies correctly — no separate view-level policy is needed.
-- Made explicit here since it's easy to assume otherwise.
alter view v_network_inventory_summary set (security_invoker = true);
alter view v_station_inventory_status set (security_invoker = true);
alter view v_pending_transfers set (security_invoker = true);
alter view v_unresolved_exceptions set (security_invoker = true);
alter view v_recent_activity set (security_invoker = true);
