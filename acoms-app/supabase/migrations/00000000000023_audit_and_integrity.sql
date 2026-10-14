-- ============================================================================
-- ACOMS Migration 023: Audit Hardening & Inventory Integrity (Admin Batch 6)
--
-- 1. audit_logs readable org-wide only with manage_configuration; report
--    viewers see just their own stations' entries.
-- 2. audit_logs and inventory_transactions become tamper-proof: UPDATE and
--    DELETE are rejected by trigger (the only allowed change is the foreign-key
--    clean-up that nulls a deleted user/station reference).
-- 3. integrity_summary() / integrity_details(): reconcile every stock bucket
--    against the records that should explain it.
-- ============================================================================

-- 1. Audit visibility
drop policy if exists "audit_logs_select_with_permission" on audit_logs;
create policy "audit_logs_select_scoped" on audit_logs for select using (
  organization_id = auth_organization_id()
  and (
    auth_has_permission('manage_configuration')
    or (auth_has_permission('view_reports') and station_id is not null and auth_has_station_access(station_id))
  )
);

-- 2. Immutability
create or replace function prevent_ledger_tampering() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then
    raise exception '% is append-only: rows cannot be deleted', tg_table_name;
  end if;
  -- UPDATE: allow only nulling a reference column (FK ON DELETE SET NULL).
  if tg_table_name = 'audit_logs' then
    if (to_jsonb(new) - 'actor_id' - 'station_id') = (to_jsonb(old) - 'actor_id' - 'station_id')
       and (new.actor_id is not distinct from old.actor_id or new.actor_id is null)
       and (new.station_id is not distinct from old.station_id or new.station_id is null) then
      return new;
    end if;
  elsif tg_table_name = 'inventory_transactions' then
    if (to_jsonb(new) - 'performed_by') = (to_jsonb(old) - 'performed_by')
       and (new.performed_by is not distinct from old.performed_by or new.performed_by is null) then
      return new;
    end if;
  end if;
  raise exception '% is append-only: rows cannot be modified', tg_table_name;
end;
$$;

create trigger trg_audit_logs_immutable before update or delete on audit_logs
  for each row execute function prevent_ledger_tampering();
create trigger trg_inventory_transactions_immutable before update or delete on inventory_transactions
  for each row execute function prevent_ledger_tampering();

-- 3. Integrity checks. Each check returns the rows that FAIL.
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
  where (x.transaction_type in ('OPENING_BALANCE','RECEIPT','TRANSFER_IN','RETURN','RECOVERY','ADJUSTMENT') and x.quantity < 0)
     or (x.transaction_type in ('TRANSFER_OUT','DAMAGE','LOSS','DISPOSAL','ADJUSTMENT_DECREASE') and x.quantity > 0)
  group by s.code, e.source_code, e.name
  union all
  -- F. Stock held at a no-stock station.
  select 'NO_STOCK_STATIONS', s.code, e.source_code, e.name, 0::bigint,
         (b.available_quantity + b.in_transit_quantity + b.damaged_quantity + b.missing_quantity)::bigint,
         'Stock recorded at a no-stock turnaround station'
  from inventory_balances b
  join stations s on s.id = b.station_id and s.organization_id = auth_organization_id() and s.station_type = 'NO_STOCK_TURNAROUND'
  join equipment_types e on e.id = b.equipment_type_id
  where (b.available_quantity + b.in_transit_quantity + b.damaged_quantity + b.missing_quantity) > 0
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

create or replace function integrity_details(p_check text default null)
returns table (check_code text, station_code text, source_code text, equipment_name text, expected bigint, actual bigint, detail text)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null or auth_organization_id() is null then raise exception 'Not authenticated'; end if;
  if not auth_has_permission('manage_configuration') then raise exception 'Permission denied: manage_configuration required'; end if;
  return query select * from _integrity_failures() f where p_check is null or f.check_code = p_check
    order by f.check_code, f.station_code, f.source_code;
end;
$$;

revoke execute on function _integrity_failures() from public, anon, authenticated;
revoke execute on function integrity_summary(), integrity_details(text) from public, anon;
grant execute on function integrity_summary(), integrity_details(text) to authenticated;
