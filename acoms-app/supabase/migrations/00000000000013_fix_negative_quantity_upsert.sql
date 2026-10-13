-- ============================================================================
-- ACOMS Migration 013: Fix Negative-Quantity Upsert Bug in apply_inventory_transaction
--
-- Bug: the original upsert used
--   INSERT ... VALUES (..., v_signed_quantity, ...) ON CONFLICT DO UPDATE ...
-- Postgres validates CHECK constraints against the literal INSERT values
-- BEFORE falling back to the ON CONFLICT UPDATE branch. So for any
-- decreasing transaction (TRANSFER_OUT, DAMAGE, LOSS, DISPOSAL), the
-- tentative insert row had a negative available_quantity and was rejected
-- by chk_balances_non_negative — even when the correct outcome (existing
-- balance + negative delta) would have been perfectly valid.
--
-- Fix: guarantee the balance row exists first (a harmless zero-value
-- upsert that can never violate the constraint), then always apply the
-- change via a genuine UPDATE. The constraint now only ever validates the
-- real computed result, never a raw literal negative value.
-- ============================================================================

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

  -- Step 1: guarantee the balance row exists, with harmless zero values.
  -- This insert can never violate chk_balances_non_negative (all zeros),
  -- so it's always safe regardless of transaction direction.
  insert into inventory_balances (organization_id, equipment_type_id, station_id)
  values (v_org, p_equipment_type_id, p_station_id)
  on conflict (equipment_type_id, station_id) do nothing;

  -- Step 2: apply the actual change via a real UPDATE. The constraint now
  -- validates the true computed result (existing + delta), not a raw
  -- literal — so a decreasing transaction correctly succeeds when there's
  -- enough stock, and correctly fails only when it would truly go negative.
  update inventory_balances
  set available_quantity = available_quantity + v_signed_quantity,
      last_transaction_at = now(),
      updated_at = now()
  where equipment_type_id = p_equipment_type_id and station_id = p_station_id;

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
