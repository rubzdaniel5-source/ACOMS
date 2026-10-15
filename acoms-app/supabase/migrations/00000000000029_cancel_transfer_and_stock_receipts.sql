-- ============================================================================
-- ACOMS Migration 029: cancel a transfer; book newly received stock
--
-- 1. cancel_transfer: a requester can withdraw their own request while it is
--    still REQUESTED. Someone with approve_transfer at the source station can
--    cancel a REQUESTED or APPROVED transfer. Nothing has moved yet in either
--    case, so no stock changes. A reason is always required. Once dispatched,
--    stock is on its way and the transfer must be received and reconciled.
-- 2. New stock received (purchase or delivery) is a new reason on the existing
--    two-person stock adjustment. On approval it posts to the ledger as
--    RECEIPT instead of ADJUSTMENT. Increase only.
-- ============================================================================

alter table equipment_transfers
  add column if not exists cancelled_by uuid references user_profiles(id) on delete restrict,
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancel_reason text;

create or replace function cancel_transfer(p_transfer_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_org uuid := auth_organization_id();
  v_t equipment_transfers%rowtype;
  v_is_requester boolean;
  v_is_approver boolean;
begin
  if auth.uid() is null or v_org is null then raise exception 'Not authenticated'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'A reason is required to cancel a transfer'; end if;
  select * into v_t from equipment_transfers where id = p_transfer_id and organization_id = v_org for update;
  if not found then raise exception 'Transfer not found'; end if;
  if v_t.status not in ('REQUESTED', 'APPROVED') then
    raise exception 'Only a requested or approved transfer can be cancelled (current status: %). After dispatch, receive and reconcile it instead.', v_t.status;
  end if;

  v_is_requester := v_t.requested_by = auth.uid();
  v_is_approver := auth_has_permission('approve_transfer') and auth_has_station_access(v_t.from_station_id);
  if v_t.status = 'REQUESTED' and not (v_is_requester or v_is_approver) then
    raise exception 'Only the requester, or an approver at the source station, can cancel this request';
  end if;
  if v_t.status = 'APPROVED' and not v_is_approver then
    raise exception 'Only an approver at the source station can cancel an approved transfer';
  end if;

  update equipment_transfers
  set status = 'CANCELLED', cancelled_by = auth.uid(), cancelled_at = now(), cancel_reason = trim(p_reason)
  where id = p_transfer_id;

  perform write_audit_log(v_org, 'transfer.cancel', 'equipment_transfer', p_transfer_id, v_t.from_station_id,
    jsonb_build_object('status', v_t.status), jsonb_build_object('status', 'CANCELLED'), trim(p_reason));
end;
$$;
revoke execute on function cancel_transfer(uuid, text) from public, anon;
grant execute on function cancel_transfer(uuid, text) to authenticated;

-- ---- New stock received ------------------------------------------------------
alter table stock_adjustments drop constraint if exists stock_adjustments_reason_code_check;
alter table stock_adjustments add constraint stock_adjustments_reason_code_check
  check (reason_code in ('COUNT_CORRECTION', 'DATA_ENTRY_ERROR', 'UNRECORDED_RECEIPT', 'WRITE_OFF', 'NEW_STOCK_RECEIVED', 'OTHER'));

do $$
declare v_def text;
begin
  -- Request: new stock can only increase stock.
  v_def := pg_get_functiondef('request_stock_adjustment(uuid, uuid, text, integer, text, text)'::regprocedure);
  v_def := replace(v_def,
    'if p_quantity is null or p_quantity <= 0 then raise exception ''Quantity must be greater than zero''; end if;',
    'if p_quantity is null or p_quantity <= 0 then raise exception ''Quantity must be greater than zero''; end if;
  if p_reason_code = ''NEW_STOCK_RECEIVED'' and p_direction <> ''INCREASE'' then raise exception ''New stock received can only increase stock''; end if;');
  if v_def not like '%NEW_STOCK_RECEIVED%' then raise exception 'Failed to patch request_stock_adjustment'; end if;
  execute v_def;

  -- Approve: post as RECEIPT.
  v_def := pg_get_functiondef('approve_stock_adjustment(uuid, text)'::regprocedure);
  v_def := replace(v_def,
    'case v_a.direction when ''INCREASE'' then ''ADJUSTMENT'' else ''ADJUSTMENT_DECREASE'' end,',
    'case when v_a.reason_code = ''NEW_STOCK_RECEIVED'' then ''RECEIPT'' when v_a.direction = ''INCREASE'' then ''ADJUSTMENT'' else ''ADJUSTMENT_DECREASE'' end,');
  if v_def not like '%NEW_STOCK_RECEIVED%' then raise exception 'Failed to patch approve_stock_adjustment'; end if;
  execute v_def;
end $$;
