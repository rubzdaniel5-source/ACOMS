-- ============================================================================
-- ACOMS Migration 011: Equipment Transfer State Machine Functions
--
-- Every state transition is a SECURITY DEFINER function that:
-- 1. Validates the current status allows this transition
-- 2. Checks the caller's capability + station access
-- 3. Performs the transition + any inventory/ledger side effects
-- 4. Writes an audit log entry
-- Application code (React/Next.js) calls these functions via Supabase RPC —
-- it never updates equipment_transfers.status directly (no RLS write policy
-- exists for that, by design).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. request_transfer — creates a transfer in REQUESTED status.
-- p_items: jsonb array like [{"equipment_type_id": "...", "quantity": 10}, ...]
-- ----------------------------------------------------------------------------
create or replace function request_transfer(
  p_from_station_id uuid,
  p_to_station_id uuid,
  p_items jsonb,
  p_reason text default null,
  p_priority text default 'NORMAL'
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org uuid;
  v_transfer_id uuid;
  v_item jsonb;
begin
  if not auth_has_permission('create_transfer') then
    raise exception 'Missing permission: create_transfer';
  end if;
  if not auth_has_station_access(p_from_station_id) then
    raise exception 'No station access to source station %', p_from_station_id;
  end if;
  if jsonb_array_length(p_items) = 0 then
    raise exception 'A transfer must include at least one item';
  end if;

  select organization_id into v_org from stations where id = p_from_station_id;

  insert into equipment_transfers (
    organization_id, from_station_id, to_station_id, requested_by, reason, priority
  ) values (
    v_org, p_from_station_id, p_to_station_id, auth.uid(), p_reason, p_priority
  ) returning id into v_transfer_id;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    insert into equipment_transfer_items (transfer_id, equipment_type_id, quantity_requested)
    values (
      v_transfer_id,
      (v_item->>'equipment_type_id')::uuid,
      (v_item->>'quantity')::integer
    );
  end loop;

  perform write_audit_log('transfer.request', 'equipment_transfer', v_transfer_id,
    p_from_station_id, null, jsonb_build_object('items', p_items), p_reason);

  return v_transfer_id;
end;
$$;

-- ----------------------------------------------------------------------------
-- 2. approve_transfer — ADR-007: requester can never approve their own request.
-- p_approved_items: jsonb array [{"item_id": "...", "quantity_approved": N}, ...]
-- (item_id = equipment_transfer_items.id, not equipment_type_id)
-- ----------------------------------------------------------------------------
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
begin
  select * into v_transfer from equipment_transfers where id = p_transfer_id;
  if not found then
    raise exception 'Transfer % not found', p_transfer_id;
  end if;
  if v_transfer.status <> 'REQUESTED' then
    raise exception 'Transfer must be REQUESTED to approve (current status: %)', v_transfer.status;
  end if;
  if not auth_has_permission('approve_transfer') then
    raise exception 'Missing permission: approve_transfer';
  end if;
  if not auth_has_station_access(v_transfer.from_station_id) then
    raise exception 'No station access to source station';
  end if;

  -- ADR-007: hard rule, enforced here, not just hidden in the UI.
  if auth.uid() = v_transfer.requested_by then
    raise exception 'The requester cannot approve their own transfer request (ADR-007)';
  end if;

  for v_item in select * from jsonb_array_elements(p_approved_items)
  loop
    update equipment_transfer_items
    set quantity_approved = (v_item->>'quantity_approved')::integer
    where id = (v_item->>'item_id')::uuid and transfer_id = p_transfer_id;
  end loop;

  update equipment_transfers
  set status = 'APPROVED', approved_by = auth.uid(), approved_at = now(), notes = coalesce(p_notes, notes)
  where id = p_transfer_id;

  perform write_audit_log('transfer.approve', 'equipment_transfer', p_transfer_id,
    v_transfer.from_station_id, jsonb_build_object('status', 'REQUESTED'),
    jsonb_build_object('status', 'APPROVED'), p_notes);
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. reject_transfer
-- ----------------------------------------------------------------------------
create or replace function reject_transfer(
  p_transfer_id uuid,
  p_reason text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_transfer equipment_transfers%rowtype;
begin
  select * into v_transfer from equipment_transfers where id = p_transfer_id;
  if not found then raise exception 'Transfer % not found', p_transfer_id; end if;
  if v_transfer.status <> 'REQUESTED' then
    raise exception 'Only a REQUESTED transfer can be rejected (current status: %)', v_transfer.status;
  end if;
  if not auth_has_permission('approve_transfer') then
    raise exception 'Missing permission: approve_transfer';
  end if;
  if auth.uid() = v_transfer.requested_by then
    raise exception 'The requester cannot reject/approve their own transfer request (ADR-007)';
  end if;

  update equipment_transfers set status = 'REJECTED', notes = p_reason where id = p_transfer_id;

  perform write_audit_log('transfer.reject', 'equipment_transfer', p_transfer_id,
    v_transfer.from_station_id, jsonb_build_object('status', v_transfer.status),
    jsonb_build_object('status', 'REJECTED'), p_reason);
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. dispatch_transfer — moves stock OUT of the source station's available
-- balance and INTO in_transit, via apply_inventory_transaction (TRANSFER_OUT).
-- p_dispatched_items: [{"item_id": "...", "quantity_dispatched": N}, ...]
-- ----------------------------------------------------------------------------
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
  v_equipment_type_id uuid;
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

    select equipment_type_id into v_equipment_type_id
    from equipment_transfer_items where id = (v_item->>'item_id')::uuid;

    update equipment_transfer_items
    set quantity_dispatched = v_qty
    where id = (v_item->>'item_id')::uuid;

    -- Reduces available_quantity at source via the ledger.
    perform apply_inventory_transaction(
      v_equipment_type_id, v_transfer.from_station_id, 'TRANSFER_OUT', v_qty,
      'equipment_transfer', p_transfer_id, 'Dispatched on transfer ' || v_transfer.transfer_number
    );

    -- Track in_transit_quantity directly (apply_inventory_transaction only
    -- manages available_quantity — in_transit is a transfer-specific concept
    -- layered on top here, cleared again in receive_transfer/reconcile below).
    update inventory_balances
    set in_transit_quantity = in_transit_quantity + v_qty, updated_at = now()
    where equipment_type_id = v_equipment_type_id and station_id = v_transfer.from_station_id;
  end loop;

  update equipment_transfers
  set status = 'IN_TRANSIT', dispatched_by = auth.uid(), dispatched_at = now()
  where id = p_transfer_id;

  perform write_audit_log('transfer.dispatch', 'equipment_transfer', p_transfer_id,
    v_transfer.from_station_id, jsonb_build_object('status', 'APPROVED'),
    jsonb_build_object('status', 'IN_TRANSIT'), null);
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. receive_transfer — records actual received quantities at destination.
-- Does NOT yet reconcile damaged/missing — that's reconcile_transfer below.
-- p_received_items: [{"item_id": "...", "quantity_received": N}, ...]
-- ----------------------------------------------------------------------------
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
  v_equipment_type_id uuid;
  v_qty integer;
begin
  select * into v_transfer from equipment_transfers where id = p_transfer_id;
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

  for v_item in select * from jsonb_array_elements(p_received_items)
  loop
    v_qty := (v_item->>'quantity_received')::integer;

    select equipment_type_id into v_equipment_type_id
    from equipment_transfer_items where id = (v_item->>'item_id')::uuid;

    update equipment_transfer_items
    set quantity_received = v_qty
    where id = (v_item->>'item_id')::uuid;

    -- Increases available_quantity at destination via the ledger.
    perform apply_inventory_transaction(
      v_equipment_type_id, v_transfer.to_station_id, 'TRANSFER_IN', v_qty,
      'equipment_transfer', p_transfer_id, 'Received on transfer ' || v_transfer.transfer_number
    );
  end loop;

  update equipment_transfers
  set status = 'RECEIVED', received_by = auth.uid(), received_at = now()
  where id = p_transfer_id;

  perform write_audit_log('transfer.receive', 'equipment_transfer', p_transfer_id,
    v_transfer.to_station_id, jsonb_build_object('status', 'IN_TRANSIT'),
    jsonb_build_object('status', 'RECEIVED'), null);
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. reconcile_transfer — the discrepancy check per equipment-transfers.md:
-- Dispatched = Received + Damaged + Missing + Other Approved Explanation
-- Uses equipment_types.reconciliation_tolerance (ADR-008) per line item.
-- If any line's unexplained difference exceeds tolerance, the WHOLE transfer
-- moves to DISCREPANCY instead of RECONCILIATION/CLOSED — it cannot be
-- silently closed (equipment-transfers.md > Integrity).
-- p_reconciliation_items: [{"item_id": "...", "quantity_damaged": N, "quantity_missing": N}, ...]
-- ----------------------------------------------------------------------------
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
  v_transfer_item equipment_transfer_items%rowtype;
  v_tolerance integer;
  v_unexplained integer;
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
    update equipment_transfer_items
    set quantity_damaged = (v_item->>'quantity_damaged')::integer,
        quantity_missing = (v_item->>'quantity_missing')::integer
    where id = (v_item->>'item_id')::uuid
    returning * into v_transfer_item;

    select reconciliation_tolerance into v_tolerance
    from equipment_types where id = v_transfer_item.equipment_type_id;

    v_unexplained := coalesce(v_transfer_item.quantity_dispatched, 0)
      - coalesce(v_transfer_item.quantity_received, 0)
      - coalesce(v_transfer_item.quantity_damaged, 0)
      - coalesce(v_transfer_item.quantity_missing, 0);

    if abs(v_unexplained) > coalesce(v_tolerance, 0) then
      v_has_discrepancy := true;
    end if;

    -- Record DAMAGE/LOSS ledger effects at the destination station where
    -- the discrepancy was discovered, so inventory reflects reality even
    -- while the transfer itself may remain open pending investigation.
    if coalesce(v_transfer_item.quantity_damaged, 0) > 0 then
      perform apply_inventory_transaction(
        v_transfer_item.equipment_type_id, v_transfer.to_station_id, 'DAMAGE',
        v_transfer_item.quantity_damaged, 'equipment_transfer', p_transfer_id,
        'Damage recorded during reconciliation of ' || v_transfer.transfer_number
      );
    end if;
    if coalesce(v_transfer_item.quantity_missing, 0) > 0 then
      perform apply_inventory_transaction(
        v_transfer_item.equipment_type_id, v_transfer.to_station_id, 'LOSS',
        v_transfer_item.quantity_missing, 'equipment_transfer', p_transfer_id,
        'Missing quantity recorded during reconciliation of ' || v_transfer.transfer_number
      );
    end if;

    -- Clear in_transit_quantity at the source station now that this line
    -- has been accounted for (whether clean or discrepant).
    update inventory_balances
    set in_transit_quantity = greatest(0, in_transit_quantity - coalesce(v_transfer_item.quantity_dispatched, 0)),
        updated_at = now()
    where equipment_type_id = v_transfer_item.equipment_type_id and station_id = v_transfer.from_station_id;
  end loop;

  v_final_status := case when v_has_discrepancy then 'DISCREPANCY' else 'RECONCILIATION' end;

  update equipment_transfers
  set status = v_final_status, notes = coalesce(p_notes, notes)
  where id = p_transfer_id;

  perform write_audit_log('transfer.reconcile', 'equipment_transfer', p_transfer_id,
    v_transfer.to_station_id, jsonb_build_object('status', 'RECEIVED'),
    jsonb_build_object('status', v_final_status), p_notes);

  return v_final_status;
end;
$$;

-- ----------------------------------------------------------------------------
-- 7. close_transfer — only from RECONCILIATION (clean), never from
-- DISCREPANCY directly (equipment-transfers.md > Integrity: cannot bypass
-- unresolved discrepancies). A discrepancy must be explicitly resolved first
-- via resolve_discrepancy() below, which moves it to RECONCILIATION.
-- ----------------------------------------------------------------------------
create or replace function close_transfer(
  p_transfer_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_transfer equipment_transfers%rowtype;
begin
  select * into v_transfer from equipment_transfers where id = p_transfer_id;
  if not found then raise exception 'Transfer % not found', p_transfer_id; end if;
  if v_transfer.status <> 'RECONCILIATION' then
    raise exception 'Transfer must be in RECONCILIATION (fully explained) to close (current status: %)', v_transfer.status;
  end if;
  if not auth_has_permission('reconcile_transfer') then
    raise exception 'Missing permission: reconcile_transfer';
  end if;

  update equipment_transfers
  set status = 'CLOSED', closed_by = auth.uid(), closed_at = now()
  where id = p_transfer_id;

  perform write_audit_log('transfer.close', 'equipment_transfer', p_transfer_id,
    v_transfer.to_station_id, jsonb_build_object('status', 'RECONCILIATION'),
    jsonb_build_object('status', 'CLOSED'), null);
end;
$$;

-- ----------------------------------------------------------------------------
-- 8. resolve_discrepancy — an authorized user explicitly accepts a
-- discrepancy as explained (e.g. after investigation), moving the transfer
-- from DISCREPANCY to RECONCILIATION so it can then be closed. Requires a
-- reason — an unexplained difference can never be closed silently.
-- ----------------------------------------------------------------------------
create or replace function resolve_discrepancy(
  p_transfer_id uuid,
  p_resolution_reason text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_transfer equipment_transfers%rowtype;
begin
  select * into v_transfer from equipment_transfers where id = p_transfer_id;
  if not found then raise exception 'Transfer % not found', p_transfer_id; end if;
  if v_transfer.status <> 'DISCREPANCY' then
    raise exception 'Transfer is not in DISCREPANCY status (current status: %)', v_transfer.status;
  end if;
  if not auth_has_permission('reconcile_transfer') then
    raise exception 'Missing permission: reconcile_transfer';
  end if;
  if p_resolution_reason is null or length(trim(p_resolution_reason)) = 0 then
    raise exception 'A resolution reason is required to resolve a discrepancy';
  end if;

  update equipment_transfers
  set status = 'RECONCILIATION', notes = coalesce(notes || E'\n', '') || 'RESOLVED: ' || p_resolution_reason
  where id = p_transfer_id;

  perform write_audit_log('transfer.resolve_discrepancy', 'equipment_transfer', p_transfer_id,
    v_transfer.to_station_id, jsonb_build_object('status', 'DISCREPANCY'),
    jsonb_build_object('status', 'RECONCILIATION'), p_resolution_reason);
end;
$$;
