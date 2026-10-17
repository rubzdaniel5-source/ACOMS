-- ============================================================================
-- ACOMS Migration 034: receipt with condition, partial receipt, held excess (step 4)
--
-- Receiving now records, per line and per receipt, what the receiver physically
-- COUNTED and how much of it was DAMAGED. Nothing is copied from the dispatch.
--   accepted = counted (up to what is still expected) minus damaged  -> available
--   damaged                                                          -> damaged bucket + damage report
--   excess   = counted beyond what was dispatched                    -> HELD bucket + excess hold
--   short    = dispatched minus accepted minus damaged               -> a reported shortage; it is
--              NOT a loss until it is explained at reconciliation and investigated
-- A receipt can be partial: the transfer stays PARTIALLY_RECEIVED (open and
-- visible) until a final receipt is recorded. Every receipt and its counts are
-- kept as they were entered. Held excess is never available stock: it is
-- investigated by one person and its treatment authorised by another.
-- Outstation returns to the hub need no separate approval (policy decision).
-- ============================================================================

-- ---- Schema -----------------------------------------------------------------
alter table inventory_balances add column if not exists held_quantity integer not null default 0;
alter table inventory_balances drop constraint if exists chk_balances_held_non_negative;
alter table inventory_balances add constraint chk_balances_held_non_negative check (held_quantity >= 0);

alter table inventory_transactions drop constraint if exists inventory_transactions_transaction_type_check;
alter table inventory_transactions add constraint inventory_transactions_transaction_type_check check (transaction_type in (
  'OPENING_BALANCE', 'RECEIPT', 'TRANSFER_OUT', 'TRANSFER_IN', 'RETURN',
  'DAMAGE', 'LOSS', 'ADJUSTMENT', 'DISPOSAL', 'RECOVERY', 'ADJUSTMENT_DECREASE', 'EXCESS_HOLD', 'EXCESS_RELEASE'));

alter table equipment_transfer_items
  add column if not exists quantity_counted integer not null default 0,
  add column if not exists quantity_damaged_on_receipt integer not null default 0,
  add column if not exists quantity_excess_held integer not null default 0,
  add column if not exists quantity_short integer not null default 0;

alter table equipment_transfers add column if not exists approval_waived boolean not null default false;

create table equipment_transfer_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete restrict,
  transfer_id uuid not null references equipment_transfers(id) on delete restrict,
  receipt_number integer not null,
  is_final boolean not null,
  received_by uuid not null references user_profiles(id) on delete restrict,
  received_at timestamptz not null default now(),
  notes text,
  unique (transfer_id, receipt_number)
);
create table equipment_transfer_receipt_lines (
  id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references equipment_transfer_receipts(id) on delete restrict,
  item_id uuid not null references equipment_transfer_items(id) on delete restrict,
  quantity_counted integer not null check (quantity_counted >= 0),
  quantity_damaged integer not null check (quantity_damaged >= 0),
  quantity_accepted integer not null check (quantity_accepted >= 0),
  quantity_excess integer not null check (quantity_excess >= 0),
  unique (receipt_id, item_id),
  constraint chk_receipt_line_damaged check (quantity_damaged <= quantity_counted)
);
create table excess_holds (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete restrict,
  transfer_id uuid not null references equipment_transfers(id) on delete restrict,
  item_id uuid not null references equipment_transfer_items(id) on delete restrict,
  station_id uuid not null references stations(id) on delete restrict,
  equipment_type_id uuid not null references equipment_types(id) on delete restrict,
  quantity integer not null check (quantity > 0),
  status text not null default 'HELD' check (status in ('HELD', 'INVESTIGATING', 'RELEASED', 'REMOVED')),
  held_by uuid not null references user_profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  investigated_by uuid references user_profiles(id) on delete restrict,
  investigated_at timestamptz,
  findings text,
  decided_by uuid references user_profiles(id) on delete restrict,
  decided_at timestamptz,
  treatment text check (treatment in ('ACCEPT_AS_STOCK', 'REMOVE_FROM_RECORDS')),
  decision_reason text
);
create index idx_excess_holds_open on excess_holds (station_id) where status in ('HELD', 'INVESTIGATING');
create index idx_excess_holds_transfer on excess_holds (transfer_id);

alter table equipment_transfer_receipts enable row level security;
alter table equipment_transfer_receipt_lines enable row level security;
alter table excess_holds enable row level security;
create policy "receipts_select" on equipment_transfer_receipts for select using (
  organization_id = auth_organization_id() and exists (select 1 from equipment_transfers t where t.id = transfer_id));
create policy "receipt_lines_select" on equipment_transfer_receipt_lines for select using (
  exists (select 1 from equipment_transfer_receipts r where r.id = receipt_id));
create policy "excess_holds_select" on excess_holds for select using (
  organization_id = auth_organization_id() and auth_has_permission('view_inventory') and auth_has_station_access(station_id));
