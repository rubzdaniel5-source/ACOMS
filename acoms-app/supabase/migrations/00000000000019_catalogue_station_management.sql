-- ============================================================================
-- ACOMS Migration 019: Catalogue & Station Management (Admin Batch 3)
--
-- Direct write policies on the catalogue and stations are replaced by
-- SECURITY DEFINER functions that validate input, protect live stock and
-- open transfers, and write an audit entry for every change.
-- ============================================================================

drop policy if exists "equipment_categories_manage" on equipment_categories;
drop policy if exists "equipment_types_manage" on equipment_types;
drop policy if exists "equipment_aliases_manage" on equipment_aliases;
drop policy if exists "stations_manage" on stations;

create or replace function _require_manage_catalogue() returns uuid
language plpgsql stable security definer set search_path = public as $$
declare v_org uuid := auth_organization_id();
begin
  if auth.uid() is null or v_org is null then raise exception 'Not authenticated'; end if;
  if not auth_has_permission('manage_catalogue') then raise exception 'Permission denied: manage_catalogue required'; end if;
  return v_org;
end;
$$;

create or replace function _require_manage_configuration() returns uuid
language plpgsql stable security definer set search_path = public as $$
declare v_org uuid := auth_organization_id();
begin
  if auth.uid() is null or v_org is null then raise exception 'Not authenticated'; end if;
  if not auth_has_permission('manage_configuration') then raise exception 'Permission denied: manage_configuration required'; end if;
  return v_org;
end;
$$;

-- Stock still on the books for an equipment type (any bucket, any station).
create or replace function _equipment_stock_on_hand(p_equipment_id uuid) returns bigint
language sql stable security definer set search_path = public as $$
  select coalesce(sum(available_quantity + reserved_quantity + in_transit_quantity
                      + damaged_quantity + missing_quantity), 0)
  from inventory_balances where equipment_type_id = p_equipment_id;
$$;

-- ----------------------------------------------------------------------------
-- Equipment validation shared by single save and CSV import.
-- Returns an error message, or null when valid. p_row holds the final values.
-- ----------------------------------------------------------------------------
create or replace function _validate_equipment_row(p_row jsonb) returns text
language plpgsql immutable as $$
declare
  v_min int := nullif(p_row->>'minimum_stock','')::int;
  v_target int := nullif(p_row->>'target_stock','')::int;
  v_max int := nullif(p_row->>'maximum_stock','')::int;
  v_reorder int := nullif(p_row->>'reorder_threshold','')::int;
  v_pack int := nullif(p_row->>'pack_size','')::int;
  v_tol int := nullif(p_row->>'reconciliation_tolerance','')::int;
begin
  if coalesce(trim(p_row->>'source_code'), '') = '' then return 'Code is required'; end if;
  if coalesce(trim(p_row->>'name'), '') = '' then return 'Name is required'; end if;
  if (p_row->>'tracking_method') not in ('QUANTITY', 'INDIVIDUAL', 'BATCH') then return 'Invalid tracking method'; end if;
  if coalesce(v_min, 0) < 0 or coalesce(v_target, 0) < 0 or coalesce(v_max, 0) < 0 or coalesce(v_reorder, 0) < 0 then
    return 'Stock levels cannot be negative';
  end if;
  if v_min is not null and v_target is not null and v_min > v_target then return 'Minimum cannot exceed target'; end if;
  if v_target is not null and v_max is not null and v_target > v_max then return 'Target cannot exceed maximum'; end if;
  if v_min is not null and v_max is not null and v_min > v_max then return 'Minimum cannot exceed maximum'; end if;
  if v_pack is not null and v_pack <= 0 then return 'Pack size must be greater than zero'; end if;
  if v_pack is not null and coalesce(trim(p_row->>'packaging_unit'), '') = '' then return 'Pack size needs a packaging unit'; end if;
  if v_tol is null or v_tol < 0 then return 'Reconciliation tolerance must be zero or more'; end if;
  if (p_row->>'tracking_method') = 'INDIVIDUAL' and v_tol <> 0 then return 'Individually tracked items must have tolerance 0'; end if;
  return null;
