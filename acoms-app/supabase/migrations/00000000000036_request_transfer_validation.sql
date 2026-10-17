-- ============================================================================
-- ACOMS Migration 036: request_transfer validates both stations and every line
-- Before: only the source station was checked. A destination in another
-- organisation, an inactive station, a repeated item or an unknown item was not
-- refused cleanly. Same signature and result as before; function body only.
-- ============================================================================
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
  v_to_org uuid;
  v_transfer_id uuid;
  v_item jsonb;
  v_qty integer;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if not auth_has_permission('create_transfer') then
    raise exception 'Missing permission: create_transfer';
  end if;
  if not auth_has_station_access(p_from_station_id) then
    raise exception 'No station access to source station %', p_from_station_id;
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'A transfer must include at least one item';
  end if;
  if p_from_station_id = p_to_station_id then
    raise exception 'The source and destination stations must be different';
  end if;
  if coalesce(p_priority, 'NORMAL') not in ('LOW', 'NORMAL', 'HIGH', 'URGENT') then
    raise exception 'Unknown priority %', p_priority;
  end if;

  select organization_id into v_org from stations where id = p_from_station_id and is_active;
  if v_org is null then raise exception 'The source station is not active'; end if;
  select organization_id into v_to_org from stations where id = p_to_station_id and is_active;
  if v_to_org is null then raise exception 'The destination station does not exist or is not active'; end if;
  if v_to_org <> v_org or v_org <> auth_organization_id() then
    raise exception 'Both stations must belong to your organisation';
  end if;

  if (select count(*) from jsonb_array_elements(p_items)) <>
     (select count(distinct e->>'equipment_type_id') from jsonb_array_elements(p_items) e) then
    raise exception 'Each equipment type can only be listed once';
  end if;
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    begin
      v_qty := (v_item->>'quantity')::integer;
    exception when others then
      raise exception 'Each quantity must be a whole number';
    end;
    if v_qty is null or v_qty <= 0 then raise exception 'Each quantity must be greater than zero'; end if;
    if not exists (select 1 from equipment_types where id = nullif(v_item->>'equipment_type_id', '')::uuid and organization_id = v_org) then
      raise exception 'Unknown equipment type in the item list';
    end if;
  end loop;

  insert into equipment_transfers (organization_id, from_station_id, to_station_id, requested_by, reason, priority)
  values (v_org, p_from_station_id, p_to_station_id, auth.uid(), p_reason, coalesce(p_priority, 'NORMAL'))
  returning id into v_transfer_id;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    insert into equipment_transfer_items (transfer_id, equipment_type_id, quantity_requested)
    values (v_transfer_id, (v_item->>'equipment_type_id')::uuid, (v_item->>'quantity')::integer);
  end loop;

  perform write_audit_log(v_org, 'transfer.request', 'equipment_transfer', v_transfer_id,
    p_from_station_id, null, jsonb_build_object('items', p_items), p_reason);

  return v_transfer_id;
end;
$$;

revoke execute on function request_transfer(uuid, uuid, jsonb, text, text) from public, anon;
grant execute on function request_transfer(uuid, uuid, jsonb, text, text) to authenticated;
