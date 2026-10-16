-- ============================================================================
-- ACOMS Migration 032: UR flight prefix and through-flights
--
-- 1. Every flight number carries the airline prefix: UR110, UR200 ... Existing
--    entries are renamed, and anything typed without the prefix ("200") is
--    stored as UR200. Other letter prefixes are left alone.
-- 2. A movement can ride a flight that continues through other stations. The
--    transfer's origin and destination must both lie on the flight's chain of
--    sectors, in order (for example EBB to LUN on UR722, which flies EBB-HRE-LUN;
--    HRE holds no stock, which is fine because nothing is unloaded there).
--    Every sector of that chain is linked; cancelling any sector blocks dispatch.
-- The schedule is continuous: routes have no end date unless one is entered.
-- ============================================================================

create or replace function normalize_flight_number(p_value text) returns text
language sql immutable as $$
  select case
    when upper(regexp_replace(coalesce(p_value, ''), '\s+', '', 'g')) ~ '^[0-9]+[A-Z]?$'
      then 'UR' || upper(regexp_replace(p_value, '\s+', '', 'g'))
    else upper(regexp_replace(coalesce(p_value, ''), '\s+', '', 'g'))
  end $$;

-- ---- Rename existing data ---------------------------------------------------------
alter table flight_legs disable trigger trg_flight_legs_identity;
update flight_routes set flight_number = normalize_flight_number(flight_number) where flight_number <> normalize_flight_number(flight_number);
update flight_legs set flight_number = normalize_flight_number(flight_number) where flight_number <> normalize_flight_number(flight_number);
alter table flight_legs enable trigger trg_flight_legs_identity;
update equipment_transfers set flight_number = normalize_flight_number(flight_number)
 where flight_number is not null and flight_number <> normalize_flight_number(flight_number);

alter table equipment_transfers add column if not exists flight_leg_ids uuid[];

-- ---- Route / leg creation use the normalised number --------------------------------
do $$
declare v_def text;
begin
  v_def := pg_get_functiondef('create_flight_route(text, text, text, integer[], date, date, text)'::regprocedure);
  v_def := replace(v_def, 'upper(trim(p_flight_number))', 'normalize_flight_number(p_flight_number)');
  execute v_def;
  v_def := pg_get_functiondef('create_one_off_flight_leg(text, date, uuid, uuid, text)'::regprocedure);
  v_def := replace(v_def, 'upper(trim(p_flight_number))', 'normalize_flight_number(p_flight_number)');
  execute v_def;
end $$;

-- ---- ensure_flight_leg: finds the chain of sectors and creates every sector's leg ----
create or replace function _flight_chain(p_org uuid, p_flight text, p_date date, p_from uuid, p_to uuid)
returns uuid[] language sql stable security definer set search_path = public as $$
  with recursive sectors as (
    select r.id, r.origin_station_id o, r.destination_station_id d from flight_routes r
     where r.organization_id = p_org and r.flight_number = p_flight and r.is_active
       and p_date >= r.valid_from and (r.valid_to is null or p_date <= r.valid_to)
       and extract(isodow from p_date)::smallint = any(r.operating_days)
  ), walk as (
    select array[s.id] ids, array[s.o, s.d] stops, s.d last from sectors s where s.o = p_from
    union all
    select w.ids || s.id, w.stops || s.d, s.d from walk w join sectors s on s.o = w.last
     where not (s.d = any(w.stops)) and cardinality(w.ids) < 6
  )
  select ids from walk where last = p_to order by cardinality(ids) limit 1
$$;
revoke execute on function _flight_chain(uuid, text, date, uuid, uuid) from public, anon, authenticated;