end;
$$;

-- Normalises/merges a payload onto an existing row (or defaults) into the full value set.
create or replace function _merge_equipment_row(p_existing equipment_types, p_in jsonb, p_category uuid) returns jsonb
language sql immutable as $$
  select jsonb_build_object(
    'category_id', p_category,
    'source_code', trim(coalesce(p_in->>'source_code', p_existing.source_code)),
    'name', trim(coalesce(p_in->>'name', p_existing.name)),
    'description', case when p_in ? 'description' then nullif(trim(p_in->>'description'), '') else p_existing.description end,
    'unit_of_measure', coalesce(nullif(trim(p_in->>'unit_of_measure'), ''), p_existing.unit_of_measure, 'EACH'),
    'packaging_unit', case when p_in ? 'packaging_unit' then nullif(trim(p_in->>'packaging_unit'), '') else p_existing.packaging_unit end,
    'pack_size', case when p_in ? 'pack_size' then nullif(p_in->>'pack_size','')::int else p_existing.pack_size end,
    'tracking_method', coalesce(nullif(p_in->>'tracking_method',''), p_existing.tracking_method, 'QUANTITY'),
    'is_consumable', case when p_in ? 'is_consumable' then (p_in->>'is_consumable')::boolean else coalesce(p_existing.is_consumable, false) end,
    'is_returnable', case when p_in ? 'is_returnable' then (p_in->>'is_returnable')::boolean else coalesce(p_existing.is_returnable, true) end,
    'reorder_threshold', case when p_in ? 'reorder_threshold' then nullif(p_in->>'reorder_threshold','')::int else p_existing.reorder_threshold end,
    'minimum_stock', case when p_in ? 'minimum_stock' then nullif(p_in->>'minimum_stock','')::int else p_existing.minimum_stock end,
    'target_stock', case when p_in ? 'target_stock' then nullif(p_in->>'target_stock','')::int else p_existing.target_stock end,
    'maximum_stock', case when p_in ? 'maximum_stock' then nullif(p_in->>'maximum_stock','')::int else p_existing.maximum_stock end,
    'ownership_type', case when p_in ? 'ownership_type' then nullif(trim(p_in->>'ownership_type'), '') else p_existing.ownership_type end,
    'reconciliation_tolerance', case when p_in ? 'reconciliation_tolerance' then nullif(p_in->>'reconciliation_tolerance','')::int
                                     else coalesce(p_existing.reconciliation_tolerance,
                                       case when coalesce(nullif(p_in->>'tracking_method',''), 'QUANTITY') = 'INDIVIDUAL' then 0 else 1 end) end,
    'notes', case when p_in ? 'notes' then nullif(trim(p_in->>'notes'), '') else p_existing.notes end
  );
$$;

-- ----------------------------------------------------------------------------
-- Categories
-- ----------------------------------------------------------------------------
create or replace function save_equipment_category(p_id uuid, p_code text, p_name text, p_is_active boolean default true)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_org uuid := _require_manage_catalogue(); v_id uuid;
begin
  if coalesce(trim(p_name), '') = '' then raise exception 'Name is required'; end if;
  if p_id is null then
    if p_code !~ '^[A-Z][A-Z0-9_]{1,30}$' then raise exception 'Category code: 2-31 characters, capital letters, digits and underscores'; end if;
    insert into equipment_categories (organization_id, code, name, is_active)
    values (v_org, p_code, trim(p_name), true) returning id into v_id;
    perform write_audit_log(v_org, 'catalogue.category_create', 'equipment_category', v_id, null, null,
      jsonb_build_object('code', p_code, 'name', trim(p_name)), null);
  else
    update equipment_categories set name = trim(p_name), is_active = p_is_active
    where id = p_id and organization_id = v_org returning id into v_id;
    if v_id is null then raise exception 'Category not found'; end if;
    perform write_audit_log(v_org, 'catalogue.category_update', 'equipment_category', v_id, null, null,
      jsonb_build_object('name', trim(p_name), 'is_active', p_is_active), null);
  end if;
  return v_id;
