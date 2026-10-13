-- ============================================================================
-- ACOMS Migration 012: Fix Audit Log Organization Resolution
--
-- Bug: write_audit_log() resolved organization_id by looking up
-- user_profiles WHERE id = auth.uid(). This breaks for any caller without
-- an active authenticated session (e.g. SQL Editor testing, future bulk
-- data loads, service-role scripts) — auth.uid() is null there, so
-- organization_id ends up null, which violates the not-null constraint.
--
-- Fix: callers now pass organization_id explicitly, since they already
-- know it (it's resolved from the entity they're acting on). This also
-- makes write_audit_log usable outside a request context, which the
-- system will need eventually (e.g. scheduled jobs, data imports).
-- ============================================================================

drop function if exists write_audit_log(text, text, uuid, uuid, jsonb, jsonb, text);

create or replace function write_audit_log(
  p_organization_id uuid,
  p_action text,
  p_entity_type text,
  p_entity_id uuid,
  p_station_id uuid,
  p_before jsonb,
  p_after jsonb,
  p_reason text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_actor_label text;
begin
  -- Best-effort actor label; stays null if there's no authenticated user
  -- (e.g. a script running outside a request context), which is fine —
  -- actor_id/actor_label are nullable by design for exactly this case.
  select full_name into v_actor_label from user_profiles where id = auth.uid();

  insert into audit_logs (
    organization_id, actor_id, actor_label, action, entity_type,
    entity_id, station_id, before_state, after_state, reason
  ) values (
    p_organization_id, auth.uid(), v_actor_label, p_action, p_entity_type,
    p_entity_id, p_station_id, p_before, p_after, p_reason
  ) returning id into v_id;

  return v_id;
end;
$$;

comment on function write_audit_log is
  'organization_id is now passed explicitly by the caller rather than resolved via auth.uid(), so this works both inside authenticated app sessions and outside them (SQL Editor, scripts, imports).';

-- ----------------------------------------------------------------------------
-- Update apply_inventory_transaction to pass organization_id explicitly
-- (it already resolves v_org from equipment_types, just wasn't passing it)
-- ----------------------------------------------------------------------------
create or replace function apply_inventory_transaction(
  p_equipment_type_id uuid,
  p_station_id uuid,
  p_transaction_type text,
  p_quantity integer,
  p_reference_type text default null,
  p_reference_id uuid default null,
  p_reason text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org uuid;
  v_signed_quantity integer;
  v_tx_id uuid;
begin
  if p_quantity < 0 then
    raise exception 'quantity must be a positive magnitude; sign is derived from transaction_type';
  end if;

  select organization_id into v_org from equipment_types where id = p_equipment_type_id;

  v_signed_quantity := case p_transaction_type
    when 'OPENING_BALANCE' then p_quantity
    when 'RECEIPT' then p_quantity
    when 'TRANSFER_IN' then p_quantity
    when 'RETURN' then p_quantity
    when 'RECOVERY' then p_quantity
    when 'ADJUSTMENT' then p_quantity
    when 'TRANSFER_OUT' then -p_quantity
    when 'DAMAGE' then -p_quantity
    when 'LOSS' then -p_quantity
    when 'DISPOSAL' then -p_quantity
    else null
  end;

  if v_signed_quantity is null then
    raise exception 'Unrecognized transaction_type: %', p_transaction_type;
  end if;

  insert into inventory_transactions (
    organization_id, equipment_type_id, station_id, transaction_type,
    quantity, reference_type, reference_id, performed_by, reason
  ) values (
    v_org, p_equipment_type_id, p_station_id, p_transaction_type,
    v_signed_quantity, p_reference_type, p_reference_id, auth.uid(), p_reason
  ) returning id into v_tx_id;

  insert into inventory_balances (organization_id, equipment_type_id, station_id, available_quantity, last_transaction_at)
  values (v_org, p_equipment_type_id, p_station_id, v_signed_quantity, now())
  on conflict (equipment_type_id, station_id)
  do update set
    available_quantity = inventory_balances.available_quantity + v_signed_quantity,
    last_transaction_at = now(),
    updated_at = now();

  perform write_audit_log(
    v_org,
    'inventory.' || lower(p_transaction_type),
    'inventory_transaction',
    v_tx_id,
    p_station_id,
    null,
    jsonb_build_object('transaction_type', p_transaction_type, 'quantity', v_signed_quantity),
    p_reason
  );

  return v_tx_id;
end;
$$;

-- ----------------------------------------------------------------------------
-- Update the 8 transfer functions to pass organization_id explicitly
-- (each already has v_transfer.organization_id available)
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

  perform write_audit_log(v_org, 'transfer.request', 'equipment_transfer', v_transfer_id,
    p_from_station_id, null, jsonb_build_object('items', p_items), p_reason);

  return v_transfer_id;
end;
$$;

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

  for v_item in select * from jsonb_array_elements(p_approved_items)
  loop
    update equipment_transfer_items
    set quantity_approved = (v_item->>'quantity_approved')::integer
    where id = (v_item->>'item_id')::uuid and transfer_id = p_transfer_id;
  end loop;

  update equipment_transfers
  set status = 'APPROVED', approved_by = auth.uid(), approved_at = now(), notes = coalesce(p_notes, notes)
  where id = p_transfer_id;

  perform write_audit_log(v_transfer.organization_id, 'transfer.approve', 'equipment_transfer', p_transfer_id,
    v_transfer.from_station_id, jsonb_build_object('status', 'REQUESTED'),
    jsonb_build_object('status', 'APPROVED'), p_notes);
end;
$$;

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

  perform write_audit_log(v_transfer.organization_id, 'transfer.reject', 'equipment_transfer', p_transfer_id,
    v_transfer.from_station_id, jsonb_build_object('status', v_transfer.status),
    jsonb_build_object('status', 'REJECTED'), p_reason);
end;
$$;

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

    perform apply_inventory_transaction(
      v_equipment_type_id, v_transfer.from_station_id, 'TRANSFER_OUT', v_qty,
      'equipment_transfer', p_transfer_id, 'Dispatched on transfer ' || v_transfer.transfer_number
    );

    update inventory_balances
    set in_transit_quantity = in_transit_quantity + v_qty, updated_at = now()
    where equipment_type_id = v_equipment_type_id and station_id = v_transfer.from_station_id;
  end loop;

  update equipment_transfers
  set status = 'IN_TRANSIT', dispatched_by = auth.uid(), dispatched_at = now()
  where id = p_transfer_id;

  perform write_audit_log(v_transfer.organization_id, 'transfer.dispatch', 'equipment_transfer', p_transfer_id,
    v_transfer.from_station_id, jsonb_build_object('status', 'APPROVED'),
    jsonb_build_object('status', 'IN_TRANSIT'), null);
end;
$$;

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

    perform apply_inventory_transaction(
      v_equipment_type_id, v_transfer.to_station_id, 'TRANSFER_IN', v_qty,
      'equipment_transfer', p_transfer_id, 'Received on transfer ' || v_transfer.transfer_number
    );
  end loop;

  update equipment_transfers
  set status = 'RECEIVED', received_by = auth.uid(), received_at = now()
  where id = p_transfer_id;

  perform write_audit_log(v_transfer.organization_id, 'transfer.receive', 'equipment_transfer', p_transfer_id,
    v_transfer.to_station_id, jsonb_build_object('status', 'IN_TRANSIT'),
    jsonb_build_object('status', 'RECEIVED'), null);
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

    update inventory_balances
    set in_transit_quantity = greatest(0, in_transit_quantity - coalesce(v_transfer_item.quantity_dispatched, 0)),
        updated_at = now()
    where equipment_type_id = v_transfer_item.equipment_type_id and station_id = v_transfer.from_station_id;
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

  perform write_audit_log(v_transfer.organization_id, 'transfer.close', 'equipment_transfer', p_transfer_id,
    v_transfer.to_station_id, jsonb_build_object('status', 'RECONCILIATION'),
    jsonb_build_object('status', 'CLOSED'), null);
end;
$$;

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

  perform write_audit_log(v_transfer.organization_id, 'transfer.resolve_discrepancy', 'equipment_transfer', p_transfer_id,
    v_transfer.to_station_id, jsonb_build_object('status', 'DISCREPANCY'),
    jsonb_build_object('status', 'RECONCILIATION'), p_resolution_reason);
end;
$$;
