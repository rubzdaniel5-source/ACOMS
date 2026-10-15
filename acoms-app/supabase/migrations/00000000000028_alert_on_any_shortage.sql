-- ============================================================================
-- ACOMS Migration 028: alert on ANY shortage for chosen items (trolleys)
--
-- Each station already has its own required level per item (station stock
-- levels). For most items a plain shortage is only shown on the Inventory
-- Health card; only a CRITICAL shortage raises an alert. For items marked
-- alert_on_any_shortage, being even one unit under the station's required
-- level raises an alert. Switched on for the Atlas trolleys (R052, R053).
-- ============================================================================

alter table equipment_types add column if not exists alert_on_any_shortage boolean not null default false;

update equipment_types set alert_on_any_shortage = true where source_code in ('R052', 'R053');

create or replace function set_equipment_shortage_alert(p_id uuid, p_value boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid := _require_manage_catalogue(); v_old boolean;
begin
  select alert_on_any_shortage into v_old from equipment_types where id = p_id and organization_id = v_org;
  if not found then raise exception 'Equipment type not found'; end if;
  update equipment_types set alert_on_any_shortage = coalesce(p_value, false) where id = p_id;
  perform write_audit_log(v_org, 'catalogue.shortage_alert_set', 'equipment_type', p_id, null,
    jsonb_build_object('alert_on_any_shortage', v_old), jsonb_build_object('alert_on_any_shortage', coalesce(p_value, false)), null);
end;
$$;
revoke execute on function set_equipment_shortage_alert(uuid, boolean) from public, anon;
grant execute on function set_equipment_shortage_alert(uuid, boolean) to authenticated;

-- Same view as before with one column appended at the end.
create or replace view v_inventory_health as
with cfg as (select get_setting('health.critical_shortage_ratio') as cs, get_setting('health.shortage_ratio') as sh,
                    get_setting('health.surplus_ratio') as su, get_setting('health.critical_surplus_ratio') as cu)
select
  s.id as station_id, s.code as station_code, s.name as station_name,
  et.id as equipment_type_id, et.source_code, et.name as equipment_name,
  coalesce(ib.available_quantity, 0) as current_stock,
  coalesce(ssl.reorder_threshold, et.reorder_threshold) as minimum_level,
  coalesce(ib.available_quantity, 0) - coalesce(ssl.reorder_threshold, et.reorder_threshold) as variance,
  case
    when ib.available_quantity is null then 'NO_DATA'
    when coalesce(ssl.reorder_threshold, et.reorder_threshold) is null
      or coalesce(ssl.reorder_threshold, et.reorder_threshold) = 0 then 'NO_THRESHOLD_SET'
    when ib.available_quantity < coalesce(ssl.reorder_threshold, et.reorder_threshold) * cfg.cs then 'CRITICAL_SHORTAGE'
    when ib.available_quantity < coalesce(ssl.reorder_threshold, et.reorder_threshold) * cfg.sh then 'SHORTAGE'
    when ib.available_quantity <= coalesce(ssl.reorder_threshold, et.reorder_threshold) * cfg.su then 'NORMAL'
    when ib.available_quantity <= coalesce(ssl.reorder_threshold, et.reorder_threshold) * cfg.cu then 'SURPLUS'
    else 'CRITICAL_SURPLUS'
  end as status,
  (ssl.reorder_threshold is not null) as has_station_override,
  et.alert_on_any_shortage
from stations s
cross join equipment_types et
cross join cfg
left join inventory_balances ib on ib.station_id = s.id and ib.equipment_type_id = et.id
left join station_stock_levels ssl on ssl.station_id = s.id and ssl.equipment_type_id = et.id
where s.is_active and et.is_active and s.station_type <> 'NO_STOCK_TURNAROUND';

alter view v_inventory_health set (security_invoker = true);
