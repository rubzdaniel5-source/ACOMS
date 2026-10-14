-- ============================================================================
-- ACOMS Migration 020: Stock Adjustments with Two-Step Approval (Admin Batch 4)
--
-- One person requests an adjustment; a DIFFERENT person approves it. Only on
-- approval does the ledger change, via apply_inventory_transaction(). A new
-- ledger type ADJUSTMENT_DECREASE is added (ADJUSTMENT remains the increase).
-- ============================================================================

alter table inventory_transactions drop constraint if exists inventory_transactions_transaction_type_check;
alter table inventory_transactions add constraint inventory_transactions_transaction_type_check
  check (transaction_type in (
    'OPENING_BALANCE', 'RECEIPT', 'TRANSFER_OUT', 'TRANSFER_IN', 'RETURN',
    'DAMAGE', 'LOSS', 'ADJUSTMENT', 'ADJUSTMENT_DECREASE', 'DISPOSAL', 'RECOVERY'
  ));

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
    when 'ADJUSTMENT_DECREASE' then -p_quantity
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


-- Re-assert the lock-down (CREATE OR REPLACE keeps grants, this is belt and braces).
revoke execute on function apply_inventory_transaction(uuid, uuid, text, integer, text, uuid, text)
  from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- Permissions (provisional role mapping; editable in Roles & Permissions)
-- ----------------------------------------------------------------------------
insert into permissions (code, description) values
  ('request_adjustment', 'Request a stock adjustment'),
  ('approve_adjustment', 'Approve or reject a stock adjustment requested by someone else')
on conflict (code) do nothing;

insert into role_permissions (role_id, permission_id)
select r.id, p.id from roles r, permissions p
where r.organization_id = (select id from organizations where code = 'UGANDA_AIRLINES')
  and ((p.code = 'request_adjustment' and r.code in ('system_admin','catering_manager','stores_officer','station_manager'))
    or (p.code = 'approve_adjustment' and r.code in ('system_admin','catering_manager','catering_supervisor','station_manager')))
on conflict do nothing;

-- ----------------------------------------------------------------------------
-- Table
-- ----------------------------------------------------------------------------
create sequence adjustment_number_seq start 1;

