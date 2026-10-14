-- ============================================================================
-- ACOMS Migration 022: System Settings (Admin Batch 5)
--
-- The provisional operating rules that were hard-coded in views and functions
-- become editable settings: stock-health ratios, overdue-transfer limits,
-- default reconciliation tolerances and the minimum adjustment note length.
-- setting_definitions holds the catalogue of settings and their defaults and
-- safe ranges; system_settings holds this organisation's overrides.
-- ============================================================================

create table setting_definitions (
  key text primary key,
  category text not null,
  label text not null,
  description text not null,
  unit text not null,
  default_value numeric not null,
  min_value numeric not null,
  max_value numeric not null,
  step numeric not null default 1,
  sort_order integer not null default 0,
  check (min_value <= default_value and default_value <= max_value)
);

create table system_settings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete cascade,
  key text not null references setting_definitions(key) on delete cascade,
  value numeric not null,
  updated_by uuid references user_profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  unique (organization_id, key)
);

alter table setting_definitions enable row level security;
alter table system_settings enable row level security;
create policy "setting_definitions_select" on setting_definitions for select using (auth.uid() is not null);
create policy "system_settings_select" on system_settings for select using (
  organization_id = auth_organization_id() and auth_has_permission('manage_configuration'));
-- No write policies: changes go through update_setting() / reset_setting().

insert into setting_definitions (key, category, label, description, unit, default_value, min_value, max_value, step, sort_order) values
 ('health.critical_shortage_ratio', 'Stock health', 'Critical shortage below', 'Stock under this fraction of the reorder threshold is a critical shortage.', '× reorder threshold', 0.5, 0.05, 1, 0.05, 10),
 ('health.shortage_ratio', 'Stock health', 'Shortage below', 'Stock under this multiple of the reorder threshold is a shortage.', '× reorder threshold', 1, 0.1, 2, 0.05, 20),
 ('health.surplus_ratio', 'Stock health', 'Surplus above', 'Stock above this multiple of the reorder threshold is a surplus.', '× reorder threshold', 3, 1, 20, 0.5, 30),
 ('health.critical_surplus_ratio', 'Stock health', 'Critical surplus above', 'Stock above this multiple of the reorder threshold is a critical surplus.', '× reorder threshold', 5, 1, 50, 0.5, 40),
 ('transfers.approval_overdue_hours', 'Transfers', 'Approval overdue after', 'A requested transfer not yet approved is flagged overdue after this long.', 'hours', 48, 1, 720, 1, 50),
 ('transfers.total_overdue_days', 'Transfers', 'Open transfer overdue after', 'An approved or moving transfer is flagged overdue this long after it was requested.', 'days', 7, 1, 90, 1, 60),
 ('catalogue.default_tolerance_quantity', 'Catalogue', 'Default tolerance, counted items', 'Reconciliation tolerance given to new counted items (individually tracked items are always 0).', 'units', 1, 0, 50, 1, 70),
 ('catalogue.default_tolerance_consumable', 'Catalogue', 'Default tolerance, consumables', 'Reconciliation tolerance given to new consumable items.', 'units', 2, 0, 100, 1, 80),
 ('adjustments.min_note_length', 'Adjustments', 'Minimum explanation length', 'Fewest characters required in the explanation of a stock adjustment.', 'characters', 10, 5, 200, 1, 90);

-- Effective value for the caller's organisation (falls back to the default).
create or replace function get_setting(p_key text) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select s.value from system_settings s where s.key = p_key and s.organization_id = auth_organization_id()),
    (select d.default_value from setting_definitions d where d.key = p_key));
$$;
revoke execute on function get_setting(text) from public, anon;
grant execute on function get_setting(text) to authenticated;

-- Effective settings with metadata, for the admin page.
create or replace function admin_list_settings()
returns table (key text, category text, label text, description text, unit text, default_value numeric,
               min_value numeric, max_value numeric, step numeric, value numeric, is_overridden boolean,
               updated_at timestamptz, updated_by_name text)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null or auth_organization_id() is null then raise exception 'Not authenticated'; end if;
  if not auth_has_permission('manage_configuration') then raise exception 'Permission denied: manage_configuration required'; end if;
  return query
  select d.key, d.category, d.label, d.description, d.unit, d.default_value, d.min_value, d.max_value, d.step,
         coalesce(s.value, d.default_value), (s.id is not null), s.updated_at, up.full_name
  from setting_definitions d
  left join system_settings s on s.key = d.key and s.organization_id = auth_organization_id()
  left join user_profiles up on up.id = s.updated_by
  order by d.sort_order;