end;
$$;

-- ----------------------------------------------------------------------------
-- Equipment types (create when p_id is null)
-- ----------------------------------------------------------------------------
create or replace function save_equipment_type(p_id uuid, p_category_id uuid, p_payload jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_org uuid := _require_manage_catalogue();
  v_old equipment_types%rowtype;
  v_row jsonb; v_err text; v_id uuid;
begin
  if not exists (select 1 from equipment_categories where id = p_category_id and organization_id = v_org) then
    raise exception 'Unknown category';
  end if;
  if p_id is not null then
    select * into v_old from equipment_types where id = p_id and organization_id = v_org;
    if not found then raise exception 'Equipment type not found'; end if;
  end if;

  v_row := _merge_equipment_row(v_old, p_payload, p_category_id);
  v_err := _validate_equipment_row(v_row);
  if v_err is not null then raise exception '%', v_err; end if;

  if p_id is not null and v_row->>'tracking_method' <> v_old.tracking_method
     and exists (select 1 from inventory_transactions where equipment_type_id = p_id) then
    raise exception 'Tracking method cannot change once stock movements exist for this item';
  end if;
  if exists (select 1 from equipment_types where organization_id = v_org
             and lower(source_code) = lower(v_row->>'source_code') and id is distinct from p_id)
     and lower(v_row->>'source_code') not in ('x','xx','xxx','xxxx','xxxxx') then
    raise exception 'Code % is already used by another item', v_row->>'source_code';
  end if;

  if p_id is null then
    insert into equipment_types (
      organization_id, category_id, source_code, name, description, unit_of_measure, packaging_unit, pack_size,
      tracking_method, is_consumable, is_returnable, reorder_threshold, minimum_stock, target_stock, maximum_stock,
      ownership_type, reconciliation_tolerance, notes)
    values (v_org, p_category_id, v_row->>'source_code', v_row->>'name', v_row->>'description',
      v_row->>'unit_of_measure', v_row->>'packaging_unit', (v_row->>'pack_size')::int,
      v_row->>'tracking_method', (v_row->>'is_consumable')::boolean, (v_row->>'is_returnable')::boolean,
      (v_row->>'reorder_threshold')::int, (v_row->>'minimum_stock')::int, (v_row->>'target_stock')::int,
      (v_row->>'maximum_stock')::int, v_row->>'ownership_type', (v_row->>'reconciliation_tolerance')::int, v_row->>'notes')
    returning id into v_id;
    perform write_audit_log(v_org, 'catalogue.equipment_create', 'equipment_type', v_id, null, null, v_row, null);
  else
    update equipment_types set
      category_id = p_category_id, source_code = v_row->>'source_code', name = v_row->>'name',
      description = v_row->>'description', unit_of_measure = v_row->>'unit_of_measure',
      packaging_unit = v_row->>'packaging_unit', pack_size = (v_row->>'pack_size')::int,
      tracking_method = v_row->>'tracking_method', is_consumable = (v_row->>'is_consumable')::boolean,
      is_returnable = (v_row->>'is_returnable')::boolean, reorder_threshold = (v_row->>'reorder_threshold')::int,
      minimum_stock = (v_row->>'minimum_stock')::int, target_stock = (v_row->>'target_stock')::int,
      maximum_stock = (v_row->>'maximum_stock')::int, ownership_type = v_row->>'ownership_type',
      reconciliation_tolerance = (v_row->>'reconciliation_tolerance')::int, notes = v_row->>'notes'
    where id = p_id returning id into v_id;
    perform write_audit_log(v_org, 'catalogue.equipment_update', 'equipment_type', v_id, null, to_jsonb(v_old), v_row, null);
  end if;
  return v_id;
end;
$$;

create or replace function set_equipment_active(p_id uuid, p_active boolean, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid := _require_manage_catalogue(); v_old equipment_types%rowtype;
begin
  select * into v_old from equipment_types where id = p_id and organization_id = v_org;
  if not found then raise exception 'Equipment type not found'; end if;
  if not p_active then
    if coalesce(trim(p_reason), '') = '' then raise exception 'A reason is required to deactivate equipment'; end if;
    if _equipment_stock_on_hand(p_id) > 0 then
      raise exception 'Cannot deactivate: % units are still on the books. Dispose or transfer them first.', _equipment_stock_on_hand(p_id);
    end if;
    if exists (select 1 from equipment_transfer_items i join equipment_transfers t on t.id = i.transfer_id
               where i.equipment_type_id = p_id and t.status not in ('CLOSED','REJECTED','CANCELLED')) then
      raise exception 'Cannot deactivate: the item is on an open transfer';
    end if;
  end if;
  update equipment_types set is_active = p_active where id = p_id;
  perform write_audit_log(v_org, case when p_active then 'catalogue.equipment_activate' else 'catalogue.equipment_deactivate' end,
    'equipment_type', p_id, null, jsonb_build_object('is_active', v_old.is_active), jsonb_build_object('is_active', p_active), p_reason);
end;
$$;

-- Resolve a placeholder-code / data-quality flag: confirm the real code and clear the flag.
create or replace function resolve_data_quality_flag(p_id uuid, p_confirmed_code text, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid := _require_manage_catalogue(); v_old equipment_types%rowtype; v_code text := trim(p_confirmed_code);
begin
  select * into v_old from equipment_types where id = p_id and organization_id = v_org;
  if not found then raise exception 'Equipment type not found'; end if;
  if not v_old.has_data_quality_flag then raise exception 'This item has no open data-quality flag'; end if;
  if coalesce(v_code, '') = '' then raise exception 'Enter the confirmed code'; end if;
  if lower(v_code) in ('x','xx','xxx','xxxx','xxxxx') then raise exception 'A placeholder is not a confirmed code'; end if;
  if exists (select 1 from equipment_types where organization_id = v_org and lower(source_code) = lower(v_code) and id <> p_id) then
    raise exception 'Code % is already used by another item', v_code;
  end if;
  update equipment_types set source_code = v_code, has_data_quality_flag = false, data_quality_note = null where id = p_id;
  perform write_audit_log(v_org, 'catalogue.flag_resolved', 'equipment_type', p_id, null,
    jsonb_build_object('source_code', v_old.source_code, 'note', v_old.data_quality_note),
    jsonb_build_object('source_code', v_code), p_note);
end;
$$;

create or replace function add_equipment_alias(p_equipment_id uuid, p_alias text)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid := _require_manage_catalogue();
begin
  if not exists (select 1 from equipment_types where id = p_equipment_id and organization_id = v_org) then raise exception 'Equipment type not found'; end if;
  if coalesce(trim(p_alias), '') = '' then raise exception 'Alias is required'; end if;
  insert into equipment_aliases (equipment_type_id, alias) values (p_equipment_id, trim(p_alias))
  on conflict (equipment_type_id, alias) do nothing;
  perform write_audit_log(v_org, 'catalogue.alias_add', 'equipment_type', p_equipment_id, null, null, jsonb_build_object('alias', trim(p_alias)), null);
end;
$$;

create or replace function remove_equipment_alias(p_alias_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid := _require_manage_catalogue(); v_a equipment_aliases%rowtype;
begin
  select a.* into v_a from equipment_aliases a join equipment_types e on e.id = a.equipment_type_id
  where a.id = p_alias_id and e.organization_id = v_org;
  if not found then raise exception 'Alias not found'; end if;
  delete from equipment_aliases where id = p_alias_id;
  perform write_audit_log(v_org, 'catalogue.alias_remove', 'equipment_type', v_a.equipment_type_id, null, jsonb_build_object('alias', v_a.alias), null, null);
end;
$$;

-- ----------------------------------------------------------------------------
-- CSV import: preview (no writes) and apply (all-or-nothing).
-- Row keys: source_code, name, category (code or name), plus any optional
-- equipment fields. Existing codes are updated; unknown codes are created.
-- ----------------------------------------------------------------------------
create or replace function preview_equipment_import(p_rows jsonb)
returns table (row_number int, source_code text, action text, error text)
language plpgsql stable security definer set search_path = public as $$
declare
  v_org uuid := _require_manage_catalogue(); v_el jsonb; v_i int := 0;
  v_cat uuid; v_existing equipment_types%rowtype; v_row jsonb; v_err text; v_seen text[] := '{}';
begin
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then raise exception 'No rows supplied'; end if;
  if jsonb_array_length(p_rows) > 1000 then raise exception 'Import at most 1000 rows at a time'; end if;
  for v_el in select * from jsonb_array_elements(p_rows) loop
    v_i := v_i + 1; v_err := null; v_existing := null;
    select id into v_cat from equipment_categories
      where organization_id = v_org and (lower(code) = lower(trim(v_el->>'category')) or lower(name) = lower(trim(v_el->>'category')));
    if v_cat is null then v_err := 'Unknown category "' || coalesce(v_el->>'category','') || '"'; end if;
    if v_err is null then
      select * into v_existing from equipment_types where organization_id = v_org and lower(equipment_types.source_code) = lower(trim(v_el->>'source_code'));
      begin
        v_row := _merge_equipment_row(v_existing, v_el, v_cat);
        v_err := _validate_equipment_row(v_row);
      exception when others then v_err := 'Invalid number in row'; end;
    end if;
    if v_err is null and lower(trim(v_el->>'source_code')) = any(v_seen) and lower(trim(v_el->>'source_code')) not in ('x','xx','xxx','xxxx','xxxxx') then
      v_err := 'Code appears more than once in the file';
    end if;
    v_seen := v_seen || lower(trim(coalesce(v_el->>'source_code','')));
    return query select v_i, trim(v_el->>'source_code'),
      case when v_err is not null then 'error' when v_existing.id is not null then 'update' else 'create' end, v_err;
  end loop;
end;
$$;

create or replace function apply_equipment_import(p_rows jsonb)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_org uuid := _require_manage_catalogue(); v_el jsonb; v_i int := 0;
  v_cat uuid; v_existing equipment_types%rowtype; v_bad record;
begin
  select * into v_bad from preview_equipment_import(p_rows) where action = 'error' limit 1;
  if found then raise exception 'Row %: %', v_bad.row_number, v_bad.error; end if;
  for v_el in select * from jsonb_array_elements(p_rows) loop
    v_i := v_i + 1; v_existing := null;
    select id into v_cat from equipment_categories
      where organization_id = v_org and (lower(code) = lower(trim(v_el->>'category')) or lower(name) = lower(trim(v_el->>'category')));
    select * into v_existing from equipment_types where organization_id = v_org and lower(equipment_types.source_code) = lower(trim(v_el->>'source_code'));
    perform save_equipment_type(v_existing.id, v_cat, v_el - 'category');
  end loop;
  perform write_audit_log(v_org, 'catalogue.import', 'equipment_type', gen_random_uuid(), null, null, jsonb_build_object('rows', v_i), 'CSV import');
  return v_i;
end;
$$;

-- ----------------------------------------------------------------------------
-- Stations
-- ----------------------------------------------------------------------------
create or replace function save_station(
  p_id uuid, p_code text, p_name text, p_station_type text,
  p_airport_code text default null, p_country text default null, p_timezone text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_org uuid := _require_manage_configuration(); v_old stations%rowtype; v_id uuid;
begin
  if coalesce(trim(p_name), '') = '' then raise exception 'Name is required'; end if;
  if p_station_type not in ('HUB','STOCK_HOLDING','NO_STOCK_TURNAROUND') then raise exception 'Invalid station type'; end if;
  if p_station_type = 'HUB' and exists (select 1 from stations where organization_id = v_org and station_type = 'HUB' and id is distinct from p_id) then
    raise exception 'There is already a hub station; only one hub is allowed';
  end if;

  if p_id is null then
    if upper(trim(p_code)) !~ '^[A-Z0-9]{2,6}$' then raise exception 'Station code: 2-6 letters or digits'; end if;
    insert into stations (organization_id, code, name, station_type, airport_code, country, timezone)
    values (v_org, upper(trim(p_code)), trim(p_name), p_station_type, nullif(trim(p_airport_code),''), nullif(trim(p_country),''), nullif(trim(p_timezone),''))
    returning id into v_id;
    perform write_audit_log(v_org, 'station.create', 'station', v_id, v_id, null,
      jsonb_build_object('code', upper(trim(p_code)), 'name', trim(p_name), 'station_type', p_station_type), null);
  else
    select * into v_old from stations where id = p_id and organization_id = v_org;
    if not found then raise exception 'Station not found'; end if;
    if p_station_type <> v_old.station_type then
      if v_old.station_type = 'HUB' then raise exception 'The hub cannot be changed to another type'; end if;
      if p_station_type = 'NO_STOCK_TURNAROUND' and exists (
        select 1 from inventory_balances where station_id = p_id
          and (available_quantity + reserved_quantity + in_transit_quantity + damaged_quantity + missing_quantity) > 0) then
        raise exception 'Cannot make this a no-stock station while it still holds stock';
      end if;
    end if;
    update stations set name = trim(p_name), station_type = p_station_type, airport_code = nullif(trim(p_airport_code),''),
      country = nullif(trim(p_country),''), timezone = nullif(trim(p_timezone),'') where id = p_id returning id into v_id;
    perform write_audit_log(v_org, 'station.update', 'station', v_id, v_id, to_jsonb(v_old),
      jsonb_build_object('name', trim(p_name), 'station_type', p_station_type), null);
  end if;
  return v_id;
end;
$$;

create or replace function set_station_active(p_id uuid, p_active boolean, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid := _require_manage_configuration(); v_old stations%rowtype;
begin
  select * into v_old from stations where id = p_id and organization_id = v_org;
  if not found then raise exception 'Station not found'; end if;
  if not p_active then
    if coalesce(trim(p_reason), '') = '' then raise exception 'A reason is required to deactivate a station'; end if;
    if v_old.station_type = 'HUB' then raise exception 'The hub station cannot be deactivated'; end if;
    if exists (select 1 from inventory_balances where station_id = p_id
        and (available_quantity + reserved_quantity + in_transit_quantity + damaged_quantity + missing_quantity) > 0) then
      raise exception 'Cannot deactivate: the station still holds stock';
    end if;
    if exists (select 1 from equipment_transfers where (from_station_id = p_id or to_station_id = p_id)
               and status not in ('CLOSED','REJECTED','CANCELLED')) then
      raise exception 'Cannot deactivate: the station has open transfers';
    end if;
  end if;
  update stations set is_active = p_active where id = p_id;
  perform write_audit_log(v_org, case when p_active then 'station.activate' else 'station.deactivate' end,
    'station', p_id, p_id, jsonb_build_object('is_active', v_old.is_active), jsonb_build_object('is_active', p_active), p_reason);
end;
$$;

revoke execute on function _require_manage_catalogue(), _require_manage_configuration(), _equipment_stock_on_hand(uuid),
  _validate_equipment_row(jsonb), _merge_equipment_row(equipment_types, jsonb, uuid) from public, anon, authenticated;

revoke execute on function save_equipment_category(uuid, text, text, boolean), save_equipment_type(uuid, uuid, jsonb),
  set_equipment_active(uuid, boolean, text), resolve_data_quality_flag(uuid, text, text),
  add_equipment_alias(uuid, text), remove_equipment_alias(uuid), preview_equipment_import(jsonb),
  apply_equipment_import(jsonb), save_station(uuid, text, text, text, text, text, text),
  set_station_active(uuid, boolean, text) from public, anon;
grant execute on function save_equipment_category(uuid, text, text, boolean), save_equipment_type(uuid, uuid, jsonb),
  set_equipment_active(uuid, boolean, text), resolve_data_quality_flag(uuid, text, text),
  add_equipment_alias(uuid, text), remove_equipment_alias(uuid), preview_equipment_import(jsonb),
  apply_equipment_import(jsonb), save_station(uuid, text, text, text, text, text, text),
  set_station_active(uuid, boolean, text) to authenticated;
