-- 025: flag transfers that sit unreconciled or unclosed for too long.
-- Until now only REQUESTED / APPROVED / DISPATCHED / IN_TRANSIT could be overdue,
-- so a received-but-never-reconciled transfer was invisible to Action Required.

insert into setting_definitions (key, category, label, description, unit, default_value, min_value, max_value, step, sort_order) values
 ('transfers.reconciliation_overdue_days', 'Transfers', 'Reconciliation overdue after', 'A received transfer that is not reconciled, or a reconciled one not yet closed, is flagged overdue after this long.', 'days', 3, 1, 90, 1, 65)
on conflict (key) do nothing;

-- Same columns as before, in the same order, plus two appended at the end.
create or replace view v_pending_transfers as
with cfg as (
  select get_setting('transfers.approval_overdue_hours') as hrs,
         get_setting('transfers.total_overdue_days') as days,
         get_setting('transfers.reconciliation_overdue_days') as rdays
)
select
  t.id, t.transfer_number, t.status, t.priority,
  fs.code as from_station_code, ts.code as to_station_code, t.requested_at,
  extract(epoch from (now() - t.requested_at)) / 3600 as hours_since_requested,
  case
    when t.status = 'REQUESTED' and now() - t.requested_at > make_interval(hours => cfg.hrs::int) then true
    when t.status in ('APPROVED', 'DISPATCHED', 'IN_TRANSIT') and now() - t.requested_at > make_interval(days => cfg.days::int) then true
    when t.status = 'RECEIVED' and now() - coalesce(t.received_at, t.updated_at) > make_interval(days => cfg.rdays::int) then true
    when t.status = 'RECONCILIATION' and now() - t.updated_at > make_interval(days => cfg.rdays::int) then true
    else false
  end as is_overdue,
  case
    when t.status = 'REQUESTED' then 'APPROVAL'
    when t.status in ('APPROVED', 'DISPATCHED', 'IN_TRANSIT') then 'OPEN'
    when t.status = 'RECEIVED' then 'RECONCILE'
    when t.status = 'RECONCILIATION' then 'CLOSE'
    else 'OPEN'
  end as overdue_kind,
  extract(epoch from (now() - case
    when t.status = 'RECEIVED' then coalesce(t.received_at, t.updated_at)
    when t.status = 'RECONCILIATION' then t.updated_at
    else t.requested_at end)) / 3600 as hours_in_status
from equipment_transfers t
join stations fs on fs.id = t.from_station_id
join stations ts on ts.id = t.to_station_id
cross join cfg
where t.status not in ('CLOSED', 'REJECTED', 'CANCELLED');

alter view v_pending_transfers set (security_invoker = true);
