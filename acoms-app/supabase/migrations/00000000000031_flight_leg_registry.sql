-- ============================================================================
-- ACOMS Migration 031: flight-leg registry (Equipment Exchange MVP, step 2)
--
-- Two levels, so history stays exact:
--   flight_routes : the recurring schedule (flight number, origin, destination,
--                   operating weekdays, season). Seeded from the Winter 2026
--                   schedule effective 25 Oct 2026 (main "WINTER SCH" sheet).
--   flight_legs   : one dated flight on one sector. Created on demand when a
--                   movement needs it (checked against the schedule) or added
--                   by an authorised user as a one-off. Identity fields can
--                   never change afterwards; a leg can only be cancelled.
-- Transfers keep a frozen copy of the flight details they used.
-- A transfer's flight, when set, must match its origin and destination, must
-- not be cancelled, and a cancelled leg blocks dispatch.
-- ============================================================================

insert into permissions (code, description) values
  ('manage_flights', 'Maintain the flight schedule and flight legs, and cancel flight legs')
on conflict (code) do nothing;
insert into role_permissions (role_id, permission_id)
select r.id, p.id from roles r, permissions p
where r.organization_id = (select id from organizations where code = 'UGANDA_AIRLINES')
  and p.code = 'manage_flights' and r.code in ('system_admin', 'station_manager')
on conflict do nothing;

create table flight_routes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete restrict,
  flight_number text not null check (length(trim(flight_number)) > 0),
  origin_station_id uuid not null references stations(id) on delete restrict,
  destination_station_id uuid not null references stations(id) on delete restrict,
  operating_days smallint[] not null check (
    cardinality(operating_days) between 1 and 7 and operating_days <@ array[1,2,3,4,5,6,7]::smallint[]),
  valid_from date not null,
  valid_to date,
  is_active boolean not null default true,
  source text,
  notes text,
  created_by uuid references user_profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint chk_route_stations_differ check (origin_station_id <> destination_station_id),
  constraint chk_route_dates check (valid_to is null or valid_to >= valid_from),
  unique (organization_id, flight_number, origin_station_id, destination_station_id, valid_from)
);

create table flight_legs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete restrict,
  route_id uuid references flight_routes(id) on delete restrict,
  flight_number text not null,
  operating_date date not null,
  origin_station_id uuid not null references stations(id) on delete restrict,
  destination_station_id uuid not null references stations(id) on delete restrict,
  status text not null default 'SCHEDULED' check (status in ('SCHEDULED', 'CANCELLED')),
  is_one_off boolean not null default false,
  one_off_reason text,
  cancelled_by uuid references user_profiles(id) on delete restrict,
  cancelled_at timestamptz,
  cancel_reason text,
  created_by uuid references user_profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint chk_leg_stations_differ check (origin_station_id <> destination_station_id),
  constraint chk_one_off_reason check (not is_one_off or length(trim(coalesce(one_off_reason, ''))) > 0),
  unique (organization_id, flight_number, operating_date, origin_station_id, destination_station_id)
);
create index idx_flight_legs_date on flight_legs (operating_date);

create or replace function prevent_flight_leg_identity_change() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then raise exception 'Flight legs cannot be deleted; cancel them instead'; end if;
  if new.flight_number <> old.flight_number or new.operating_date <> old.operating_date
     or new.origin_station_id <> old.origin_station_id or new.destination_station_id <> old.destination_station_id
     or new.organization_id <> old.organization_id then
    raise exception 'A flight leg''s flight, date and route cannot be changed; cancel it and create the correct one';
  end if;
  return new;
end $$;
create trigger trg_flight_legs_identity before update or delete on flight_legs
  for each row execute function prevent_flight_leg_identity_change();

alter table flight_routes enable row level security;
alter table flight_legs enable row level security;
create policy "flight_routes_select" on flight_routes for select
  using (organization_id = auth_organization_id() and auth_has_permission('view_inventory'));
create policy "flight_legs_select" on flight_legs for select
  using (organization_id = auth_organization_id() and auth_has_permission('view_inventory'));
