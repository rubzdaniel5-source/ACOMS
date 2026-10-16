-- ============================================================================
-- ACOMS Migration 030: transfer safety fixes (functions only, no schema change)
--
-- 1. Every state-changing transfer function now locks the transfer row first
--    (SELECT ... FOR UPDATE), so two simultaneous clicks are serialised: the
--    second one waits, then sees the new status and is refused.
-- 2. approve_transfer: a line must belong to the transfer, may not be negative,
--    may not exceed what was requested, and may be listed only once.
-- 3. dispatch_transfer / reconcile_transfer: the same line may be listed only
--    once (a repeated line used to post stock twice).
-- 4. receive_transfer: every line must be counted exactly once, lines must
--    belong to the transfer, no negatives, and the count may not exceed what
--    was dispatched. Over-receipt is refused for now; a controlled
--    "excess held for investigation" state follows in the next step.
-- All of it runs in one transaction per call, so a failure on any line leaves
-- no partial stock or status change.
-- ============================================================================

create or replace function _assert_unique_items(p_items jsonb)
returns void language plpgsql immutable set search_path = public as $$
begin
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'A list of items is required';
  end if;
  if (select count(*) from jsonb_array_elements(p_items)) <>
     (select count(distinct e->>'item_id') from jsonb_array_elements(p_items) e) then
    raise exception 'Each item can only be listed once';
  end if;
end $$;
revoke execute on function _assert_unique_items(jsonb) from public, anon, authenticated;

-- ---- Row locks on the existing functions ------------------------------------
do $$
declare
  v_name text; v_def text;
  v_old constant text := 'select * into v_transfer from equipment_transfers where id = p_transfer_id;';
  v_new constant text := 'select * into v_transfer from equipment_transfers where id = p_transfer_id for update;';
begin
  foreach v_name in array array['reject_transfer(uuid, text)', 'dispatch_transfer(uuid, jsonb)', 'reconcile_transfer(uuid, jsonb, text)',
                                'close_transfer(uuid)', 'resolve_discrepancy(uuid, text)'] loop
    v_def := pg_get_functiondef(v_name::regprocedure);
    if position(v_old in v_def) = 0 then raise exception 'Lock patch: pattern not found in %', v_name; end if;
    v_def := replace(v_def, v_old, v_new);
    if v_name like 'dispatch_transfer%' then
      v_def := replace(v_def, 'for v_item in select * from jsonb_array_elements(p_dispatched_items)',
        E'perform _assert_unique_items(p_dispatched_items);\n  for v_item in select * from jsonb_array_elements(p_dispatched_items)');
      if v_def not like '%_assert_unique_items%' then raise exception 'Duplicate-line patch failed for dispatch'; end if;
    elsif v_name like 'reconcile_transfer%' then
      v_def := replace(v_def, 'for v_item in select * from jsonb_array_elements(p_reconciliation_items)',
        E'perform _assert_unique_items(p_reconciliation_items);\n  for v_item in select * from jsonb_array_elements(p_reconciliation_items)');
      if v_def not like '%_assert_unique_items%' then raise exception 'Duplicate-line patch failed for reconcile'; end if;
    end if;
    execute v_def;
  end loop;
end $$;