-- No write policies: all changes go through the functions below.

create or replace view v_excess_holds with (security_invoker = true) as
select h.id, h.transfer_id, t.transfer_number, h.status, h.quantity, h.created_at, h.station_id, s.code as station_code,
       e.source_code, e.name as equipment_name, h.held_by, h.investigated_by, h.findings, h.treatment, h.decision_reason
from excess_holds h
join equipment_transfers t on t.id = h.transfer_id
join stations s on s.id = h.station_id
join equipment_types e on e.id = h.equipment_type_id;

-- ---- Ledger: two new entry types ---------------------------------------------------
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
    when 'EXCESS_RELEASE' then p_quantity
    when 'TRANSFER_OUT' then -p_quantity
    when 'DAMAGE' then -p_quantity
    when 'LOSS' then -p_quantity
    when 'DISPOSAL' then -p_quantity
    when 'ADJUSTMENT_DECREASE' then -p_quantity
    when 'EXCESS_HOLD' then -p_quantity
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

revoke execute on function apply_inventory_transaction(uuid, uuid, text, integer, text, uuid, text) from public, anon, authenticated;

-- ---- Integrity checks include the held bucket -------------------------------------
create or replace function _integrity_failures()
returns table (check_code text, station_code text, source_code text, equipment_name text, expected bigint, actual bigint, detail text)
language sql stable security definer set search_path = public as $$
  -- A. Available balance must equal the sum of the ledger.
  select 'LEDGER_MATCH', s.code, e.source_code, e.name, coalesce(l.total, 0)::bigint, coalesce(b.available_quantity, 0)::bigint,
         'Available balance differs from the sum of ledger entries'
  from (select station_id, equipment_type_id from inventory_balances
        union select station_id, equipment_type_id from inventory_transactions) k
  join stations s on s.id = k.station_id and s.organization_id = auth_organization_id()
  join equipment_types e on e.id = k.equipment_type_id
  left join inventory_balances b on b.station_id = k.station_id and b.equipment_type_id = k.equipment_type_id
  left join (select station_id, equipment_type_id, sum(quantity) as total from inventory_transactions group by 1, 2) l
    on l.station_id = k.station_id and l.equipment_type_id = k.equipment_type_id
  where coalesce(l.total, 0) <> coalesce(b.available_quantity, 0)
  union all
  -- B. Damaged bucket must equal open damage reports.
  select 'DAMAGED_MATCH', s.code, e.source_code, e.name, coalesce(r.total, 0)::bigint, coalesce(b.damaged_quantity, 0)::bigint,
         'Damaged quantity differs from open damage reports'
  from (select station_id, equipment_type_id from inventory_balances union select station_id, equipment_type_id from damage_reports) k
  join stations s on s.id = k.station_id and s.organization_id = auth_organization_id()
  join equipment_types e on e.id = k.equipment_type_id
  left join inventory_balances b on b.station_id = k.station_id and b.equipment_type_id = k.equipment_type_id
  left join (select station_id, equipment_type_id, sum(quantity) as total from damage_reports
             where status in ('REPORTED','UNDER_REVIEW','ASSESSED','REPAIR','RETIRED') group by 1, 2) r
    on r.station_id = k.station_id and r.equipment_type_id = k.equipment_type_id
  where coalesce(r.total, 0) <> coalesce(b.damaged_quantity, 0)
  union all
  -- C. Missing bucket must equal open loss reports.
  select 'MISSING_MATCH', s.code, e.source_code, e.name, coalesce(r.total, 0)::bigint, coalesce(b.missing_quantity, 0)::bigint,
         'Missing quantity differs from open loss reports'
  from (select station_id, equipment_type_id from inventory_balances union select station_id, equipment_type_id from loss_reports) k
  join stations s on s.id = k.station_id and s.organization_id = auth_organization_id()
  join equipment_types e on e.id = k.equipment_type_id
  left join inventory_balances b on b.station_id = k.station_id and b.equipment_type_id = k.equipment_type_id
  left join (select station_id, equipment_type_id, sum(quantity) as total from loss_reports
             where status in ('REPORTED','INVESTIGATION') group by 1, 2) r
    on r.station_id = k.station_id and r.equipment_type_id = k.equipment_type_id
  where coalesce(r.total, 0) <> coalesce(b.missing_quantity, 0)
  union all
  -- D. In-transit bucket must equal dispatched-but-unreconciled transfer lines at the source station.
  select 'IN_TRANSIT_MATCH', s.code, e.source_code, e.name, coalesce(t.total, 0)::bigint, coalesce(b.in_transit_quantity, 0)::bigint,
         'In-transit quantity differs from open transfers'
  from (select station_id, equipment_type_id from inventory_balances
        union select tr.from_station_id, i.equipment_type_id from equipment_transfer_items i join equipment_transfers tr on tr.id = i.transfer_id) k
  join stations s on s.id = k.station_id and s.organization_id = auth_organization_id()
  join equipment_types e on e.id = k.equipment_type_id
  left join inventory_balances b on b.station_id = k.station_id and b.equipment_type_id = k.equipment_type_id
  left join (select tr.from_station_id as station_id, i.equipment_type_id, sum(coalesce(i.quantity_dispatched, 0)) as total
             from equipment_transfer_items i join equipment_transfers tr on tr.id = i.transfer_id
             where tr.status in ('DISPATCHED','IN_TRANSIT','RECEIVED','PARTIALLY_RECEIVED') group by 1, 2) t
    on t.station_id = k.station_id and t.equipment_type_id = k.equipment_type_id
  where coalesce(t.total, 0) <> coalesce(b.in_transit_quantity, 0)
  union all
  -- E. Sign convention: increases positive, decreases negative.
  select 'LEDGER_SIGNS', s.code, e.source_code, e.name, 0::bigint, count(*)::bigint, 'Ledger entries with the wrong sign for their type'
  from inventory_transactions x
  join stations s on s.id = x.station_id and s.organization_id = auth_organization_id()
  join equipment_types e on e.id = x.equipment_type_id
  where (x.transaction_type in ('OPENING_BALANCE','RECEIPT','TRANSFER_IN','RETURN','RECOVERY','ADJUSTMENT','EXCESS_RELEASE') and x.quantity < 0)
     or (x.transaction_type in ('TRANSFER_OUT','DAMAGE','LOSS','DISPOSAL','ADJUSTMENT_DECREASE','EXCESS_HOLD') and x.quantity > 0)
  group by s.code, e.source_code, e.name
  union all
  -- F. Stock held at a no-stock station.
  select 'NO_STOCK_STATIONS', s.code, e.source_code, e.name, 0::bigint,
         (b.available_quantity + b.in_transit_quantity + b.damaged_quantity + b.missing_quantity + b.held_quantity)::bigint,
         'Stock recorded at a no-stock turnaround station'
  from inventory_balances b
  join stations s on s.id = b.station_id and s.organization_id = auth_organization_id() and s.station_type = 'NO_STOCK_TURNAROUND'
  join equipment_types e on e.id = b.equipment_type_id
  where (b.available_quantity + b.in_transit_quantity + b.damaged_quantity + b.missing_quantity + b.held_quantity) > 0
  union all
  -- H. Held-excess bucket must equal open excess holds.
  select 'HELD_MATCH', s.code, e.source_code, e.name, coalesce(r.total, 0)::bigint, coalesce(b.held_quantity, 0)::bigint,
         'Held excess differs from open excess holds'
  from (select station_id, equipment_type_id from inventory_balances union select station_id, equipment_type_id from excess_holds) k
  join stations s on s.id = k.station_id and s.organization_id = auth_organization_id()
  join equipment_types e on e.id = k.equipment_type_id
  left join inventory_balances b on b.station_id = k.station_id and b.equipment_type_id = k.equipment_type_id
  left join (select station_id, equipment_type_id, sum(quantity) as total from excess_holds
             where status in ('HELD','INVESTIGATING') group by 1, 2) r
    on r.station_id = k.station_id and r.equipment_type_id = k.equipment_type_id
  where coalesce(r.total, 0) <> coalesce(b.held_quantity, 0)
  union all
  -- G. Approved adjustments must have a ledger entry.
  select 'ADJUSTMENT_LEDGER', s.code, e.source_code, e.name, 1::bigint, 0::bigint, a.adjustment_number || ' approved without a ledger entry'
  from stock_adjustments a
  join stations s on s.id = a.station_id and s.organization_id = auth_organization_id()
  join equipment_types e on e.id = a.equipment_type_id
  where a.status = 'APPROVED' and a.ledger_transaction_id is null;