-- No write policies: all changes go through the functions below.

create or replace view v_flight_legs with (security_invoker = true) as
select l.id, l.flight_number, l.operating_date, l.status, l.is_one_off, l.one_off_reason, l.cancel_reason, l.cancelled_at,
       o.code as origin_code, o.name as origin_name, d.code as destination_code, d.name as destination_name,
       l.origin_station_id, l.destination_station_id, l.route_id, l.created_at
from flight_legs l join stations o on o.id = l.origin_station_id join stations d on d.id = l.destination_station_id;

create or replace view v_flight_routes with (security_invoker = true) as
select r.id, r.flight_number, r.operating_days, r.valid_from, r.valid_to, r.is_active, r.source, r.notes,
       o.code as origin_code, o.name as origin_name, d.code as destination_code, d.name as destination_name,
       r.origin_station_id, r.destination_station_id
from flight_routes r join stations o on o.id = r.origin_station_id join stations d on d.id = r.destination_station_id;

-- ---- Seed: Winter 2026 schedule (effective 25 Oct 2026) -----------------------
insert into flight_routes (organization_id, flight_number, origin_station_id, destination_station_id, operating_days, valid_from, source)
select o.id, s.flt, so.id, sd.id, s.days::smallint[], date '2026-10-25', 'WINTER 2026 schedule, sheet WINTER SCH'
from organizations o
cross join (values
  ('110', 'EBB', 'LGW', array[2, 5, 7]),
  ('111', 'LGW', 'EBB', array[2, 5, 7]),
  ('120', 'EBB', 'JUB', array[2, 4, 5, 6, 7]),
  ('121', 'JUB', 'EBB', array[2, 4, 5, 6, 7]),
  ('122', 'EBB', 'JUB', array[1, 3]),
  ('123', 'JUB', 'EBB', array[1, 3]),
  ('200', 'EBB', 'NBO', array[1, 2, 3, 4, 5, 6, 7]),
  ('201', 'NBO', 'EBB', array[1, 2, 3, 4, 5, 6, 7]),
  ('205', 'NBO', 'EBB', array[5, 6]),
  ('206', 'EBB', 'NBO', array[2, 6, 7]),
  ('207', 'NBO', 'EBB', array[2, 6, 7]),
  ('208', 'EBB', 'NBO', array[1, 2, 3, 4, 5, 6]),
  ('209', 'NBO', 'EBB', array[1, 2, 3, 4, 5, 6]),
  ('320', 'EBB', 'DAR', array[1, 2]),
  ('321', 'DAR', 'EBB', array[1, 2]),
  ('322', 'EBB', 'DAR', array[1, 3, 4, 5, 6, 7]),
  ('323', 'DAR', 'EBB', array[1, 2, 4, 5, 6, 7]),
  ('334', 'EBB', 'ZNZ', array[3, 5, 7]),
  ('334', 'JRO', 'EBB', array[3, 5, 7]),
  ('334', 'ZNZ', 'JRO', array[3, 5, 7]),
  ('342', 'EBB', 'MBA', array[3, 5, 7]),
  ('343', 'MBA', 'EBB', array[3, 5, 7]),
  ('360', 'EBB', 'BJM', array[1, 2, 3, 4, 5, 7]),
  ('361', 'BJM', 'EBB', array[1, 2, 3, 4, 5, 7]),
  ('380', 'EBB', 'KGL', array[2, 3, 5, 7]),
  ('381', 'KGL', 'EBB', array[2, 3, 5, 7]),
  ('382', 'EBB', 'KGL', array[1, 4, 6]),
  ('383', 'KGL', 'EBB', array[1, 4, 6]),
  ('430', 'EBB', 'BOM', array[3, 6]),
  ('431', 'BOM', 'EBB', array[3, 6]),
  ('520', 'EBB', 'MGQ', array[2, 4, 6, 7]),
  ('521', 'MGQ', 'EBB', array[2, 4, 6, 7]),
  ('710', 'EBB', 'JNB', array[1, 3, 5, 6]),
  ('711', 'JNB', 'EBB', array[1, 3, 5, 6]),
  ('712', 'EBB', 'JNB', array[1, 2, 4, 7]),
  ('713', 'JNB', 'EBB', array[1, 2, 3, 5]),
  ('720', 'EBB', 'LUN', array[5, 7]),
  ('720', 'HRE', 'EBB', array[1, 6]),
  ('720', 'LUN', 'HRE', array[5, 7]),
  ('722', 'EBB', 'HRE', array[2, 3, 4]),
  ('722', 'HRE', 'LUN', array[2, 3, 4]),
  ('722', 'LUN', 'EBB', array[2, 3, 4]),
  ('724', 'EBB', 'HRE', array[1, 6]),
  ('724', 'HRE', 'LUN', array[1, 6]),
  ('725', 'HRE', 'EBB', array[2, 7]),
  ('725', 'LUN', 'HRE', array[2, 7]),
  ('882', 'EBB', 'FIH', array[1, 4, 6]),
  ('883', 'FIH', 'EBB', array[1, 4, 6]),
  ('884', 'EBB', 'FIH', array[3, 7]),
  ('885', 'FIH', 'EBB', array[3, 7]),
  ('900', 'EBB', 'LOS', array[2, 4, 5, 7]),
  ('900', 'LOS', 'ACC', array[2, 4, 5, 7]),
  ('901', 'ACC', 'LOS', array[2, 4, 5, 7]),
  ('901', 'LOS', 'EBB', array[2, 4, 5, 7])
) as s(flt, org, dst, days)
join stations so on so.organization_id = o.id and so.code = s.org
join stations sd on sd.organization_id = o.id and sd.code = s.dst
where o.code = 'UGANDA_AIRLINES';

