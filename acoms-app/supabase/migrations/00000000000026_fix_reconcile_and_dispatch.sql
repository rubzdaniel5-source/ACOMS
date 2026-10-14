-- ============================================================================
-- ACOMS Migration 026: two inventory bugs found by the automated tests
--
-- 1. reconcile_transfer debited DAMAGE/LOSS from the destination's AVAILABLE
--    stock, but those units were never received into it, so they were deducted
--    twice (10 sent, 7 received, 1 damaged, 2 missing left 4 available, not 7)
--    and the damaged/missing buckets stayed at zero.
--    Now each damaged or missing unit is credited to the destination as it is
--    found (TRANSFER_IN) and then moved out of available by a DAMAGE / LOSS
--    entry, exactly as report_damage / report_loss do. A real damage or loss
--    report is opened for it, so it enters the normal workflow, the buckets
--    fill, and the integrity checks keep matching.
--
-- 2. dispatch_transfer accepted any quantity up to what the source held, and
--    any item id. It now refuses items that are not on the transfer, negative
--    quantities, and more than was approved.
--
-- Transfers reconciled BEFORE this migration keep their old (double-deducted)
-- figures; correct those with a stock adjustment if any exist.
-- ============================================================================

create or replace function dispatch_transfer(
  p_transfer_id uuid,
  p_dispatched_items jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_transfer equipment_transfers%rowtype;
  v_item jsonb;
  v_line equipment_transfer_items%rowtype;
  v_qty integer;
begin
  select * into v_transfer from equipment_transfers where id = p_transfer_id;
  if not found then raise exception 'Transfer % not found', p_transfer_id; end if;
  if v_transfer.status <> 'APPROVED' then
    raise exception 'Transfer must be APPROVED to dispatch (current status: %)', v_transfer.status;
  end if;
  if not auth_has_permission('dispatch_transfer') then
    raise exception 'Missing permission: dispatch_transfer';
  end if;
  if not auth_has_station_access(v_transfer.from_station_id) then
    raise exception 'No station access to source station';
  end if;

  for v_item in select * from jsonb_array_elements(p_dispatched_items)
  loop
    v_qty := (v_item->>'quantity_dispatched')::integer;

    select * into v_line from equipment_transfer_items
    where id = (v_item->>'item_id')::uuid and transfer_id = p_transfer_id;
    if not found then raise exception 'Item does not belong to this transfer'; end if;
    if v_qty is null or v_qty < 0 then raise exception 'Dispatched quantity cannot be negative'; end if;
    if v_qty > coalesce(v_line.quantity_approved, v_line.quantity_requested) then
      raise exception 'Cannot dispatch % of an item approved for %', v_qty, coalesce(v_line.quantity_approved, v_line.quantity_requested);
    end if;

    update equipment_transfer_items set quantity_dispatched = v_qty where id = v_line.id;

    if v_qty > 0 then
      perform apply_inventory_transaction(
        v_line.equipment_type_id, v_transfer.from_station_id, 'TRANSFER_OUT', v_qty,
        'equipment_transfer', p_transfer_id, 'Dispatched on transfer ' || v_transfer.transfer_number
      );
      update inventory_balances
      set in_transit_quantity = in_transit_quantity + v_qty, updated_at = now()
      where equipment_type_id = v_line.equipment_type_id and station_id = v_transfer.from_station_id;
    end if;
  end loop;

  update equipment_transfers
  set status = 'IN_TRANSIT', dispatched_by = auth.uid(), dispatched_at = now()
  where id = p_transfer_id;

  perform write_audit_log(v_transfer.organization_id, 'transfer.dispatch', 'equipment_transfer', p_transfer_id,
    v_transfer.from_station_id, jsonb_build_object('status', 'APPROVED'),
    jsonb_build_object('status', 'IN_TRANSIT'), null);
end;
$$;

create or replace function reconcile_transfer(
  p_transfer_id uuid,
  p_reconciliation_items jsonb,
  p_notes text default null
) returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_transfer equipment_transfers%rowtype;
  v_item jsonb;
  v_line equipment_transfer_items%rowtype;
  v_tolerance integer;
  v_unexplained integer;
  v_damaged integer;
  v_missing integer;
  v_report uuid;
  v_has_discrepancy boolean := false;
  v_final_status text;
begin
  select * into v_transfer from equipment_transfers where id = p_transfer_id;
  if not found then raise exception 'Transfer % not found', p_transfer_id; end if;
  if v_transfer.status <> 'RECEIVED' then
    raise exception 'Transfer must be RECEIVED to reconcile (current status: %)', v_transfer.status;
  end if;
  if not auth_has_permission('reconcile_transfer') then
    raise exception 'Missing permission: reconcile_transfer';
  end if;
  if not (auth_has_station_access(v_transfer.from_station_id) or auth_has_station_access(v_transfer.to_station_id)) then
    raise exception 'No station access to either side of this transfer';
  end if;

  for v_item in select * from jsonb_array_elements(p_reconciliation_items)
  loop
    v_damaged := coalesce((v_item->>'quantity_damaged')::integer, 0);
    v_missing := coalesce((v_item->>'quantity_missing')::integer, 0);
    if v_damaged < 0 or v_missing < 0 then raise exception 'Damaged and missing quantities cannot be negative'; end if;

    update equipment_transfer_items
    set quantity_damaged = v_damaged, quantity_missing = v_missing
    where id = (v_item->>'item_id')::uuid and transfer_id = p_transfer_id
    returning * into v_line;
    if not found then raise exception 'Item does not belong to this transfer'; end if;

    select reconciliation_tolerance into v_tolerance from equipment_types where id = v_line.equipment_type_id;

    v_unexplained := coalesce(v_line.quantity_dispatched, 0) - coalesce(v_line.quantity_received, 0) - v_damaged - v_missing;
    if abs(v_unexplained) > coalesce(v_tolerance, 0) then
      v_has_discrepancy := true;
    end if;

    -- Damaged units arrived broken: credit them, then take them out of available into the damaged bucket.
    if v_damaged > 0 then
      insert into damage_reports (organization_id, station_id, equipment_type_id, quantity, reported_by, reason)
      values (v_transfer.organization_id, v_transfer.to_station_id, v_line.equipment_type_id, v_damaged, auth.uid(),
              'Found damaged on receipt, transfer ' || v_transfer.transfer_number)
      returning id into v_report;
      perform apply_inventory_transaction(v_line.equipment_type_id, v_transfer.to_station_id, 'TRANSFER_IN', v_damaged,
        'equipment_transfer', p_transfer_id, 'Damaged units on transfer ' || v_transfer.transfer_number);
      perform apply_inventory_transaction(v_line.equipment_type_id, v_transfer.to_station_id, 'DAMAGE', v_damaged,
        'damage_report', v_report, 'Found damaged on receipt, transfer ' || v_transfer.transfer_number);
      update inventory_balances set damaged_quantity = damaged_quantity + v_damaged, updated_at = now()
      where equipment_type_id = v_line.equipment_type_id and station_id = v_transfer.to_station_id;
    end if;

    -- Missing units never arrived: record them against the destination until investigated.
    if v_missing > 0 then
      insert into loss_reports (organization_id, station_id, equipment_type_id, quantity, reported_by, circumstances)
      values (v_transfer.organization_id, v_transfer.to_station_id, v_line.equipment_type_id, v_missing, auth.uid(),
              'Not received on transfer ' || v_transfer.transfer_number)
      returning id into v_report;
      perform apply_inventory_transaction(v_line.equipment_type_id, v_transfer.to_station_id, 'TRANSFER_IN', v_missing,
        'equipment_transfer', p_transfer_id, 'Missing units on transfer ' || v_transfer.transfer_number);
      perform apply_inventory_transaction(v_line.equipment_type_id, v_transfer.to_station_id, 'LOSS', v_missing,
        'loss_report', v_report, 'Not received on transfer ' || v_transfer.transfer_number);
      update inventory_balances set missing_quantity = missing_quantity + v_missing, updated_at = now()
      where equipment_type_id = v_line.equipment_type_id and station_id = v_transfer.to_station_id;
    end if;

    update inventory_balances
    set in_transit_quantity = greatest(0, in_transit_quantity - coalesce(v_line.quantity_dispatched, 0)),
        updated_at = now()
    where equipment_type_id = v_line.equipment_type_id and station_id = v_transfer.from_station_id;
  end loop;

  v_final_status := case when v_has_discrepancy then 'DISCREPANCY' else 'RECONCILIATION' end;

  update equipment_transfers
  set status = v_final_status, notes = coalesce(p_notes, notes)
  where id = p_transfer_id;

  perform write_audit_log(v_transfer.organization_id, 'transfer.reconcile', 'equipment_transfer', p_transfer_id,
    v_transfer.to_station_id, jsonb_build_object('status', 'RECEIVED'),
    jsonb_build_object('status', v_final_status), p_notes);

  return v_final_status;
end;
$$;

-- CREATE OR REPLACE keeps existing grants; re-assert them for clarity.
revoke execute on function dispatch_transfer(uuid, jsonb), reconcile_transfer(uuid, jsonb, text) from public, anon;
grant execute on function dispatch_transfer(uuid, jsonb), reconcile_transfer(uuid, jsonb, text) to authenticated;