$$;

create or replace function integrity_summary()
returns table (check_code text, label text, description text, examined bigint, failures bigint)
language plpgsql security definer set search_path = public as $$
declare v_org uuid := auth_organization_id();
begin
  if auth.uid() is null or v_org is null then raise exception 'Not authenticated'; end if;
  if not auth_has_permission('manage_configuration') then raise exception 'Permission denied: manage_configuration required'; end if;
  return query
  with f as (select x.check_code, count(*) as n from _integrity_failures() x group by 1),
       c(check_code, label, description, examined) as (values
    ('LEDGER_MATCH', 'Available stock matches the ledger', 'For every station and equipment type, the available balance equals the sum of all ledger entries.',
       (select count(*) from inventory_balances where organization_id = v_org)),
    ('DAMAGED_MATCH', 'Damaged stock matches damage reports', 'The damaged balance equals the open damage reports.',
       (select count(*) from damage_reports where organization_id = v_org)),
    ('MISSING_MATCH', 'Missing stock matches loss reports', 'The missing balance equals the open loss reports.',
       (select count(*) from loss_reports where organization_id = v_org)),
    ('IN_TRANSIT_MATCH', 'In-transit stock matches open transfers', 'The in-transit balance equals dispatched, unreconciled transfer lines.',
       (select count(*) from equipment_transfers where organization_id = v_org)),
    ('HELD_MATCH', 'Held excess matches open holds', 'The held-excess balance equals the excess holds still under investigation.',
       (select count(*) from excess_holds where organization_id = v_org)),
    ('LEDGER_SIGNS', 'Ledger signs are consistent', 'Increases are positive and decreases negative for every entry type.',
       (select count(*) from inventory_transactions where organization_id = v_org)),
    ('NO_STOCK_STATIONS', 'No stock at no-stock stations', 'Turnaround stations hold no equipment.',
       (select count(*) from stations where organization_id = v_org and station_type = 'NO_STOCK_TURNAROUND')),
    ('ADJUSTMENT_LEDGER', 'Approved adjustments are in the ledger', 'Every approved adjustment produced a ledger entry.',
       (select count(*) from stock_adjustments where organization_id = v_org and status = 'APPROVED')))
  select c.check_code, c.label, c.description, c.examined, coalesce(f.n, 0) from c left join f on f.check_code = c.check_code;
  perform write_audit_log(v_org, 'integrity.check', 'integrity_check', gen_random_uuid(), null, null,
    jsonb_build_object('failures', (select count(*) from _integrity_failures())), null);