-- ---- Functions --------------------------------------------------------------
create or replace function create_flight_route(
  p_flight_number text, p_origin_code text, p_destination_code text, p_days integer[],
  p_valid_from date, p_valid_to date default null, p_notes text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_org uuid := auth_organization_id(); v_o uuid; v_d uuid; v_id uuid;
begin
  if auth.uid() is null or v_org is null then raise exception 'Not authenticated'; end if;
  if not auth_has_permission('manage_flights') then raise exception 'Permission denied: manage_flights required'; end if;
  select id into v_o from stations where organization_id = v_org and code = upper(trim(p_origin_code)) and is_active;
  select id into v_d from stations where organization_id = v_org and code = upper(trim(p_destination_code)) and is_active;
  if v_o is null or v_d is null then raise exception 'Unknown or inactive origin or destination station'; end if;
  if v_o = v_d then raise exception 'Origin and destination must differ'; end if;
  if p_days is null or cardinality(p_days) = 0 or not (p_days <@ array[1,2,3,4,5,6,7]) then
    raise exception 'Operating days must be numbers from 1 (Monday) to 7 (Sunday)'; end if;
  insert into flight_routes (organization_id, flight_number, origin_station_id, destination_station_id, operating_days,
                             valid_from, valid_to, source, notes, created_by)
  values (v_org, upper(trim(p_flight_number)), v_o, v_d, p_days::smallint[], p_valid_from, p_valid_to, 'MANUAL', p_notes, auth.uid())
  returning id into v_id;
  perform write_audit_log(v_org, 'flight.route_create', 'flight_route', v_id, v_o, null,
    jsonb_build_object('flight', upper(trim(p_flight_number)), 'from', p_origin_code, 'to', p_destination_code, 'days', p_days), p_notes);
  return v_id;
end $$;

create or replace function set_flight_route_active(p_route_id uuid, p_active boolean, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid := auth_organization_id(); v_r flight_routes%rowtype;
begin
  if auth.uid() is null or v_org is null then raise exception 'Not authenticated'; end if;
  if not auth_has_permission('manage_flights') then raise exception 'Permission denied: manage_flights required'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'A reason is required'; end if;
  select * into v_r from flight_routes where id = p_route_id and organization_id = v_org for update;
  if not found then raise exception 'Flight route not found'; end if;
  update flight_routes set is_active = p_active where id = p_route_id;
  perform write_audit_log(v_org, case when p_active then 'flight.route_activate' else 'flight.route_deactivate' end,
    'flight_route', p_route_id, v_r.origin_station_id, jsonb_build_object('is_active', v_r.is_active),
    jsonb_build_object('is_active', p_active), trim(p_reason));
end $$;

-- Find or create the dated leg for a scheduled flight. Never invents a flight:
-- the date must fall on an operating day inside the season of an active route.
create or replace function ensure_flight_leg(p_flight_number text, p_date date, p_origin_station_id uuid, p_destination_station_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_org uuid := auth_organization_id(); v_route flight_routes%rowtype; v_id uuid; v_fn text := upper(trim(p_flight_number));
begin
  if auth.uid() is null or v_org is null then raise exception 'Not authenticated'; end if;
  if not (auth_has_permission('create_transfer') or auth_has_permission('manage_flights')) then
    raise exception 'Permission denied: create_transfer or manage_flights required'; end if;
  if not (auth_has_station_access(p_origin_station_id) or auth_has_station_access(p_destination_station_id)) then
    raise exception 'You have no access to either station on this flight'; end if;
  select id into v_id from flight_legs
   where organization_id = v_org and flight_number = v_fn and operating_date = p_date
     and origin_station_id = p_origin_station_id and destination_station_id = p_destination_station_id;
  if found then return v_id; end if;
  select * into v_route from flight_routes
   where organization_id = v_org and flight_number = v_fn and is_active
     and origin_station_id = p_origin_station_id and destination_station_id = p_destination_station_id
     and p_date >= valid_from and (valid_to is null or p_date <= valid_to)
     and extract(isodow from p_date)::smallint = any(operating_days)
   order by valid_from desc limit 1;
  if not found then
    raise exception 'No scheduled flight % on % for that route. Check the flight number, date and stations, or ask a station manager to add a one-off flight.', v_fn, p_date;
  end if;
  insert into flight_legs (organization_id, route_id, flight_number, operating_date, origin_station_id, destination_station_id, created_by)
  values (v_org, v_route.id, v_fn, p_date, p_origin_station_id, p_destination_station_id, auth.uid())
  on conflict do nothing returning id into v_id;
  if v_id is null then
    select id into v_id from flight_legs where organization_id = v_org and flight_number = v_fn and operating_date = p_date
      and origin_station_id = p_origin_station_id and destination_station_id = p_destination_station_id;
  end if;
  return v_id;
end $$;

create or replace function create_one_off_flight_leg(p_flight_number text, p_date date, p_origin_station_id uuid, p_destination_station_id uuid, p_reason text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_org uuid := auth_organization_id(); v_id uuid; v_fn text := upper(trim(p_flight_number));
begin
  if auth.uid() is null or v_org is null then raise exception 'Not authenticated'; end if;
  if not auth_has_permission('manage_flights') then raise exception 'Permission denied: manage_flights required'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'A reason is required for a one-off flight'; end if;
  if p_origin_station_id = p_destination_station_id then raise exception 'Origin and destination must differ'; end if;
  if not exists (select 1 from stations where id = p_origin_station_id and organization_id = v_org and is_active)
     or not exists (select 1 from stations where id = p_destination_station_id and organization_id = v_org and is_active) then
    raise exception 'Unknown or inactive station'; end if;
  insert into flight_legs (organization_id, flight_number, operating_date, origin_station_id, destination_station_id, is_one_off, one_off_reason, created_by)
  values (v_org, v_fn, p_date, p_origin_station_id, p_destination_station_id, true, trim(p_reason), auth.uid())
  returning id into v_id;
  perform write_audit_log(v_org, 'flight.leg_one_off', 'flight_leg', v_id, p_origin_station_id, null,
    jsonb_build_object('flight', v_fn, 'date', p_date), trim(p_reason));
  return v_id;
end $$;

create or replace function cancel_flight_leg(p_leg_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid := auth_organization_id(); v_l flight_legs%rowtype;
begin
  if auth.uid() is null or v_org is null then raise exception 'Not authenticated'; end if;
  if not auth_has_permission('manage_flights') then raise exception 'Permission denied: manage_flights required'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'A reason is required to cancel a flight leg'; end if;
  select * into v_l from flight_legs where id = p_leg_id and organization_id = v_org for update;
  if not found then raise exception 'Flight leg not found'; end if;
  if v_l.status = 'CANCELLED' then raise exception 'This flight leg is already cancelled'; end if;
  update flight_legs set status = 'CANCELLED', cancelled_by = auth.uid(), cancelled_at = now(), cancel_reason = trim(p_reason) where id = p_leg_id;
  perform write_audit_log(v_org, 'flight.leg_cancel', 'flight_leg', p_leg_id, v_l.origin_station_id,
    jsonb_build_object('status', 'SCHEDULED'), jsonb_build_object('status', 'CANCELLED'), trim(p_reason));
end $$;

-- ---- Link a transfer to its flight leg ------------------------------------------
alter table equipment_transfers
  add column if not exists flight_leg_id uuid references flight_legs(id) on delete restrict,
  add column if not exists flight_number text,
  add column if not exists flight_date date,
  add column if not exists flight_origin_code text,
  add column if not exists flight_destination_code text;

create or replace function set_transfer_flight(p_transfer_id uuid, p_flight_leg_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid := auth_organization_id(); v_t equipment_transfers%rowtype; v_l flight_legs%rowtype; v_oc text; v_dc text;
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
  if v_l.status <> 'SCHEDULED' then raise exception 'This flight leg is cancelled and cannot be used'; end if;
  if v_l.origin_station_id <> v_t.from_station_id or v_l.destination_station_id <> v_t.to_station_id then
    raise exception 'The flight''s route does not match the transfer''s sending and receiving stations'; end if;
  if v_l.operating_date < current_date - 1 then raise exception 'The flight date has already passed'; end if;
  select code into v_oc from stations where id = v_l.origin_station_id;
  select code into v_dc from stations where id = v_l.destination_station_id;
  update equipment_transfers set flight_leg_id = v_l.id, flight_number = v_l.flight_number, flight_date = v_l.operating_date,
         flight_origin_code = v_oc, flight_destination_code = v_dc where id = p_transfer_id;
  perform write_audit_log(v_org, 'transfer.set_flight', 'equipment_transfer', p_transfer_id, v_t.from_station_id,
    jsonb_build_object('flight', v_t.flight_number, 'date', v_t.flight_date),
    jsonb_build_object('flight', v_l.flight_number, 'date', v_l.operating_date), null);
end $$;

-- A cancelled leg blocks dispatch.
do $$
declare v_def text;
begin
  v_def := pg_get_functiondef('dispatch_transfer(uuid, jsonb)'::regprocedure);
  v_def := replace(v_def, 'perform _assert_unique_items(p_dispatched_items);',
    E'if v_transfer.flight_leg_id is not null and exists (select 1 from flight_legs where id = v_transfer.flight_leg_id and status = ''CANCELLED'') then\n    raise exception ''The flight for this transfer has been cancelled. Choose another flight before dispatching.'';\n  end if;\n  perform _assert_unique_items(p_dispatched_items);');
  if v_def not like '%flight for this transfer has been cancelled%' then raise exception 'Failed to patch dispatch_transfer'; end if;
  execute v_def;
end $$;

revoke execute on function create_flight_route(text, text, text, integer[], date, date, text), set_flight_route_active(uuid, boolean, text),
  ensure_flight_leg(text, date, uuid, uuid), create_one_off_flight_leg(text, date, uuid, uuid, text), cancel_flight_leg(uuid, text),
  set_transfer_flight(uuid, uuid) from public, anon;
grant execute on function create_flight_route(text, text, text, integer[], date, date, text), set_flight_route_active(uuid, boolean, text),
  ensure_flight_leg(text, date, uuid, uuid), create_one_off_flight_leg(text, date, uuid, uuid, text), cancel_flight_leg(uuid, text),
  set_transfer_flight(uuid, uuid) to authenticated;
