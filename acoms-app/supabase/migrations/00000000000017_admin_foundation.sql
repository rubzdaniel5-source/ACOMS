-- ============================================================================
-- ACOMS Migration 017: Admin Foundation (Batch 1)
--
-- 1. Lock down the two internal SECURITY DEFINER functions. Supabase grants
--    EXECUTE on new public functions to anon/authenticated by default, which
--    would let any logged-in user call apply_inventory_transaction() or
--    write_audit_log() directly through the API and forge stock or audit
--    entries. They are only ever meant to be called from other definer
--    functions (which run as the owner, so revoking is safe).
-- 2. record_opening_balance permission.
-- 3. record_opening_balances(): bulk, once-only per station x equipment.
-- 4. v_inventory_ledger: readable ledger view for the admin ledger page.
-- ============================================================================

revoke execute on function apply_inventory_transaction(uuid, uuid, text, integer, text, uuid, text)
  from public, anon, authenticated;
revoke execute on function write_audit_log(uuid, text, text, uuid, uuid, jsonb, jsonb, text)
  from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- Permission
-- ----------------------------------------------------------------------------
insert into permissions (code, description) values
  ('record_opening_balance', 'Record the one-time opening balance for a station and equipment type')
on conflict (code) do nothing;

insert into role_permissions (role_id, permission_id)
select r.id, p.id
from roles r, permissions p
where p.code = 'record_opening_balance'
  and r.code in ('system_admin', 'catering_manager', 'stores_officer', 'station_manager')
  and r.organization_id = (select id from organizations where code = 'UGANDA_AIRLINES')
on conflict do nothing;

-- ----------------------------------------------------------------------------
-- Database-level once-only guarantee (skipped with a notice if historic
-- duplicates already exist, so the migration can never fail on live data).
-- ----------------------------------------------------------------------------
do $$
begin
  if exists (
    select 1 from inventory_transactions
    where transaction_type = 'OPENING_BALANCE'
    group by station_id, equipment_type_id having count(*) > 1
  ) then
    raise notice 'Duplicate OPENING_BALANCE rows exist; unique index not created. Resolve via adjustments.';
  else
    create unique index if not exists uq_opening_balance_once
      on inventory_transactions (station_id, equipment_type_id)
      where transaction_type = 'OPENING_BALANCE';
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- record_opening_balances
-- p_items: [{"equipment_type_id": "<uuid>", "quantity": 12}, ...]
-- All-or-nothing: any invalid row aborts the whole batch.
-- ----------------------------------------------------------------------------
create or replace function record_opening_balances(
  p_station_id uuid,
  p_items jsonb,
  p_reason text default null
) returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org uuid := auth_organization_id();
  v_station stations%rowtype;
  v_item jsonb;
  v_eq uuid;
  v_qty integer;
  v_count integer := 0;
  v_seen uuid[] := '{}';
begin
  if auth.uid() is null or v_org is null then
    raise exception 'Not authenticated';
  end if;
  if not auth_has_permission('record_opening_balance') then
    raise exception 'Permission denied: record_opening_balance required';
  end if;

  select * into v_station from stations where id = p_station_id and organization_id = v_org;
  if not found then
    raise exception 'Station not found';
  end if;
  if not auth_has_station_access(p_station_id) then
    raise exception 'Permission denied: no access to station %', v_station.code;
  end if;
  if v_station.station_type = 'NO_STOCK_TURNAROUND' then
    raise exception 'Station % is a no-stock turnaround station and cannot hold inventory', v_station.code;
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'No items supplied';
  end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_eq := (v_item->>'equipment_type_id')::uuid;
    v_qty := (v_item->>'quantity')::integer;

    if v_qty is null or v_qty <= 0 then
      raise exception 'Quantity must be a positive whole number';
    end if;
    if v_eq = any(v_seen) then
      raise exception 'Equipment listed more than once in the same batch';
    end if;
    v_seen := v_seen || v_eq;

    if not exists (
      select 1 from equipment_types
      where id = v_eq and organization_id = v_org and is_active
    ) then
      raise exception 'Unknown or inactive equipment type %', v_eq;
    end if;

    if exists (
      select 1 from inventory_transactions
      where station_id = p_station_id and equipment_type_id = v_eq
        and transaction_type = 'OPENING_BALANCE'
    ) then
      raise exception 'Opening balance already recorded for this station and equipment; use a stock adjustment instead';
    end if;

    perform apply_inventory_transaction(
      v_eq, p_station_id, 'OPENING_BALANCE', v_qty,
      'opening_balance', null, coalesce(p_reason, 'Opening balance')
    );
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

revoke execute on function record_opening_balances(uuid, jsonb, text) from public, anon;
grant execute on function record_opening_balances(uuid, jsonb, text) to authenticated;

-- ----------------------------------------------------------------------------
-- Ledger view (security_invoker: underlying RLS still applies per user)
-- ----------------------------------------------------------------------------
create or replace view v_inventory_ledger
with (security_invoker = true) as
select
  t.id,
  t.created_at,
  s.code as station_code,
  s.name as station_name,
  e.source_code,
  e.name as equipment_name,
  t.transaction_type,
  t.quantity,
  t.reference_type,
  t.reference_id,
  t.reason,
  up.full_name as performed_by_name
from inventory_transactions t
join stations s on s.id = t.station_id
join equipment_types e on e.id = t.equipment_type_id
left join user_profiles up on up.id = t.performed_by;