end;
$$;

revoke execute on function _integrity_failures() from public, anon, authenticated;
revoke execute on function integrity_summary() from public, anon;
grant execute on function integrity_summary() to authenticated;

-- ---- Receive ---------------------------------------------------------------------------
drop function if exists receive_transfer(uuid, jsonb);
create or replace function receive_transfer(
  p_transfer_id uuid,
  p_received_items jsonb,
  p_final boolean default true,
  p_notes text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_t equipment_transfers%rowtype;
  v_item jsonb;
  v_line equipment_transfer_items%rowtype;
  v_c integer; v_d integer; v_remaining integer; v_exp integer; v_exc integer; v_acc integer;
  v_receipt uuid; v_no integer; v_report uuid; v_hold uuid;
begin
  select * into v_t from equipment_transfers where id = p_transfer_id for update;
  if not found then raise exception 'Transfer % not found', p_transfer_id; end if;
  if v_t.status not in ('IN_TRANSIT', 'PARTIALLY_RECEIVED') then
    raise exception 'Transfer must be IN_TRANSIT or PARTIALLY_RECEIVED to receive (current status: %)', v_t.status;
  end if;
  if not auth_has_permission('receive_transfer') then raise exception 'Missing permission: receive_transfer'; end if;
  if not auth_has_station_access(v_t.to_station_id) then raise exception 'No station access to destination station'; end if;

  perform _assert_unique_items(p_received_items, true);
  if exists (select 1 from jsonb_array_elements(p_received_items) e
              where not exists (select 1 from equipment_transfer_items i where i.transfer_id = p_transfer_id and i.id::text = e->>'item_id')) then
    raise exception 'Item does not belong to this transfer';
  end if;
  if jsonb_array_length(p_received_items) = 0 and not p_final then
    raise exception 'Count at least one item, or mark this as the final receipt';
  end if;
  if p_final and exists (
       select 1 from equipment_transfer_items i
        where i.transfer_id = p_transfer_id
          and not exists (select 1 from jsonb_array_elements(p_received_items) e where e->>'item_id' = i.id::text)
          and not exists (select 1 from equipment_transfer_receipt_lines rl join equipment_transfer_receipts r on r.id = rl.receipt_id
                           where rl.item_id = i.id and r.transfer_id = p_transfer_id)) then
    raise exception 'Every item on the transfer must be counted';
  end if;

  select coalesce(max(receipt_number), 0) + 1 into v_no from equipment_transfer_receipts where transfer_id = p_transfer_id;
  insert into equipment_transfer_receipts (organization_id, transfer_id, receipt_number, is_final, received_by, notes)
  values (v_t.organization_id, p_transfer_id, v_no, p_final, auth.uid(), nullif(trim(p_notes), ''))
  returning id into v_receipt;

  for v_item in select * from jsonb_array_elements(p_received_items)
  loop
    select * into v_line from equipment_transfer_items
     where id = (v_item->>'item_id')::uuid and transfer_id = p_transfer_id;
    if not found then raise exception 'Item does not belong to this transfer'; end if;
    v_c := coalesce(v_item->>'quantity_counted', v_item->>'quantity_received')::integer;
    v_d := coalesce((v_item->>'quantity_damaged')::integer, 0);
    if v_c is null then raise exception 'Enter the counted quantity for every item'; end if;
    if v_c < 0 or v_d < 0 then raise exception 'Counted and damaged quantities cannot be negative'; end if;
    if v_d > v_c then raise exception 'Damaged units (%) cannot exceed the units counted (%)', v_d, v_c; end if;

    v_remaining := greatest(coalesce(v_line.quantity_dispatched, 0) - coalesce(v_line.quantity_received, 0) - v_line.quantity_damaged_on_receipt, 0);
    v_exp := least(v_c, v_remaining);
    v_exc := v_c - v_exp;
    if v_d > v_exp then
      raise exception 'Damaged units (%) cannot exceed the expected quantity (%). Excess units are held for investigation first.', v_d, v_exp;
    end if;
    v_acc := v_exp - v_d;

    if v_acc > 0 then
      perform apply_inventory_transaction(v_line.equipment_type_id, v_t.to_station_id, 'TRANSFER_IN', v_acc,
        'equipment_transfer', p_transfer_id, 'Received on transfer ' || v_t.transfer_number);
    end if;
    if v_d > 0 then
      insert into damage_reports (organization_id, station_id, equipment_type_id, quantity, reported_by, reason)
      values (v_t.organization_id, v_t.to_station_id, v_line.equipment_type_id, v_d, auth.uid(),
              'Found damaged on receipt, transfer ' || v_t.transfer_number) returning id into v_report;
      perform apply_inventory_transaction(v_line.equipment_type_id, v_t.to_station_id, 'TRANSFER_IN', v_d,
        'equipment_transfer', p_transfer_id, 'Damaged units on transfer ' || v_t.transfer_number);
      perform apply_inventory_transaction(v_line.equipment_type_id, v_t.to_station_id, 'DAMAGE', v_d,
        'damage_report', v_report, 'Found damaged on receipt, transfer ' || v_t.transfer_number);
      update inventory_balances set damaged_quantity = damaged_quantity + v_d, updated_at = now()
       where equipment_type_id = v_line.equipment_type_id and station_id = v_t.to_station_id;
    end if;
    if v_exc > 0 then
      insert into excess_holds (organization_id, transfer_id, item_id, station_id, equipment_type_id, quantity, held_by)
      values (v_t.organization_id, p_transfer_id, v_line.id, v_t.to_station_id, v_line.equipment_type_id, v_exc, auth.uid())
      returning id into v_hold;
      perform apply_inventory_transaction(v_line.equipment_type_id, v_t.to_station_id, 'TRANSFER_IN', v_exc,
        'equipment_transfer', p_transfer_id, 'Excess units on transfer ' || v_t.transfer_number);
      perform apply_inventory_transaction(v_line.equipment_type_id, v_t.to_station_id, 'EXCESS_HOLD', v_exc,
        'excess_hold', v_hold, 'Held for investigation, transfer ' || v_t.transfer_number);
      update inventory_balances set held_quantity = held_quantity + v_exc, updated_at = now()
       where equipment_type_id = v_line.equipment_type_id and station_id = v_t.to_station_id;
    end if;

    insert into equipment_transfer_receipt_lines (receipt_id, item_id, quantity_counted, quantity_damaged, quantity_accepted, quantity_excess)
    values (v_receipt, v_line.id, v_c, v_d, v_acc, v_exc);
    update equipment_transfer_items
       set quantity_received = coalesce(quantity_received, 0) + v_acc,
           quantity_damaged_on_receipt = quantity_damaged_on_receipt + v_d,
           quantity_damaged = quantity_damaged_on_receipt + v_d,
           quantity_excess_held = quantity_excess_held + v_exc,
           quantity_counted = quantity_counted + v_c
     where id = v_line.id;
  end loop;

  if p_final then
    update equipment_transfer_items
       set quantity_short = greatest(coalesce(quantity_dispatched, 0) - coalesce(quantity_received, 0) - quantity_damaged_on_receipt, 0)
     where transfer_id = p_transfer_id;
    update equipment_transfers set status = 'RECEIVED', received_by = auth.uid(), received_at = now() where id = p_transfer_id;
  else
    update equipment_transfers set status = 'PARTIALLY_RECEIVED' where id = p_transfer_id;
  end if;

  perform write_audit_log(v_t.organization_id, case when p_final then 'transfer.receive' else 'transfer.receive_partial' end,
    'equipment_transfer', p_transfer_id, v_t.to_station_id, jsonb_build_object('status', v_t.status),
    jsonb_build_object('status', case when p_final then 'RECEIVED' else 'PARTIALLY_RECEIVED' end, 'receipt', v_no), p_notes);
end;
$$;

-- ---- Reconcile / resolve (explanations only; damage on receipt is already recorded) --------
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
  select * into v_transfer from equipment_transfers where id = p_transfer_id for update;
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

  perform _assert_unique_items(p_reconciliation_items, true);
  for v_item in select * from jsonb_array_elements(p_reconciliation_items)
  loop
    v_damaged := coalesce((v_item->>'quantity_damaged')::integer, 0);
    v_missing := coalesce((v_item->>'quantity_missing')::integer, 0);
    if v_damaged < 0 or v_missing < 0 then raise exception 'Damaged and missing quantities cannot be negative'; end if;

    update equipment_transfer_items
    set quantity_damaged = coalesce(quantity_damaged_on_receipt, 0) + v_damaged, quantity_missing = v_missing
    where id = (v_item->>'item_id')::uuid and transfer_id = p_transfer_id
    returning * into v_line;
    if not found then raise exception 'Item does not belong to this transfer'; end if;

    select reconciliation_tolerance into v_tolerance from equipment_types where id = v_line.equipment_type_id;

    v_unexplained := coalesce(v_line.quantity_dispatched, 0) - coalesce(v_line.quantity_received, 0) - coalesce(v_line.quantity_damaged, 0) - v_missing;
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

  if exists (select 1 from excess_holds where transfer_id = p_transfer_id and status in ('HELD', 'INVESTIGATING')) then
    v_has_discrepancy := true;
  end if;

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
  select * into v_transfer from equipment_transfers where id = p_transfer_id for update;
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

  if exists (select 1 from excess_holds where transfer_id = p_transfer_id and status in ('HELD', 'INVESTIGATING')) then
    raise exception 'Excess units from this transfer are still held for investigation. Resolve the excess first.';
  end if;

  update equipment_transfers
  set status = 'RECONCILIATION', notes = coalesce(notes || E'\n', '') || 'RESOLVED: ' || p_resolution_reason
  where id = p_transfer_id;

  perform write_audit_log(v_transfer.organization_id, 'transfer.resolve_discrepancy', 'equipment_transfer', p_transfer_id,
    v_transfer.to_station_id, jsonb_build_object('status', 'DISCREPANCY'),
    jsonb_build_object('status', 'RECONCILIATION'), p_resolution_reason);
end;
$$;

revoke execute on function receive_transfer(uuid, jsonb, boolean, text), reconcile_transfer(uuid, jsonb, text), resolve_discrepancy(uuid, text) from public, anon;
grant execute on function receive_transfer(uuid, jsonb, boolean, text), reconcile_transfer(uuid, jsonb, text), resolve_discrepancy(uuid, text) to authenticated;

-- ---- Held excess: investigate, then a different person authorises the treatment ---------
create or replace function record_excess_investigation(p_hold_id uuid, p_findings text)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid := auth_organization_id(); v_h excess_holds%rowtype;
begin
  if auth.uid() is null or v_org is null then raise exception 'Not authenticated'; end if;
  select * into v_h from excess_holds where id = p_hold_id and organization_id = v_org for update;
  if not found then raise exception 'Excess hold not found'; end if;
  if not auth_has_permission('reconcile_transfer') then raise exception 'Missing permission: reconcile_transfer'; end if;
  if not auth_has_station_access(v_h.station_id) then raise exception 'No station access to this hold'; end if;
  if v_h.status <> 'HELD' then raise exception 'Only a held excess can be investigated (current status: %)', v_h.status; end if;
  if length(trim(coalesce(p_findings, ''))) < 10 then raise exception 'Record what the investigation found (at least 10 characters)'; end if;
  update excess_holds set status = 'INVESTIGATING', investigated_by = auth.uid(), investigated_at = now(), findings = trim(p_findings) where id = p_hold_id;
  perform write_audit_log(v_org, 'excess.investigate', 'excess_hold', p_hold_id, v_h.station_id,
    jsonb_build_object('status', 'HELD'), jsonb_build_object('status', 'INVESTIGATING'), trim(p_findings));
end $$;

create or replace function resolve_excess_hold(p_hold_id uuid, p_treatment text, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid := auth_organization_id(); v_h excess_holds%rowtype;
begin
  if auth.uid() is null or v_org is null then raise exception 'Not authenticated'; end if;
  select * into v_h from excess_holds where id = p_hold_id and organization_id = v_org for update;
  if not found then raise exception 'Excess hold not found'; end if;
  if not auth_has_permission('approve_adjustment') then raise exception 'Missing permission: approve_adjustment'; end if;
  if not auth_has_station_access(v_h.station_id) then raise exception 'No station access to this hold'; end if;
  if v_h.status <> 'INVESTIGATING' then raise exception 'The excess must be investigated before its treatment is authorised (current status: %)', v_h.status; end if;
  if auth.uid() in (v_h.held_by, v_h.investigated_by) then
    raise exception 'The person who counted or investigated the excess cannot authorise its treatment'; end if;
  if p_treatment not in ('ACCEPT_AS_STOCK', 'REMOVE_FROM_RECORDS') then raise exception 'Unknown treatment %', p_treatment; end if;
  if length(trim(coalesce(p_reason, ''))) < 10 then raise exception 'Give the reason for this treatment (at least 10 characters)'; end if;

  if p_treatment = 'ACCEPT_AS_STOCK' then
    perform apply_inventory_transaction(v_h.equipment_type_id, v_h.station_id, 'EXCESS_RELEASE', v_h.quantity,
      'excess_hold', p_hold_id, 'Excess accepted as stock: ' || trim(p_reason));
  end if;
  update inventory_balances set held_quantity = greatest(0, held_quantity - v_h.quantity), updated_at = now()
   where equipment_type_id = v_h.equipment_type_id and station_id = v_h.station_id;
  update excess_holds set status = case p_treatment when 'ACCEPT_AS_STOCK' then 'RELEASED' else 'REMOVED' end,
         decided_by = auth.uid(), decided_at = now(), treatment = p_treatment, decision_reason = trim(p_reason) where id = p_hold_id;
  perform write_audit_log(v_org, 'excess.resolve', 'excess_hold', p_hold_id, v_h.station_id,
    jsonb_build_object('status', 'INVESTIGATING'), jsonb_build_object('treatment', p_treatment, 'quantity', v_h.quantity), trim(p_reason));
end $$;

revoke execute on function record_excess_investigation(uuid, text), resolve_excess_hold(uuid, text, text) from public, anon;
grant execute on function record_excess_investigation(uuid, text), resolve_excess_hold(uuid, text, text) to authenticated;

-- ---- Dashboard views: partially received transfers stay visible ------------------------------
create or replace view v_pending_transfers as
with cfg as (
  select get_setting('transfers.approval_overdue_hours') as hrs,
         get_setting('transfers.total_overdue_days') as days,
         get_setting('transfers.reconciliation_overdue_days') as rdays
)
select
  t.id, t.transfer_number, t.status, t.priority,
  fs.code as from_station_code, ts.code as to_station_code, t.requested_at,
  extract(epoch from (now() - t.requested_at)) / 3600 as hours_since_requested,
  case
    when t.status = 'REQUESTED' and now() - t.requested_at > make_interval(hours => cfg.hrs::int) then true
    when t.status in ('APPROVED', 'DISPATCHED', 'IN_TRANSIT', 'PARTIALLY_RECEIVED') and now() - t.requested_at > make_interval(days => cfg.days::int) then true
    when t.status = 'RECEIVED' and now() - coalesce(t.received_at, t.updated_at) > make_interval(days => cfg.rdays::int) then true
    when t.status = 'RECONCILIATION' and now() - t.updated_at > make_interval(days => cfg.rdays::int) then true
    else false
  end as is_overdue,
  case
    when t.status = 'REQUESTED' then 'APPROVAL'
    when t.status in ('APPROVED', 'DISPATCHED', 'IN_TRANSIT', 'PARTIALLY_RECEIVED') then 'OPEN'
    when t.status = 'RECEIVED' then 'RECONCILE'
    when t.status = 'RECONCILIATION' then 'CLOSE'
    else 'OPEN'
  end as overdue_kind,
  extract(epoch from (now() - case
    when t.status = 'RECEIVED' then coalesce(t.received_at, t.updated_at)
    when t.status = 'RECONCILIATION' then t.updated_at
    else t.requested_at end)) / 3600 as hours_in_status
from equipment_transfers t
join stations fs on fs.id = t.from_station_id
join stations ts on ts.id = t.to_station_id
cross join cfg
where t.status not in ('CLOSED', 'REJECTED', 'CANCELLED');
alter view v_pending_transfers set (security_invoker = true);

create or replace view v_movement_funnel as
select
  count(*) filter (where status = 'REQUESTED') as awaiting_approval,
  count(*) filter (where status = 'APPROVED') as awaiting_dispatch,
  count(*) filter (where status = 'IN_TRANSIT') as in_transit,
  count(*) filter (where status in ('IN_TRANSIT', 'PARTIALLY_RECEIVED')) as awaiting_receipt,
  count(*) filter (where status = 'RECEIVED') as awaiting_reconciliation,
  count(*) filter (where status = 'DISCREPANCY') as disputed,
  count(*) filter (where status not in ('CLOSED', 'REJECTED', 'CANCELLED')) as total_requiring_action
from equipment_transfers;
alter view v_movement_funnel set (security_invoker = true);

-- ---- Exchange view: partial receipt shows as work still to do ---------------------------------
create or replace view v_equipment_exchanges with (security_invoker = true) as
select e.id, e.exchange_number, e.return_required, e.created_at, e.closed_at, e.close_kind, e.close_note,
       e.hub_station_id, e.outstation_id, h.code as hub_code, s.code as outstation_code,
       e.no_return_requested_at, e.no_return_requested_by, e.no_return_reason, e.no_return_decision, e.no_return_decision_note,
       (e.no_return_requested_at is not null and e.no_return_decision is null) as no_return_pending,
       o.id as outbound_id, o.transfer_number as outbound_number, o.status as outbound_status,
       o.flight_number as outbound_flight, o.flight_date as outbound_flight_date,
       r.id as return_id, r.transfer_number as return_number, r.status as return_status,
       r.flight_number as return_flight, r.flight_date as return_flight_date,
       (coalesce(o.status, '') = 'DISCREPANCY' or coalesce(r.status, '') = 'DISCREPANCY') as has_open_discrepancy,
       case
         when e.closed_at is not null then case e.close_kind when 'NORMAL' then 'CLOSED' else 'CLOSED_NO_RETURN' end
         when o.status in ('CANCELLED', 'REJECTED') then 'CANCELLED'
         when r.id is not null and r.status <> 'CLOSED' then 'RETURN_IN_PROGRESS'
         when o.status in ('REQUESTED', 'APPROVED', 'IN_TRANSIT', 'PARTIALLY_RECEIVED') then 'OUTBOUND'
         when o.status <> 'CLOSED' then 'OUTBOUND_RECONCILIATION'
         when r.id is null and e.return_required then 'AWAITING_RETURN'
         else 'READY_TO_CLOSE'
       end as status,
       case
         when e.closed_at is not null or o.status in ('CANCELLED', 'REJECTED') then null
         when r.id is not null and r.status <> 'CLOSED' then
           case r.status when 'REQUESTED' then 'Approve the return movement' when 'APPROVED' then 'Dispatch the return movement'
             when 'IN_TRANSIT' then 'Receive the return at the hub' when 'PARTIALLY_RECEIVED' then 'Receive the rest of the return' when 'RECEIVED' then 'Reconcile the return movement'
             when 'DISCREPANCY' then 'Resolve the return discrepancy' when 'RECONCILIATION' then 'Close the return movement'
             else 'Review the return movement' end
         when o.status = 'REQUESTED' then 'Approve the outbound movement'
         when o.status = 'APPROVED' then 'Dispatch the outbound movement'
         when o.status = 'IN_TRANSIT' then 'Receive at the outstation'
         when o.status = 'PARTIALLY_RECEIVED' then 'Receive the rest at the outstation'
         when o.status = 'RECEIVED' then 'Reconcile the outbound movement'
         when o.status = 'DISCREPANCY' then 'Resolve the outbound discrepancy'
         when o.status = 'RECONCILIATION' then 'Close the outbound movement'
         when r.id is null and e.return_required then
           case when e.no_return_requested_at is not null and e.no_return_decision is null then 'Decide the request to close without a return'
                else 'Record the return movement' end
         else 'Close the exchange'
       end as next_action,
       case
         when e.closed_at is not null or o.status in ('CANCELLED', 'REJECTED') then null
         when r.id is not null and r.status <> 'CLOSED' then
           case when r.status in ('REQUESTED', 'APPROVED') then s.code else h.code end
         when o.status in ('REQUESTED', 'APPROVED') then h.code
         when o.status in ('IN_TRANSIT', 'PARTIALLY_RECEIVED') then s.code
         when o.status in ('RECEIVED', 'DISCREPANCY', 'RECONCILIATION') then s.code
         when r.id is null and e.return_required then s.code
         else h.code
       end as next_station_code
from equipment_exchanges e
join stations h on h.id = e.hub_station_id
join stations s on s.id = e.outstation_id
left join equipment_transfers o on o.exchange_id = e.id and o.exchange_leg = 'OUTBOUND'
left join equipment_transfers r on r.exchange_id = e.id and r.exchange_leg = 'RETURN' and r.status not in ('CANCELLED', 'REJECTED')
;

-- ---- Outstation returns need no separate approval (policy decision) -------------------------------
do $$
declare v_def text; v_anchor constant text := 'perform set_transfer_flight(v_tid, v_leg);';
begin
  v_def := pg_get_functiondef('start_exchange_return(uuid, jsonb, text, text, text, date)'::regprocedure);
  if position(v_anchor in v_def) = 0 then raise exception 'start_exchange_return was not found in the expected form'; end if;
  v_def := replace(v_def, v_anchor, v_anchor || E'\n  update equipment_transfer_items set quantity_approved = quantity_requested where transfer_id = v_tid;\n  update equipment_transfers set status = ''APPROVED'', approval_waived = true, approved_at = now() where id = v_tid;\n  perform write_audit_log(v_org, ''transfer.approval_waived'', ''equipment_transfer'', v_tid, v_e.outstation_id, jsonb_build_object(''status'', ''REQUESTED''), jsonb_build_object(''status'', ''APPROVED''), ''Outstation return to the hub: no separate approval required'');');
  execute v_def;
end $$;