-- ---- approve_transfer ---------------------------------------------------------
create or replace function approve_transfer(
  p_transfer_id uuid,
  p_approved_items jsonb,
  p_notes text default null
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
  select * into v_transfer from equipment_transfers where id = p_transfer_id for update;
  if not found then raise exception 'Transfer % not found', p_transfer_id; end if;
  if v_transfer.status <> 'REQUESTED' then
    raise exception 'Transfer must be REQUESTED to approve (current status: %)', v_transfer.status;
  end if;
  if not auth_has_permission('approve_transfer') then
    raise exception 'Missing permission: approve_transfer';
  end if;
  if not auth_has_station_access(v_transfer.from_station_id) then
    raise exception 'No station access to source station';
  end if;
  if auth.uid() = v_transfer.requested_by then
    raise exception 'The requester cannot approve their own transfer request (ADR-007)';
  end if;

  perform _assert_unique_items(p_approved_items);
  for v_item in select * from jsonb_array_elements(p_approved_items)
  loop
    v_qty := (v_item->>'quantity_approved')::integer;
    select * into v_line from equipment_transfer_items
    where id = (v_item->>'item_id')::uuid and transfer_id = p_transfer_id;
    if not found then raise exception 'Item does not belong to this transfer'; end if;
    if v_qty is null or v_qty < 0 then raise exception 'Approved quantity cannot be negative'; end if;
    if v_qty > v_line.quantity_requested then
      raise exception 'Cannot approve % of an item: more than requested (%)', v_qty, v_line.quantity_requested;
    end if;
    update equipment_transfer_items set quantity_approved = v_qty where id = v_line.id;
  end loop;

  update equipment_transfers
  set status = 'APPROVED', approved_by = auth.uid(), approved_at = now(), notes = coalesce(p_notes, notes)
  where id = p_transfer_id;

  perform write_audit_log(v_transfer.organization_id, 'transfer.approve', 'equipment_transfer', p_transfer_id,
    v_transfer.from_station_id, jsonb_build_object('status', 'REQUESTED'),
    jsonb_build_object('status', 'APPROVED'), p_notes);
end;
$$;

-- ---- receive_transfer ---------------------------------------------------------
create or replace function receive_transfer(
  p_transfer_id uuid,
  p_received_items jsonb
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
  v_dispatched integer;
begin
  select * into v_transfer from equipment_transfers where id = p_transfer_id for update;
  if not found then raise exception 'Transfer % not found', p_transfer_id; end if;
  if v_transfer.status <> 'IN_TRANSIT' then
    raise exception 'Transfer must be IN_TRANSIT to receive (current status: %)', v_transfer.status;
  end if;
  if not auth_has_permission('receive_transfer') then
    raise exception 'Missing permission: receive_transfer';
  end if;
  if not auth_has_station_access(v_transfer.to_station_id) then
    raise exception 'No station access to destination station';
  end if;

  perform _assert_unique_items(p_received_items);
  if jsonb_array_length(p_received_items) <> (select count(*) from equipment_transfer_items where transfer_id = p_transfer_id) then
    raise exception 'Every item on the transfer must be counted';
  end if;

  for v_item in select * from jsonb_array_elements(p_received_items)
  loop
    v_qty := (v_item->>'quantity_received')::integer;
    select * into v_line from equipment_transfer_items
    where id = (v_item->>'item_id')::uuid and transfer_id = p_transfer_id;
    if not found then raise exception 'Item does not belong to this transfer'; end if;
    if v_qty is null or v_qty < 0 then raise exception 'Received quantity cannot be negative'; end if;
    v_dispatched := coalesce(v_line.quantity_dispatched, 0);
    if v_qty > v_dispatched then
      raise exception 'Received quantity % exceeds the dispatched quantity % and cannot be accepted as stock', v_qty, v_dispatched;
    end if;

    update equipment_transfer_items set quantity_received = v_qty where id = v_line.id;

    if v_qty > 0 then
      perform apply_inventory_transaction(
        v_line.equipment_type_id, v_transfer.to_station_id, 'TRANSFER_IN', v_qty,
        'equipment_transfer', p_transfer_id, 'Received on transfer ' || v_transfer.transfer_number
      );
    end if;
  end loop;

  update equipment_transfers
  set status = 'RECEIVED', received_by = auth.uid(), received_at = now()
  where id = p_transfer_id;

  perform write_audit_log(v_transfer.organization_id, 'transfer.receive', 'equipment_transfer', p_transfer_id,
    v_transfer.to_station_id, jsonb_build_object('status', 'IN_TRANSIT'),
    jsonb_build_object('status', 'RECEIVED'), null);
end;
$$;

revoke execute on function approve_transfer(uuid, jsonb, text), receive_transfer(uuid, jsonb) from public, anon;
grant execute on function approve_transfer(uuid, jsonb, text), receive_transfer(uuid, jsonb) to authenticated;