create table stock_adjustments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete restrict,
  adjustment_number text not null unique default (
    'ADJ-' || extract(year from now()) || '-' || lpad(nextval('adjustment_number_seq')::text, 6, '0')),
  station_id uuid not null references stations(id) on delete restrict,
  equipment_type_id uuid not null references equipment_types(id) on delete restrict,
  direction text not null check (direction in ('INCREASE', 'DECREASE')),
  quantity integer not null check (quantity > 0),
  reason_code text not null check (reason_code in (
    'COUNT_CORRECTION', 'DATA_ENTRY_ERROR', 'UNRECORDED_RECEIPT', 'WRITE_OFF', 'OTHER')),
  notes text not null check (length(trim(notes)) >= 10),
  status text not null default 'REQUESTED' check (status in ('REQUESTED', 'APPROVED', 'REJECTED', 'CANCELLED')),
  requested_by uuid not null references user_profiles(id) on delete restrict,
  requested_at timestamptz not null default now(),
  decided_by uuid references user_profiles(id) on delete restrict,
  decided_at timestamptz,
  decision_note text,
  balance_before integer,
  balance_after integer,
  ledger_transaction_id uuid references inventory_transactions(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index idx_stock_adjustments_status on stock_adjustments (status, requested_at desc);
create index idx_stock_adjustments_station on stock_adjustments (station_id);
create trigger trg_stock_adjustments_updated_at before update on stock_adjustments
  for each row execute function set_updated_at();

alter table stock_adjustments enable row level security;
create policy "stock_adjustments_select" on stock_adjustments for select using (
  organization_id = auth_organization_id()
  and (requested_by = auth.uid()
       or ((auth_has_permission('request_adjustment') or auth_has_permission('approve_adjustment')
            or auth_has_permission('view_inventory')) and auth_has_station_access(station_id)))
);
-- No write policies: every change goes through the functions below.

create or replace view v_stock_adjustments with (security_invoker = true) as
select a.id, a.adjustment_number, a.status, a.direction, a.quantity, a.reason_code, a.notes,
       a.requested_at, a.decided_at, a.decision_note, a.balance_before, a.balance_after,
       a.requested_by, a.decided_by, a.station_id, a.equipment_type_id,
       s.code as station_code, e.source_code, e.name as equipment_name,
       rq.full_name as requested_by_name, dc.full_name as decided_by_name
from stock_adjustments a
join stations s on s.id = a.station_id
join equipment_types e on e.id = a.equipment_type_id
join user_profiles rq on rq.id = a.requested_by
left join user_profiles dc on dc.id = a.decided_by;

-- ----------------------------------------------------------------------------
-- Functions
-- ----------------------------------------------------------------------------
create or replace function request_stock_adjustment(
  p_station_id uuid, p_equipment_type_id uuid, p_direction text, p_quantity integer,
  p_reason_code text, p_notes text
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_org uuid := auth_organization_id(); v_id uuid; v_station stations%rowtype; v_avail integer;
begin
  if auth.uid() is null or v_org is null then raise exception 'Not authenticated'; end if;
  if not auth_has_permission('request_adjustment') then raise exception 'Permission denied: request_adjustment required'; end if;
  select * into v_station from stations where id = p_station_id and organization_id = v_org and is_active;
  if not found then raise exception 'Unknown or inactive station'; end if;
  if not auth_has_station_access(p_station_id) then raise exception 'You have no access to station %', v_station.code; end if;
  if v_station.station_type = 'NO_STOCK_TURNAROUND' then raise exception 'Station % holds no stock', v_station.code; end if;
  if not exists (select 1 from equipment_types where id = p_equipment_type_id and organization_id = v_org and is_active) then
    raise exception 'Unknown or inactive equipment type';
  end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'Quantity must be greater than zero'; end if;
  if coalesce(length(trim(p_notes)), 0) < 10 then raise exception 'Explain the adjustment (at least 10 characters)'; end if;

  if p_direction = 'DECREASE' then
    select coalesce(available_quantity, 0) into v_avail from inventory_balances
      where station_id = p_station_id and equipment_type_id = p_equipment_type_id;
    if coalesce(v_avail, 0) < p_quantity then
      raise exception 'Only % available at this station; cannot decrease by %', coalesce(v_avail, 0), p_quantity;
    end if;
  end if;

  insert into stock_adjustments (organization_id, station_id, equipment_type_id, direction, quantity, reason_code, notes, requested_by)
  values (v_org, p_station_id, p_equipment_type_id, p_direction, p_quantity, p_reason_code, trim(p_notes), auth.uid())
  returning id into v_id;
  perform write_audit_log(v_org, 'adjustment.request', 'stock_adjustment', v_id, p_station_id, null,
    jsonb_build_object('direction', p_direction, 'quantity', p_quantity, 'reason_code', p_reason_code), trim(p_notes));
  return v_id;
end;
$$;

create or replace function cancel_stock_adjustment(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_a stock_adjustments%rowtype;
begin
  select * into v_a from stock_adjustments where id = p_id and organization_id = auth_organization_id() for update;
  if not found then raise exception 'Adjustment not found'; end if;
  if v_a.requested_by <> auth.uid() then raise exception 'Only the requester can cancel'; end if;
  if v_a.status <> 'REQUESTED' then raise exception 'Only pending adjustments can be cancelled'; end if;
  update stock_adjustments set status = 'CANCELLED', decided_at = now() where id = p_id;
  perform write_audit_log(v_a.organization_id, 'adjustment.cancel', 'stock_adjustment', p_id, v_a.station_id, null, null, null);
end;
$$;

create or replace function approve_stock_adjustment(p_id uuid, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid := auth_organization_id(); v_a stock_adjustments%rowtype; v_before integer; v_after integer; v_tx uuid;
begin
  if auth.uid() is null or v_org is null then raise exception 'Not authenticated'; end if;
  if not auth_has_permission('approve_adjustment') then raise exception 'Permission denied: approve_adjustment required'; end if;
  select * into v_a from stock_adjustments where id = p_id and organization_id = v_org for update;
  if not found then raise exception 'Adjustment not found'; end if;
  if v_a.status <> 'REQUESTED' then raise exception 'This adjustment is already %', lower(v_a.status); end if;
  if v_a.requested_by = auth.uid() then raise exception 'You cannot approve an adjustment you requested'; end if;
  if not auth_has_station_access(v_a.station_id) then raise exception 'You have no access to this station'; end if;

  select coalesce(available_quantity, 0) into v_before from inventory_balances
    where station_id = v_a.station_id and equipment_type_id = v_a.equipment_type_id;
  v_before := coalesce(v_before, 0);
  if v_a.direction = 'DECREASE' and v_before < v_a.quantity then
    raise exception 'Stock has changed: only % available now, cannot decrease by %. Reject this request and raise a new one.', v_before, v_a.quantity;
  end if;

  v_tx := apply_inventory_transaction(
    v_a.equipment_type_id, v_a.station_id,
    case v_a.direction when 'INCREASE' then 'ADJUSTMENT' else 'ADJUSTMENT_DECREASE' end,
    v_a.quantity, 'stock_adjustment', v_a.id,
    v_a.adjustment_number || ' (' || v_a.reason_code || '): ' || v_a.notes);
  v_after := v_before + case v_a.direction when 'INCREASE' then v_a.quantity else -v_a.quantity end;

  update stock_adjustments set status = 'APPROVED', decided_by = auth.uid(), decided_at = now(),
    decision_note = nullif(trim(p_note), ''), balance_before = v_before, balance_after = v_after, ledger_transaction_id = v_tx
  where id = p_id;
  perform write_audit_log(v_org, 'adjustment.approve', 'stock_adjustment', p_id, v_a.station_id, null,
    jsonb_build_object('balance_before', v_before, 'balance_after', v_after), p_note);
end;
$$;

create or replace function reject_stock_adjustment(p_id uuid, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid := auth_organization_id(); v_a stock_adjustments%rowtype;
begin
  if auth.uid() is null or v_org is null then raise exception 'Not authenticated'; end if;
  if not auth_has_permission('approve_adjustment') then raise exception 'Permission denied: approve_adjustment required'; end if;
  if coalesce(trim(p_note), '') = '' then raise exception 'A reason is required to reject'; end if;
  select * into v_a from stock_adjustments where id = p_id and organization_id = v_org for update;
  if not found then raise exception 'Adjustment not found'; end if;
  if v_a.status <> 'REQUESTED' then raise exception 'This adjustment is already %', lower(v_a.status); end if;
  if v_a.requested_by = auth.uid() then raise exception 'You cannot reject an adjustment you requested; cancel it instead'; end if;
  if not auth_has_station_access(v_a.station_id) then raise exception 'You have no access to this station'; end if;
  update stock_adjustments set status = 'REJECTED', decided_by = auth.uid(), decided_at = now(), decision_note = trim(p_note) where id = p_id;
  perform write_audit_log(v_org, 'adjustment.reject', 'stock_adjustment', p_id, v_a.station_id, null, null, p_note);
end;
$$;

revoke execute on function request_stock_adjustment(uuid, uuid, text, integer, text, text),
  cancel_stock_adjustment(uuid), approve_stock_adjustment(uuid, text), reject_stock_adjustment(uuid, text) from public, anon;
grant execute on function request_stock_adjustment(uuid, uuid, text, integer, text, text),
  cancel_stock_adjustment(uuid), approve_stock_adjustment(uuid, text), reject_stock_adjustment(uuid, text) to authenticated;