end;
$$;

create or replace function update_setting(p_key text, p_value numeric, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_org uuid := auth_organization_id(); v_def setting_definitions%rowtype; v_old numeric; v_id uuid;
  v_cs numeric; v_sh numeric; v_su numeric; v_cu numeric;
begin
  if auth.uid() is null or v_org is null then raise exception 'Not authenticated'; end if;
  if not auth_has_permission('manage_configuration') then raise exception 'Permission denied: manage_configuration required'; end if;
  select * into v_def from setting_definitions where key = p_key;
  if not found then raise exception 'Unknown setting'; end if;
  if p_value is null or p_value < v_def.min_value or p_value > v_def.max_value then
    raise exception '% must be between % and %', v_def.label, v_def.min_value, v_def.max_value;
  end if;
  v_old := get_setting(p_key);

  -- Stock-health ratios must stay in order: critical shortage < shortage < surplus < critical surplus.
  if p_key like 'health.%' then
    v_cs := case when p_key = 'health.critical_shortage_ratio' then p_value else get_setting('health.critical_shortage_ratio') end;
    v_sh := case when p_key = 'health.shortage_ratio' then p_value else get_setting('health.shortage_ratio') end;
    v_su := case when p_key = 'health.surplus_ratio' then p_value else get_setting('health.surplus_ratio') end;
    v_cu := case when p_key = 'health.critical_surplus_ratio' then p_value else get_setting('health.critical_surplus_ratio') end;
    if not (v_cs < v_sh and v_sh < v_su and v_su < v_cu) then
      raise exception 'Ratios must increase in order: critical shortage (%) < shortage (%) < surplus (%) < critical surplus (%)', v_cs, v_sh, v_su, v_cu;
    end if;
  end if;

  insert into system_settings (organization_id, key, value, updated_by) values (v_org, p_key, p_value, auth.uid())
  on conflict (organization_id, key) do update set value = excluded.value, updated_by = auth.uid(), updated_at = now()
  returning id into v_id;
  perform write_audit_log(v_org, 'setting.update', 'setting', v_id, null,
    jsonb_build_object('key', p_key, 'value', v_old), jsonb_build_object('key', p_key, 'value', p_value), p_reason);
end;
$$;

create or replace function reset_setting(p_key text, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid := auth_organization_id(); v_row system_settings%rowtype; v_def numeric;
begin
  if auth.uid() is null or v_org is null then raise exception 'Not authenticated'; end if;
  if not auth_has_permission('manage_configuration') then raise exception 'Permission denied: manage_configuration required'; end if;
  select * into v_row from system_settings where organization_id = v_org and key = p_key;
  if not found then return; end if;
  select default_value into v_def from setting_definitions where key = p_key;
  -- A reset can also break ordering; reuse update_setting's validation for health ratios.
  if p_key like 'health.%' then
    perform update_setting(p_key, v_def, p_reason);
    delete from system_settings where id = v_row.id;
  else
    delete from system_settings where id = v_row.id;
    perform write_audit_log(v_org, 'setting.reset', 'setting', v_row.id, null,
      jsonb_build_object('key', p_key, 'value', v_row.value), jsonb_build_object('key', p_key, 'value', v_def), p_reason);
  end if;
end;
$$;

revoke execute on function admin_list_settings(), update_setting(text, numeric, text), reset_setting(text, text) from public, anon;
grant execute on function admin_list_settings(), update_setting(text, numeric, text), reset_setting(text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- Views now read their rules from settings (one-row cfg join keeps it cheap).
-- ----------------------------------------------------------------------------
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
  (ssl.reorder_threshold is not null) as has_station_override
from stations s
cross join equipment_types et
cross join cfg
left join inventory_balances ib on ib.station_id = s.id and ib.equipment_type_id = et.id
left join station_stock_levels ssl on ssl.station_id = s.id and ssl.equipment_type_id = et.id
where s.is_active and et.is_active and s.station_type <> 'NO_STOCK_TURNAROUND';

create or replace view v_station_inventory_status as
with cfg as (select get_setting('health.shortage_ratio') as sh, get_setting('health.surplus_ratio') as su)
select
  s.id as station_id, s.code as station_code, s.name as station_name, s.station_type,
  et.id as equipment_type_id, et.source_code, et.name as equipment_name,
  ib.available_quantity, ib.in_transit_quantity, ib.damaged_quantity, ib.missing_quantity,
  coalesce(ssl.reorder_threshold, et.reorder_threshold) as reorder_threshold,
  case
    when ib.available_quantity is null then 'NO_DATA'
    when coalesce(ssl.reorder_threshold, et.reorder_threshold) is null then 'NO_THRESHOLD_SET'
    when ib.available_quantity < coalesce(ssl.reorder_threshold, et.reorder_threshold) * cfg.sh then 'SHORTAGE'
    when ib.available_quantity > coalesce(ssl.reorder_threshold, et.reorder_threshold) * cfg.su then 'SURPLUS'
    else 'NORMAL'
  end as stock_status
from stations s
cross join equipment_types et
cross join cfg
left join inventory_balances ib on ib.station_id = s.id and ib.equipment_type_id = et.id
left join station_stock_levels ssl on ssl.station_id = s.id and ssl.equipment_type_id = et.id
where s.is_active and et.is_active and s.station_type <> 'NO_STOCK_TURNAROUND';

create or replace view v_pending_transfers as
with cfg as (select get_setting('transfers.approval_overdue_hours') as hrs, get_setting('transfers.total_overdue_days') as days)
select
  t.id, t.transfer_number, t.status, t.priority,
  fs.code as from_station_code, ts.code as to_station_code, t.requested_at,
  extract(epoch from (now() - t.requested_at)) / 3600 as hours_since_requested,
  case
    when t.status = 'REQUESTED' and now() - t.requested_at > make_interval(hours => cfg.hrs::int) then true
    when t.status in ('APPROVED', 'DISPATCHED', 'IN_TRANSIT') and now() - t.requested_at > make_interval(days => cfg.days::int) then true
    else false
  end as is_overdue
from equipment_transfers t
join stations fs on fs.id = t.from_station_id
join stations ts on ts.id = t.to_station_id
cross join cfg
where t.status not in ('CLOSED', 'REJECTED', 'CANCELLED');

alter view v_inventory_health set (security_invoker = true);
alter view v_station_inventory_status set (security_invoker = true);
alter view v_pending_transfers set (security_invoker = true);

-- ----------------------------------------------------------------------------
-- Default tolerance for new catalogue items comes from settings.
-- ----------------------------------------------------------------------------
create or replace function _merge_equipment_row(p_existing equipment_types, p_in jsonb, p_category uuid) returns jsonb
language sql stable security definer set search_path = public as $$
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
    'reconciliation_tolerance', case
        when p_in ? 'reconciliation_tolerance' then nullif(p_in->>'reconciliation_tolerance','')::int
        when p_existing.id is not null then p_existing.reconciliation_tolerance
        when coalesce(nullif(p_in->>'tracking_method',''), 'QUANTITY') = 'INDIVIDUAL' then 0
        when coalesce((p_in->>'is_consumable')::boolean, false) then get_setting('catalogue.default_tolerance_consumable')::int
        else get_setting('catalogue.default_tolerance_quantity')::int end,
    'notes', case when p_in ? 'notes' then nullif(trim(p_in->>'notes'), '') else p_existing.notes end
  );
$$;
revoke execute on function _merge_equipment_row(equipment_types, jsonb, uuid) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- Adjustment explanation length now comes from settings.
-- ----------------------------------------------------------------------------
alter table stock_adjustments drop constraint if exists stock_adjustments_notes_check;
alter table stock_adjustments add constraint stock_adjustments_notes_check check (length(trim(notes)) >= 5);

do $$
declare v_def text;
begin
  v_def := pg_get_functiondef('request_stock_adjustment(uuid, uuid, text, integer, text, text)'::regprocedure);
  v_def := replace(v_def, 'if coalesce(length(trim(p_notes)), 0) < 10 then raise exception ''Explain the adjustment (at least 10 characters)''; end if;',
    'if coalesce(length(trim(p_notes)), 0) < get_setting(''adjustments.min_note_length'') then raise exception ''Explain the adjustment (at least % characters)'', get_setting(''adjustments.min_note_length'')::int; end if;');
  if v_def not like '%adjustments.min_note_length%' then raise exception 'Failed to patch request_stock_adjustment'; end if;
  execute v_def;
end $$;