create or replace function ensure_flight_leg(p_flight_number text, p_date date, p_origin_station_id uuid, p_destination_station_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_org uuid := auth_organization_id(); v_fn text := normalize_flight_number(p_flight_number);
  v_chain uuid[]; v_route flight_routes%rowtype; v_rid uuid; v_first uuid; v_id uuid;
begin
  if auth.uid() is null or v_org is null then raise exception 'Not authenticated'; end if;
  if not (auth_has_permission('create_transfer') or auth_has_permission('manage_flights')) then
    raise exception 'Permission denied: create_transfer or manage_flights required'; end if;
  if not (auth_has_station_access(p_origin_station_id) or auth_has_station_access(p_destination_station_id)) then
    raise exception 'You have no access to either station on this flight'; end if;

  v_chain := _flight_chain(v_org, v_fn, p_date, p_origin_station_id, p_destination_station_id);
  if v_chain is null then
    -- A one-off leg that already covers exactly this sector is acceptable.
    select id into v_id from flight_legs where organization_id = v_org and flight_number = v_fn and operating_date = p_date
      and origin_station_id = p_origin_station_id and destination_station_id = p_destination_station_id;
    if found then return v_id; end if;
    raise exception 'No scheduled flight % on % for that route. Check the flight number, date and stations, or ask a station manager to add a one-off flight.', v_fn, p_date;
  end if;

  foreach v_rid in array v_chain loop
    select * into v_route from flight_routes where id = v_rid;
    select id into v_id from flight_legs where organization_id = v_org and flight_number = v_fn and operating_date = p_date
      and origin_station_id = v_route.origin_station_id and destination_station_id = v_route.destination_station_id;
    if not found then
      insert into flight_legs (organization_id, route_id, flight_number, operating_date, origin_station_id, destination_station_id, created_by)
      values (v_org, v_route.id, v_fn, p_date, v_route.origin_station_id, v_route.destination_station_id, auth.uid())
      on conflict do nothing returning id into v_id;
      if v_id is null then
        select id into v_id from flight_legs where organization_id = v_org and flight_number = v_fn and operating_date = p_date
          and origin_station_id = v_route.origin_station_id and destination_station_id = v_route.destination_station_id;
      end if;
    end if;
    if v_first is null then v_first := v_id; end if;
  end loop;
  return v_first;
end $$;

-- ---- set_transfer_flight: the transfer's stations must lie on the flight's chain ------
create or replace function set_transfer_flight(p_transfer_id uuid, p_flight_leg_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_org uuid := auth_organization_id(); v_t equipment_transfers%rowtype; v_l flight_legs%rowtype;
  v_oc text; v_dc text; v_ids uuid[];
begin
  if auth.uid() is null or v_org is null then raise exception 'Not authenticated'; end if;
  select * into v_t from equipment_transfers where id = p_transfer_id and organization_id = v_org for update;
  if not found then raise exception 'Transfer not found'; end if;
  if v_t.status not in ('REQUESTED', 'APPROVED') then
    raise exception 'The flight can only be set while the transfer is requested or approved (current status: %)', v_t.status; end if;
  if not (v_t.requested_by = auth.uid() or (auth_has_permission('create_transfer') and auth_has_station_access(v_t.from_station_id))) then
    raise exception 'Only the requester, or staff at the sending station, can set the flight'; end if;
  select * into v_l from flight_legs where id = p_flight_leg_id and organization_id = v_org;
  if not found then raise exception 'Flight leg not found'; end if;
  if v_l.operating_date < current_date - 1 then raise exception 'The flight date has already passed'; end if;

  -- Chain of dated sectors of this flight from the transfer's origin to its destination.
  with recursive walk as (
    select array[l.id] ids, array[l.origin_station_id, l.destination_station_id] stops, l.destination_station_id last
      from flight_legs l
     where l.organization_id = v_org and l.flight_number = v_l.flight_number and l.operating_date = v_l.operating_date
       and l.origin_station_id = v_t.from_station_id
    union all
    select w.ids || l.id, w.stops || l.destination_station_id, l.destination_station_id
      from walk w join flight_legs l on l.origin_station_id = w.last
     where l.organization_id = v_org and l.flight_number = v_l.flight_number and l.operating_date = v_l.operating_date
       and not (l.destination_station_id = any(w.stops)) and cardinality(w.ids) < 6
  )
  select ids into v_ids from walk where last = v_t.to_station_id order by cardinality(ids) limit 1;
  if v_ids is null then
    raise exception 'The flight''s route does not match the transfer''s sending and receiving stations'; end if;
  if not (p_flight_leg_id = any(v_ids)) then
    raise exception 'The flight''s route does not match the transfer''s sending and receiving stations'; end if;
  if exists (select 1 from flight_legs where id = any(v_ids) and status = 'CANCELLED') then
    raise exception 'This flight is cancelled on part of the route and cannot be used'; end if;

  select code into v_oc from stations where id = v_t.from_station_id;
  select code into v_dc from stations where id = v_t.to_station_id;
  update equipment_transfers set flight_leg_id = v_ids[1], flight_leg_ids = v_ids, flight_number = v_l.flight_number,
         flight_date = v_l.operating_date, flight_origin_code = v_oc, flight_destination_code = v_dc where id = p_transfer_id;
  perform write_audit_log(v_org, 'transfer.set_flight', 'equipment_transfer', p_transfer_id, v_t.from_station_id,
    jsonb_build_object('flight', v_t.flight_number, 'date', v_t.flight_date),
    jsonb_build_object('flight', v_l.flight_number, 'date', v_l.operating_date, 'sectors', cardinality(v_ids)), null);
end $$;

-- ---- Dispatch: any cancelled sector on the chain blocks it ------------------------------
do $$
declare v_def text;
begin
  v_def := pg_get_functiondef('dispatch_transfer(uuid, jsonb)'::regprocedure);
  v_def := replace(v_def,
    'v_transfer.flight_leg_id is not null and exists (select 1 from flight_legs where id = v_transfer.flight_leg_id and status = ''CANCELLED'')',
    'exists (select 1 from flight_legs where id = any(coalesce(v_transfer.flight_leg_ids, array[v_transfer.flight_leg_id])) and status = ''CANCELLED'')');
  if v_def not like '%flight_leg_ids%' then raise exception 'Failed to patch dispatch_transfer'; end if;
  execute v_def;
end $$;

revoke execute on function ensure_flight_leg(text, date, uuid, uuid), set_transfer_flight(uuid, uuid), normalize_flight_number(text) from public, anon;
grant execute on function ensure_flight_leg(text, date, uuid, uuid), set_transfer_flight(uuid, uuid), normalize_flight_number(text) to authenticated;

-- Flights a screen can offer for a route and date (through-flights included).
create or replace function available_flights(p_from uuid, p_to uuid, p_date date)
returns table (flight_number text) language sql stable security definer set search_path = public as $$
  select distinct r.flight_number from flight_routes r
   where r.organization_id = auth_organization_id() and auth_has_permission('view_inventory') and r.is_active
     and _flight_chain(r.organization_id, r.flight_number, p_date, p_from, p_to) is not null
   order by 1
$$;
revoke execute on function available_flights(uuid, uuid, date) from public, anon;
grant execute on function available_flights(uuid, uuid, date) to authenticated;
