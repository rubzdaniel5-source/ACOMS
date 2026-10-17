-- ============================================================================
-- Migration 038: dispatch that leaves the source below its minimum level
-- needs a catering supervisor's or catering manager's approval, with a reason.
--
-- Minimum level = the station's own level when set, otherwise the equipment's
-- default (same figure the stock-health view uses). A level of 0 or none means
-- "no minimum", so nothing is checked. Stock cannot go negative regardless.
-- ============================================================================

alter table equipment_transfers
  add column if not exists below_min_approved_by uuid references user_profiles(id),
  add column if not exists below_min_approved_at timestamptz,
  add column if not exists below_min_reason text;

-- Lines that would leave the source under its minimum if dispatched as given.
create or replace function dispatch_below_minimum(p_transfer_id uuid, p_items jsonb)
returns table(item_id uuid, equipment_name text, available integer, dispatching integer, minimum_level integer)
language sql stable security definer set search_path = public as $$
  select i.id, et.name, coalesce(ib.available_quantity, 0)::int, q.qty,
         coalesce(ssl.reorder_threshold, et.reorder_threshold)::int
  from equipment_transfers t
  cross join lateral jsonb_array_elements(p_items) e
  cross join lateral (select case when (e->>'quantity_dispatched') ~ '^[0-9]+$' then (e->>'quantity_dispatched')::int end as qty) q
  join equipment_transfer_items i
    on i.transfer_id = t.id and (e->>'item_id') ~* '^[0-9a-f-]{36}$' and i.id = (e->>'item_id')::uuid
  join equipment_types et on et.id = i.equipment_type_id
  left join inventory_balances ib on ib.station_id = t.from_station_id and ib.equipment_type_id = i.equipment_type_id
  left join station_stock_levels ssl on ssl.station_id = t.from_station_id and ssl.equipment_type_id = i.equipment_type_id
  where t.id = p_transfer_id
    and auth_has_station_access(t.from_station_id)
    and q.qty > 0
    and coalesce(ssl.reorder_threshold, et.reorder_threshold, 0) > 0
    and coalesce(ib.available_quantity, 0) - q.qty < coalesce(ssl.reorder_threshold, et.reorder_threshold);
$$;

-- Supervisor / manager sign-off, recorded with the reason.
create or replace function approve_below_minimum_dispatch(p_transfer_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_t equipment_transfers%rowtype;
begin
  select * into v_t from equipment_transfers where id = p_transfer_id for update;
  if not found then raise exception 'Transfer not found'; end if;
  if not exists (
    select 1 from user_profiles up join user_roles ur on ur.user_id = up.id
    join roles r on r.id = ur.role_id and r.is_active
    where up.id = auth.uid() and up.is_active and r.code in ('catering_supervisor', 'catering_manager')
      and (ur.station_id is null or ur.station_id = v_t.from_station_id)
  ) then raise exception 'Only a catering supervisor or catering manager can approve a dispatch below the minimum level'; end if;
  if v_t.status <> 'APPROVED' then raise exception 'Transfer must be APPROVED (current status: %)', v_t.status; end if;
  if p_reason is null or length(btrim(p_reason)) < 10 then
    raise exception 'Give a clear reason (at least 10 characters) for dispatching below the minimum level';
  end if;
  if not exists (select 1 from dispatch_below_minimum(p_transfer_id, (
      select jsonb_agg(jsonb_build_object('item_id', id, 'quantity_dispatched', coalesce(quantity_approved, quantity_requested)::text))
      from equipment_transfer_items where transfer_id = p_transfer_id))) then
    raise exception 'This dispatch does not go below any minimum level, so no approval is needed';
  end if;
  update equipment_transfers set below_min_approved_by = auth.uid(), below_min_approved_at = now(), below_min_reason = btrim(p_reason)
  where id = p_transfer_id;
  perform write_audit_log(v_t.organization_id, 'transfer.below_min_approve', 'equipment_transfer', p_transfer_id,
    v_t.from_station_id, null, jsonb_build_object('approved_by', auth.uid()), btrim(p_reason));
end $$;

-- dispatch_transfer: refuse until approved. Patched in place so earlier fixes stay.
do $outer$
declare v_def text; v_new text;
        v_add constant text := $add$
  if exists (select 1 from dispatch_below_minimum(p_transfer_id, p_dispatched_items))
     and not exists (select 1 from equipment_transfers where id = p_transfer_id and below_min_approved_by is not null) then
    raise exception 'This dispatch leaves stock below the minimum level. A catering supervisor or catering manager must approve it, with a reason, before it can be dispatched.';
  end if;$add$;
begin
  v_def := pg_get_functiondef('dispatch_transfer(uuid, jsonb)'::regprocedure);
  v_new := regexp_replace(v_def, '(No station access to source station.;\s*end if;)', '\1' || replace(v_add, '\', '\\'));
  if v_new = v_def then raise exception 'Could not patch dispatch_transfer'; end if;
  execute v_new;
end $outer$;

revoke execute on function dispatch_below_minimum(uuid, jsonb), approve_below_minimum_dispatch(uuid, text) from public, anon;
grant execute on function dispatch_below_minimum(uuid, jsonb), approve_below_minimum_dispatch(uuid, text) to authenticated;
