-- ============================================================================
-- ACOMS Migration 016: Control Panel Dashboard Views
--
-- Supports the redesigned dashboard: 6 control cards with progressive
-- disclosure (summary + detail), per the person's specification. Extends,
-- rather than replaces, the views from migration 015.
--
-- PROVISIONAL THRESHOLDS FLAGGED: the 5-tier inventory health classification
-- below uses placeholder ratios (50%/100%/300%/500% of reorder_threshold)
-- per master spec §40's rule against inventing arbitrary percentages —
-- these are a starting default, explicitly flagged for operational
-- confirmation, not a claimed-correct business rule.
-- ============================================================================

-- 1. Equipment Overview — network-wide totals across ALL equipment types
-- combined into single numbers, as the card design calls for. Note this
-- sums different equipment types together (casseroles + trolleys + napkins
-- as one number) — a deliberate simplification per the card's own design,
-- not a claim that these units are truly equivalent.
create or replace view v_equipment_overview as
select
  coalesce(sum(available_quantity), 0) as total_available,
  coalesce(sum(in_transit_quantity), 0) as total_in_transit,
  coalesce(sum(damaged_quantity), 0) as total_damaged,
  coalesce(sum(missing_quantity), 0) as total_missing,
  coalesce(sum(available_quantity + in_transit_quantity + damaged_quantity + missing_quantity), 0) as grand_total
from inventory_balances;

-- 2. Inventory Health — 5-tier classification, replacing the 3-tier
-- version from migration 015. Ratios are provisional (see header note).
create or replace view v_inventory_health as
select
  s.id as station_id,
  s.code as station_code,
  s.name as station_name,
  et.id as equipment_type_id,
  et.source_code,
  et.name as equipment_name,
  coalesce(ib.available_quantity, 0) as current_stock,
  et.reorder_threshold as minimum_level,
  coalesce(ib.available_quantity, 0) - et.reorder_threshold as variance,
  case
    when ib.available_quantity is null then 'NO_DATA'
    when et.reorder_threshold is null or et.reorder_threshold = 0 then 'NO_THRESHOLD_SET'
    when ib.available_quantity < et.reorder_threshold * 0.5 then 'CRITICAL_SHORTAGE'
    when ib.available_quantity < et.reorder_threshold then 'SHORTAGE'
    when ib.available_quantity <= et.reorder_threshold * 3 then 'NORMAL'
    when ib.available_quantity <= et.reorder_threshold * 5 then 'SURPLUS'
    else 'CRITICAL_SURPLUS'
  end as status
from stations s
cross join equipment_types et
left join inventory_balances ib on ib.station_id = s.id and ib.equipment_type_id = et.id
where s.is_active and et.is_active and s.station_type <> 'NO_STOCK_TURNAROUND';

comment on view v_inventory_health is
  'PROVISIONAL thresholds (50%/100%/300%/500% of reorder_threshold) per master spec §40 — flagged for operational confirmation, adjust the ratios here once real usage patterns are known.';

-- 3. Equipment Movement & Exchange funnel counts.
-- NOTE: "In Transit" and "Awaiting Receipt" are the same underlying status
-- (IN_TRANSIT) in the current state machine — there is no structural
-- distinction between "still moving" and "arrived, not yet logged as
-- received" yet. Shown as the same count; a real split would need a new
-- transfer status, which is a schema change, not just a view change.
create or replace view v_movement_funnel as
select
  count(*) filter (where status = 'REQUESTED') as awaiting_approval,
  count(*) filter (where status = 'APPROVED') as awaiting_dispatch,
  count(*) filter (where status = 'IN_TRANSIT') as in_transit,
  count(*) filter (where status = 'IN_TRANSIT') as awaiting_receipt,
  count(*) filter (where status = 'RECEIVED') as awaiting_reconciliation,
  count(*) filter (where status = 'DISCREPANCY') as disputed,
  count(*) filter (where status not in ('CLOSED', 'REJECTED', 'CANCELLED')) as total_requiring_action
from equipment_transfers;

-- 4. Loss & Damage Control summary.
create or replace view v_loss_damage_summary as
select
  (select coalesce(sum(quantity), 0) from loss_reports where status in ('REPORTED', 'INVESTIGATION')) as missing_open_qty,
  (select count(*) from loss_reports where status in ('REPORTED', 'INVESTIGATION')) as missing_open_count,
  (select coalesce(sum(quantity), 0) from damage_reports where status not in ('RETURNED_TO_SERVICE', 'DISPOSED')) as damaged_open_qty,
  (select count(*) from damage_reports where status not in ('RETURNED_TO_SERVICE', 'DISPOSED')) as damaged_open_count,
  (select count(*) from loss_reports where status = 'INVESTIGATION') as under_investigation,
  (select count(*) from loss_reports where status in ('CONFIRMED_LOSS', 'CLOSED')) as confirmed_losses,
  (select count(*) from equipment_transfers where status = 'DISCREPANCY') as unresolved_transfer_discrepancies,
  (select count(*) from loss_reports where status in ('REPORTED', 'INVESTIGATION'))
    + (select count(*) from damage_reports where status not in ('RETURNED_TO_SERVICE', 'DISPOSED'))
    + (select count(*) from equipment_transfers where status = 'DISCREPANCY') as open_exceptions_total;

-- 5. Reconciliation Control summary.
-- "Unexplained Variances" treated as equivalent to Discrepancies for now —
-- flagged simplification, no separate concept exists yet in the data model.
create or replace view v_reconciliation_summary as
select
  count(*) filter (where status = 'RECEIVED') as awaiting_reconciliation,
  count(*) filter (where status = 'RECONCILIATION') as reconciled_pending_close,
  count(*) filter (where status = 'DISCREPANCY') as discrepancies,
  count(*) filter (where status = 'DISCREPANCY') as unexplained_variances,
  count(*) filter (where status = 'CLOSED') as closed_total
from equipment_transfers;

alter view v_equipment_overview set (security_invoker = true);
alter view v_inventory_health set (security_invoker = true);
alter view v_movement_funnel set (security_invoker = true);
alter view v_loss_damage_summary set (security_invoker = true);
alter view v_reconciliation_summary set (security_invoker = true);
