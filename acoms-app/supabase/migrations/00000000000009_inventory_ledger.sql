-- ============================================================================
-- ACOMS Migration 009: Inventory Ledger + Balances
--
-- Per CLAUDE.md > Inventory Integrity and equipment-management.md:
-- "Inventory changes require transactions. Normal operations cannot use
-- unexplained direct balance edits."
--
-- Design:
-- - inventory_transactions is the append-only source of truth (the ledger).
-- - inventory_balances is a derived/materialized cache for fast reads,
--   updated ONLY by apply_inventory_transaction() — never directly by the
--   application layer.
-- - NO_STOCK_TURNAROUND stations (ADR-012 station list) cannot hold a
--   balance row at all — enforced by trigger, not just convention, since
--   these stations by definition never carry equipment on the ground.
-- ============================================================================

create table inventory_balances (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete restrict,
  equipment_type_id uuid not null references equipment_types(id) on delete restrict,
  station_id uuid not null references stations(id) on delete restrict,

  available_quantity integer not null default 0,
  reserved_quantity integer not null default 0,
  in_transit_quantity integer not null default 0,
  damaged_quantity integer not null default 0,
  missing_quantity integer not null default 0,

  last_transaction_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (equipment_type_id, station_id),

  constraint chk_balances_non_negative check (
    available_quantity >= 0 and reserved_quantity >= 0 and
    in_transit_quantity >= 0 and damaged_quantity >= 0 and missing_quantity >= 0
  )
);

comment on table inventory_balances is
  'Derived cache only. Never write directly from application code — always go through apply_inventory_transaction(). Explainable at all times from inventory_transactions.';

create index idx_inventory_balances_station on inventory_balances (station_id);
create index idx_inventory_balances_equipment on inventory_balances (equipment_type_id);

-- Prevent a balance row from ever being created at a NO_STOCK_TURNAROUND
-- station — these stations do not carry equipment on the ground by design
-- (see decisions.md ADR-012 / the 8-station turnaround list).
create or replace function prevent_balance_at_turnaround_station()
returns trigger
language plpgsql
as $$
declare
  v_station_type text;
begin
  select station_type into v_station_type from stations where id = new.station_id;
  if v_station_type = 'NO_STOCK_TURNAROUND' then
    raise exception 'Station % is a no-stock turnaround station and cannot hold an inventory balance', new.station_id;
  end if;
  return new;
end;
$$;

create trigger trg_prevent_turnaround_balance
  before insert or update on inventory_balances
  for each row execute function prevent_balance_at_turnaround_station();

-- ----------------------------------------------------------------------------
-- Inventory ledger (append-only)
-- ----------------------------------------------------------------------------
create table inventory_transactions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete restrict,
  equipment_type_id uuid not null references equipment_types(id) on delete restrict,
  station_id uuid not null references stations(id) on delete restrict,

  transaction_type text not null check (transaction_type in (
    'OPENING_BALANCE', 'RECEIPT', 'TRANSFER_OUT', 'TRANSFER_IN', 'RETURN',
    'DAMAGE', 'LOSS', 'ADJUSTMENT', 'DISPOSAL', 'RECOVERY'
  )),

  -- Positive = increases available_quantity, negative = decreases.
  -- Sign convention is enforced in apply_inventory_transaction(), not left
  -- to the caller, so TRANSFER_OUT etc. can't be inserted with the wrong sign.
  quantity integer not null,

  -- Optional link to the operational record that caused this transaction
  -- (e.g. an equipment_transfers row) — nullable because not every
  -- transaction type has one yet (transfers table doesn't exist until the
  -- next slice).
  reference_type text,
  reference_id uuid,

  performed_by uuid references user_profiles(id) on delete set null,
  reason text,

  created_at timestamptz not null default now()
);

comment on table inventory_transactions is
  'Append-only ledger. No update or delete policy exists — a mistake is corrected with a compensating ADJUSTMENT transaction, never by editing history.';

create index idx_inventory_tx_station_equipment on inventory_transactions (station_id, equipment_type_id, created_at desc);
create index idx_inventory_tx_reference on inventory_transactions (reference_type, reference_id);

-- ----------------------------------------------------------------------------
-- apply_inventory_transaction: the ONLY sanctioned way to change a balance.
-- Inserts the ledger row and updates the balance atomically, enforcing the
-- non-negative constraint and the sign convention per transaction type.
-- ----------------------------------------------------------------------------
create or replace function apply_inventory_transaction(
  p_equipment_type_id uuid,
  p_station_id uuid,
  p_transaction_type text,
  p_quantity integer,   -- always a positive magnitude; sign is derived below
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

  -- Sign convention: increases vs decreases to available_quantity.
  v_signed_quantity := case p_transaction_type
    when 'OPENING_BALANCE' then p_quantity
    when 'RECEIPT' then p_quantity
    when 'TRANSFER_IN' then p_quantity
    when 'RETURN' then p_quantity
    when 'RECOVERY' then p_quantity
    when 'ADJUSTMENT' then p_quantity -- adjustments may be signed by caller in future; MVP treats as increase
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

comment on function apply_inventory_transaction is
  'The only sanctioned way to change inventory_balances. Enforces sign convention per transaction_type and the non-negative balance constraint (via chk_balances_non_negative), and writes both the ledger row and an audit entry atomically.';

-- ----------------------------------------------------------------------------
-- RLS
-- ----------------------------------------------------------------------------
alter table inventory_balances enable row level security;
alter table inventory_transactions enable row level security;

create policy "inventory_balances_select_station_scoped"
  on inventory_balances for select
  using (
    organization_id = auth_organization_id()
    and auth_has_permission('view_inventory')
    and auth_has_station_access(station_id)
  );

-- No direct insert/update/delete policy — all writes go through
-- apply_inventory_transaction() (SECURITY DEFINER), by design.

create policy "inventory_transactions_select_station_scoped"
  on inventory_transactions for select
  using (
    organization_id = auth_organization_id()
    and auth_has_permission('view_inventory')
    and auth_has_station_access(station_id)
  );

-- No direct insert/update/delete policy on the ledger either — same reason.
