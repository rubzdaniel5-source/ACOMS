-- ============================================================================
-- ACOMS Migration 021: Per-Station Stock Levels
--
-- Each station can have its own reorder threshold / min / target / max for
-- each equipment type. The equipment_types values remain the network-wide
-- DEFAULT; a station row overrides them. Health views use the override when
-- present.
-- ============================================================================

create table station_stock_levels (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete restrict,
  station_id uuid not null references stations(id) on delete cascade,
  equipment_type_id uuid not null references equipment_types(id) on delete cascade,
  reorder_threshold integer check (reorder_threshold >= 0),
  minimum_stock integer check (minimum_stock >= 0),
  target_stock integer check (target_stock >= 0),
  maximum_stock integer check (maximum_stock >= 0),
  updated_at timestamptz not null default now(),
  unique (station_id, equipment_type_id),
  check (minimum_stock is null or target_stock is null or minimum_stock <= target_stock),
  check (target_stock is null or maximum_stock is null or target_stock <= maximum_stock)
);
create trigger trg_station_stock_levels_updated_at before update on station_stock_levels
  for each row execute function set_updated_at();

alter table station_stock_levels enable row level security;
create policy "station_stock_levels_select" on station_stock_levels for select using (
  organization_id = auth_organization_id() and auth_has_station_access(station_id));

-- Upsert many overrides for one station. An item with all four values null
-- removes the override (the station then follows the network default).
create or replace function set_station_stock_levels(p_station_id uuid, p_items jsonb)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_org uuid := auth_organization_id(); v_el jsonb; v_eq uuid; v_n integer := 0;
  v_re int; v_mn int; v_tg int; v_mx int; v_station stations%rowtype;
begin
  if auth.uid() is null or v_org is null then raise exception 'Not authenticated'; end if;
  if not auth_has_permission('manage_catalogue') then raise exception 'Permission denied: manage_catalogue required'; end if;
  select * into v_station from stations where id = p_station_id and organization_id = v_org;
  if not found then raise exception 'Station not found'; end if;
  if not auth_has_station_access(p_station_id) then raise exception 'You have no access to this station'; end if;
  if v_station.station_type = 'NO_STOCK_TURNAROUND' then raise exception 'Station % holds no stock', v_station.code; end if;
  if jsonb_typeof(p_items) <> 'array' then raise exception 'Invalid items'; end if;

  for v_el in select * from jsonb_array_elements(p_items) loop
    v_eq := (v_el->>'equipment_type_id')::uuid;
    if not exists (select 1 from equipment_types where id = v_eq and organization_id = v_org) then
      raise exception 'Unknown equipment type';
    end if;
    v_re := nullif(v_el->>'reorder_threshold','')::int; v_mn := nullif(v_el->>'minimum_stock','')::int;
    v_tg := nullif(v_el->>'target_stock','')::int; v_mx := nullif(v_el->>'maximum_stock','')::int;
    if coalesce(v_re,0) < 0 or coalesce(v_mn,0) < 0 or coalesce(v_tg,0) < 0 or coalesce(v_mx,0) < 0 then
      raise exception 'Stock levels cannot be negative';
    end if;
    if v_re is null and v_mn is null and v_tg is null and v_mx is null then
      delete from station_stock_levels where station_id = p_station_id and equipment_type_id = v_eq;
    else
      insert into station_stock_levels (organization_id, station_id, equipment_type_id, reorder_threshold, minimum_stock, target_stock, maximum_stock)
      values (v_org, p_station_id, v_eq, v_re, v_mn, v_tg, v_mx)
      on conflict (station_id, equipment_type_id) do update
        set reorder_threshold = excluded.reorder_threshold, minimum_stock = excluded.minimum_stock,
            target_stock = excluded.target_stock, maximum_stock = excluded.maximum_stock;
    end if;
    v_n := v_n + 1;
  end loop;

  perform write_audit_log(v_org, 'station.stock_levels_set', 'station', p_station_id, p_station_id, null,
    jsonb_build_object('items', v_n), null);
  return v_n;
end;
$$;
revoke execute on function set_station_stock_levels(uuid, jsonb) from public, anon;
grant execute on function set_station_stock_levels(uuid, jsonb) to authenticated;

-- ----------------------------------------------------------------------------
-- Views: use the station override when present (columns unchanged; one added).
-- ----------------------------------------------------------------------------
create or replace view v_inventory_health as
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
    when ib.available_quantity < coalesce(ssl.reorder_threshold, et.reorder_threshold) * 0.5 then 'CRITICAL_SHORTAGE'
    when ib.available_quantity < coalesce(ssl.reorder_threshold, et.reorder_threshold) then 'SHORTAGE'
    when ib.available_quantity <= coalesce(ssl.reorder_threshold, et.reorder_threshold) * 3 then 'NORMAL'
    when ib.available_quantity <= coalesce(ssl.reorder_threshold, et.reorder_threshold) * 5 then 'SURPLUS'
    else 'CRITICAL_SURPLUS'
  end as status,
  (ssl.reorder_threshold is not null) as has_station_override
from stations s
cross join equipment_types et
left join inventory_balances ib on ib.station_id = s.id and ib.equipment_type_id = et.id
left join station_stock_levels ssl on ssl.station_id = s.id and ssl.equipment_type_id = et.id
where s.is_active and et.is_active and s.station_type <> 'NO_STOCK_TURNAROUND';

create or replace view v_station_inventory_status as
select
  s.id as station_id, s.code as station_code, s.name as station_name, s.station_type,
  et.id as equipment_type_id, et.source_code, et.name as equipment_name,
  ib.available_quantity, ib.in_transit_quantity, ib.damaged_quantity, ib.missing_quantity,
  coalesce(ssl.reorder_threshold, et.reorder_threshold) as reorder_threshold,
  case
    when ib.available_quantity is null then 'NO_DATA'
    when coalesce(ssl.reorder_threshold, et.reorder_threshold) is null then 'NO_THRESHOLD_SET'
    when ib.available_quantity < coalesce(ssl.reorder_threshold, et.reorder_threshold) then 'SHORTAGE'
    when ib.available_quantity > coalesce(ssl.reorder_threshold, et.reorder_threshold) * 3 then 'SURPLUS'
    else 'NORMAL'
  end as stock_status
from stations s
cross join equipment_types et
left join inventory_balances ib on ib.station_id = s.id and ib.equipment_type_id = et.id
left join station_stock_levels ssl on ssl.station_id = s.id and ssl.equipment_type_id = et.id
where s.is_active and et.is_active and s.station_type <> 'NO_STOCK_TURNAROUND';

alter view v_inventory_health set (security_invoker = true);
alter view v_station_inventory_status set (security_invoker = true);
