-- ============================================================================
-- ACOMS Migration 037: continuous flight schedule, upcoming flights, unverified flights
-- 1. Flight numbers continue across seasons: every route is valid from the start (no season start or end).
-- 2. upcoming_flights(): the next flights between two stations as one list (date + flight), so one pick sets both.
-- 3. Base staff can enter a flight that is not in the schedule. It is saved as UNVERIFIED and a station
--    manager confirms it (or cancels it). It never blocks a movement.
-- ============================================================================

-- ---- 1. Continuous schedule --------------------------------------------------------------------
update flight_routes set valid_from = date '2000-01-01', valid_to = null where valid_from > date '2000-01-01' or valid_to is not null;

-- ---- 2. Upcoming flights -------------------------------------------------------------------------
create or replace function upcoming_flights(p_from uuid, p_to uuid, p_days integer default 14)
returns table (flight_date date, flight_number text)
language sql stable security definer set search_path = public as $$
  select d::date, f.flight_number
    from generate_series((now() at time zone 'Africa/Kampala')::date,
                         (now() at time zone 'Africa/Kampala')::date + least(greatest(coalesce(p_days, 14), 1), 60), interval '1 day') d
    cross join (select distinct r.flight_number from flight_routes r
                 where r.organization_id = auth_organization_id() and r.is_active) f
   where auth_has_permission('view_inventory')
     and _flight_chain(auth_organization_id(), f.flight_number, d::date, p_from, p_to) is not null
     and not exists (select 1 from flight_legs l
                      where l.organization_id = auth_organization_id() and l.flight_number = f.flight_number
                        and l.operating_date = d::date and l.status = 'CANCELLED'
                        and l.origin_station_id = p_from and l.destination_station_id = p_to)
   order by 1, 2
$$;
revoke execute on function upcoming_flights(uuid, uuid, integer) from public, anon;
grant execute on function upcoming_flights(uuid, uuid, integer) to authenticated;

-- ---- 3. Unverified flights ---------------------------------------------------------------------------
alter table flight_legs
  add column if not exists is_unverified boolean not null default false,
  add column if not exists verified_by uuid references user_profiles(id) on delete restrict,
  add column if not exists verified_at timestamptz;

-- The immutability trigger only guards flight identity, so confirming (a status flag) is allowed.
create or replace view v_flight_legs with (security_invoker = true) as
select l.id, l.flight_number, l.operating_date, l.status, l.is_one_off, l.one_off_reason, l.cancel_reason, l.cancelled_at,
       o.code as origin_code, o.name as origin_name, d.code as destination_code, d.name as destination_name,
       l.origin_station_id, l.destination_station_id, l.route_id, l.created_at, l.is_unverified, l.created_by
from flight_legs l join stations o on o.id = l.origin_station_id join stations d on d.id = l.destination_station_id;

create or replace function create_unverified_flight_leg(p_flight_number text, p_date date, p_origin_station_id uuid, p_destination_station_id uuid, p_note text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_org uuid := auth_organization_id(); v_id uuid; v_fn text := normalize_flight_number(p_flight_number);
begin
  if auth.uid() is null or v_org is null then raise exception 'Not authenticated'; end if;
  if not (auth_has_permission('create_transfer') or auth_has_permission('manage_flights')) then
    raise exception 'Permission denied: create_transfer required'; end if;
  if not (auth_has_station_access(p_origin_station_id) or auth_has_station_access(p_destination_station_id)) then
    raise exception 'You have no access to either station on this flight'; end if;
  if v_fn is null or v_fn = '' then raise exception 'Enter the flight number'; end if;
  if p_date is null then raise exception 'Enter the flight date'; end if;
  if p_date < (now() at time zone 'Africa/Kampala')::date - 1 then raise exception 'The flight date cannot be in the past'; end if;
  if p_origin_station_id = p_destination_station_id then raise exception 'Origin and destination must differ'; end if;
  if length(trim(coalesce(p_note, ''))) < 3 then raise exception 'Say why this flight is not in the schedule'; end if;
  if not exists (select 1 from stations where id = p_origin_station_id and organization_id = v_org and is_active)
     or not exists (select 1 from stations where id = p_destination_station_id and organization_id = v_org and is_active) then
    raise exception 'Unknown or inactive station'; end if;

  -- A scheduled flight or an existing leg for this exact sector is simply reused.
  select id into v_id from flight_legs where organization_id = v_org and flight_number = v_fn and operating_date = p_date
     and origin_station_id = p_origin_station_id and destination_station_id = p_destination_station_id;
  if found then return v_id; end if;
  if _flight_chain(v_org, v_fn, p_date, p_origin_station_id, p_destination_station_id) is not null then
    return ensure_flight_leg(v_fn, p_date, p_origin_station_id, p_destination_station_id);
  end if;

  insert into flight_legs (organization_id, flight_number, operating_date, origin_station_id, destination_station_id,
                           is_one_off, one_off_reason, is_unverified, created_by)
  values (v_org, v_fn, p_date, p_origin_station_id, p_destination_station_id, true, 'Entered by base staff: ' || trim(p_note), true, auth.uid())
  returning id into v_id;
  perform write_audit_log(v_org, 'flight.leg_unverified', 'flight_leg', v_id, p_origin_station_id, null,
    jsonb_build_object('flight', v_fn, 'date', p_date), trim(p_note));
  return v_id;
end $$;

create or replace function confirm_flight_leg(p_leg_id uuid, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid := auth_organization_id(); v_l flight_legs%rowtype;
begin
  if auth.uid() is null or v_org is null then raise exception 'Not authenticated'; end if;
  if not auth_has_permission('manage_flights') then raise exception 'Permission denied: manage_flights required'; end if;
  select * into v_l from flight_legs where id = p_leg_id and organization_id = v_org for update;
  if not found then raise exception 'Flight not found'; end if;
  if not v_l.is_unverified then raise exception 'This flight is already confirmed'; end if;
  update flight_legs set is_unverified = false, verified_by = auth.uid(), verified_at = now() where id = p_leg_id;
  perform write_audit_log(v_org, 'flight.leg_confirm', 'flight_leg', p_leg_id, v_l.origin_station_id,
    jsonb_build_object('is_unverified', true), jsonb_build_object('is_unverified', false), p_note);
end $$;

revoke execute on function create_unverified_flight_leg(text, date, uuid, uuid, text), confirm_flight_leg(uuid, text) from public, anon;
grant execute on function create_unverified_flight_leg(text, date, uuid, uuid, text), confirm_flight_leg(uuid, text) to authenticated;
