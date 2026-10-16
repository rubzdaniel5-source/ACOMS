-- ============================================================================
-- ACOMS Migration 033: equipment exchange cases (step 3)
--
-- An exchange is a parent case that ties together an outbound movement
-- (hub to outstation) and a return movement (outstation to hub). Each
-- movement is an ordinary equipment_transfers record, so every existing rule
-- (approval, dispatch, receipt, reconciliation, ledger, audit) applies to it
-- unchanged. The exchange adds: the link, the flight requirement, the
-- closure rules, and an authorised, two-person "close without return"
-- exception. The exchange status is derived from its legs, never typed in.
-- Only stock-holding outstations take part: a no-stock turnaround station
-- has equipment loaded by the hub for both sectors and cannot hold stock.
-- ============================================================================

create sequence exchange_number_seq start 1;

create table equipment_exchanges (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete restrict,
  exchange_number text not null unique default (
    'EX-' || extract(year from now()) || '-' || lpad(nextval('exchange_number_seq')::text, 6, '0')),
  hub_station_id uuid not null references stations(id) on delete restrict,
  outstation_id uuid not null references stations(id) on delete restrict,
  return_required boolean not null default true,
  request_key text,
  created_by uuid not null references user_profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  closed_by uuid references user_profiles(id) on delete restrict,
  closed_at timestamptz,
  close_kind text check (close_kind in ('NORMAL', 'NO_RETURN_EXCEPTION')),
  close_note text,
  no_return_requested_by uuid references user_profiles(id) on delete restrict,
  no_return_requested_at timestamptz,
  no_return_reason text,
  no_return_decision text check (no_return_decision in ('APPROVED', 'REJECTED')),
  no_return_decided_by uuid references user_profiles(id) on delete restrict,
  no_return_decided_at timestamptz,
  no_return_decision_note text,
  constraint chk_exchange_stations_differ check (hub_station_id <> outstation_id),
  constraint chk_exchange_closed check ((closed_at is null) = (close_kind is null))
);
create unique index uq_exchange_request_key on equipment_exchanges (organization_id, created_by, request_key) where request_key is not null;

alter table equipment_transfers
  add column if not exists exchange_id uuid references equipment_exchanges(id) on delete restrict,
  add column if not exists exchange_leg text check (exchange_leg in ('OUTBOUND', 'RETURN'));
alter table equipment_transfers add constraint chk_exchange_leg_pair check ((exchange_id is null) = (exchange_leg is null));
create unique index uq_exchange_active_leg on equipment_transfers (exchange_id, exchange_leg)
  where exchange_id is not null and status not in ('CANCELLED', 'REJECTED');
create index idx_transfers_exchange on equipment_transfers (exchange_id) where exchange_id is not null;

alter table equipment_exchanges enable row level security;
create policy "exchanges_select" on equipment_exchanges for select using (
  organization_id = auth_organization_id() and auth_has_permission('view_inventory')
  and (auth_has_station_access(hub_station_id) or auth_has_station_access(outstation_id)));
-- No write policies: every change goes through the functions below.

-- ---- Derived status and next action -------------------------------------------------
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
         when o.status in ('REQUESTED', 'APPROVED', 'IN_TRANSIT') then 'OUTBOUND'
         when o.status <> 'CLOSED' then 'OUTBOUND_RECONCILIATION'
         when r.id is null and e.return_required then 'AWAITING_RETURN'
         else 'READY_TO_CLOSE'
       end as status,
       case
         when e.closed_at is not null or o.status in ('CANCELLED', 'REJECTED') then null
         when r.id is not null and r.status <> 'CLOSED' then
           case r.status when 'REQUESTED' then 'Approve the return movement' when 'APPROVED' then 'Dispatch the return movement'
             when 'IN_TRANSIT' then 'Receive the return at the hub' when 'RECEIVED' then 'Reconcile the return movement'
             when 'DISCREPANCY' then 'Resolve the return discrepancy' when 'RECONCILIATION' then 'Close the return movement'
             else 'Review the return movement' end
         when o.status = 'REQUESTED' then 'Approve the outbound movement'
         when o.status = 'APPROVED' then 'Dispatch the outbound movement'
         when o.status = 'IN_TRANSIT' then 'Receive at the outstation'
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
         when o.status = 'IN_TRANSIT' then s.code
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
-- ---- Helpers ----------------------------------------------------------------------------
create or replace function _exchange_leg(p_exchange_id uuid, p_leg text)
returns equipment_transfers language sql stable security definer set search_path = public as $$
  select t.* from equipment_transfers t where t.exchange_id = p_exchange_id and t.exchange_leg = p_leg
    and t.status not in ('CANCELLED', 'REJECTED') order by t.requested_at desc limit 1
$$;
revoke execute on function _exchange_leg(uuid, text) from public, anon, authenticated;

-- ---- Start an exchange (outbound hub to outstation) -------------------------------------
create or replace function create_exchange(
  p_outstation_id uuid, p_items jsonb, p_reason text, p_priority text,
  p_flight_number text, p_flight_date date, p_request_key text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_org uuid := auth_organization_id(); v_hub stations%rowtype; v_out stations%rowtype;
  v_id uuid; v_tid uuid; v_leg uuid;
begin
  if auth.uid() is null or v_org is null then raise exception 'Not authenticated'; end if;
  if not auth_has_permission('create_transfer') then raise exception 'Missing permission: create_transfer'; end if;
  if p_request_key is not null then
    select id into v_id from equipment_exchanges where organization_id = v_org and created_by = auth.uid() and request_key = p_request_key;
    if found then return v_id; end if;
  end if;
  select * into v_hub from stations where organization_id = v_org and station_type = 'HUB' and is_active limit 1;
  if not found then raise exception 'No active hub station is configured'; end if;
  if not auth_has_station_access(v_hub.id) then raise exception 'No station access to the hub (%)', v_hub.code; end if;
  select * into v_out from stations where id = p_outstation_id and organization_id = v_org and is_active;
  if not found then raise exception 'Unknown or inactive destination station'; end if;
  if v_out.id = v_hub.id then raise exception 'The destination must be an outstation, not the hub'; end if;
  if v_out.station_type <> 'STOCK_HOLDING' then
    raise exception 'Station % holds no stock. Equipment for turnaround stations is loaded by the hub for both sectors and is not recorded as an exchange.', v_out.code;
  end if;
  if coalesce(trim(p_flight_number), '') = '' or p_flight_date is null then
    raise exception 'A flight and flight date are required for an exchange'; end if;

  v_leg := ensure_flight_leg(p_flight_number, p_flight_date, v_hub.id, v_out.id);

  insert into equipment_exchanges (organization_id, hub_station_id, outstation_id, request_key, created_by)
  values (v_org, v_hub.id, v_out.id, p_request_key, auth.uid()) returning id into v_id;

  v_tid := request_transfer(v_hub.id, v_out.id, p_items, p_reason, coalesce(p_priority, 'NORMAL'));
  update equipment_transfers set exchange_id = v_id, exchange_leg = 'OUTBOUND' where id = v_tid;
  perform set_transfer_flight(v_tid, v_leg);

  perform write_audit_log(v_org, 'exchange.create', 'equipment_exchange', v_id, v_hub.id, null,
    jsonb_build_object('outstation', v_out.code, 'outbound_transfer', v_tid), p_reason);
  return v_id;
end $$;

-- ---- Return movement (outstation to hub) ------------------------------------------------
create or replace function start_exchange_return(
  p_exchange_id uuid, p_items jsonb, p_reason text, p_priority text, p_flight_number text, p_flight_date date
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_org uuid := auth_organization_id(); v_e equipment_exchanges%rowtype; v_o equipment_transfers%rowtype;
  v_tid uuid; v_leg uuid;
begin
  if auth.uid() is null or v_org is null then raise exception 'Not authenticated'; end if;
  select * into v_e from equipment_exchanges where id = p_exchange_id and organization_id = v_org for update;
  if not found then raise exception 'Exchange not found'; end if;
  if v_e.closed_at is not null then raise exception 'This exchange is already closed'; end if;
  if not auth_has_permission('create_transfer') then raise exception 'Missing permission: create_transfer'; end if;
  if not auth_has_station_access(v_e.outstation_id) then raise exception 'No station access to the outstation'; end if;
  v_o := _exchange_leg(p_exchange_id, 'OUTBOUND');
  if v_o.id is null then raise exception 'This exchange has no active outbound movement'; end if;
  if v_o.status not in ('RECEIVED', 'DISCREPANCY', 'RECONCILIATION', 'CLOSED') then
    raise exception 'The outstation can record a return only after it has received the outbound movement (outbound status: %)', v_o.status; end if;
  if (_exchange_leg(p_exchange_id, 'RETURN')).id is not null then
    raise exception 'This exchange already has a return movement'; end if;
  if v_e.no_return_requested_at is not null and v_e.no_return_decision is null then
    raise exception 'A request to close without a return is waiting for a decision'; end if;
  if coalesce(trim(p_flight_number), '') = '' or p_flight_date is null then
    raise exception 'A flight and flight date are required for the return movement'; end if;

  v_leg := ensure_flight_leg(p_flight_number, p_flight_date, v_e.outstation_id, v_e.hub_station_id);
  v_tid := request_transfer(v_e.outstation_id, v_e.hub_station_id, p_items, p_reason, coalesce(p_priority, 'NORMAL'));
  update equipment_transfers set exchange_id = p_exchange_id, exchange_leg = 'RETURN' where id = v_tid;
  perform set_transfer_flight(v_tid, v_leg);

  perform write_audit_log(v_org, 'exchange.return_start', 'equipment_exchange', p_exchange_id, v_e.outstation_id, null,
    jsonb_build_object('return_transfer', v_tid), p_reason);
  return v_tid;
end $$;

-- ---- Close ----------------------------------------------------------------------------------
create or replace function close_exchange(p_exchange_id uuid, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid := auth_organization_id(); v_e equipment_exchanges%rowtype; v_o equipment_transfers%rowtype; v_r equipment_transfers%rowtype;
begin
  if auth.uid() is null or v_org is null then raise exception 'Not authenticated'; end if;
  select * into v_e from equipment_exchanges where id = p_exchange_id and organization_id = v_org for update;
  if not found then raise exception 'Exchange not found'; end if;
  if v_e.closed_at is not null then raise exception 'This exchange is already closed'; end if;
  if not auth_has_permission('reconcile_transfer') then raise exception 'Missing permission: reconcile_transfer'; end if;
  if not (auth_has_station_access(v_e.hub_station_id) or auth_has_station_access(v_e.outstation_id)) then
    raise exception 'No station access to either side of this exchange'; end if;
  v_o := _exchange_leg(p_exchange_id, 'OUTBOUND');
  if v_o.id is null or v_o.status <> 'CLOSED' then
    raise exception 'The outbound movement must be reconciled and closed first (status: %)', coalesce(v_o.status, 'none'); end if;
  if v_e.return_required then
    v_r := _exchange_leg(p_exchange_id, 'RETURN');
    if v_r.id is null then
      raise exception 'No return movement has been recorded. Record the return, or request closure without a return.'; end if;
    if v_r.status <> 'CLOSED' then
      raise exception 'The return movement must be reconciled and closed first (status: %)', v_r.status; end if;
  end if;
  update equipment_exchanges set closed_by = auth.uid(), closed_at = now(), close_kind = 'NORMAL', close_note = nullif(trim(p_note), '') where id = p_exchange_id;
  perform write_audit_log(v_org, 'exchange.close', 'equipment_exchange', p_exchange_id, v_e.hub_station_id,
    null, jsonb_build_object('close_kind', 'NORMAL'), p_note);
end $$;

-- ---- Exception: close without a return (two people, reason required) ------------------------
create or replace function request_exchange_no_return(p_exchange_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid := auth_organization_id(); v_e equipment_exchanges%rowtype;
begin
  if auth.uid() is null or v_org is null then raise exception 'Not authenticated'; end if;
  select * into v_e from equipment_exchanges where id = p_exchange_id and organization_id = v_org for update;
  if not found then raise exception 'Exchange not found'; end if;
  if v_e.closed_at is not null then raise exception 'This exchange is already closed'; end if;
  if not auth_has_permission('create_transfer') then raise exception 'Missing permission: create_transfer'; end if;
  if not (auth_has_station_access(v_e.hub_station_id) or auth_has_station_access(v_e.outstation_id)) then
    raise exception 'No station access to either side of this exchange'; end if;
  if length(trim(coalesce(p_reason, ''))) < 10 then raise exception 'Explain why no return is needed (at least 10 characters)'; end if;
  if (_exchange_leg(p_exchange_id, 'RETURN')).id is not null then
    raise exception 'A return movement already exists for this exchange'; end if;
  if v_e.no_return_requested_at is not null and v_e.no_return_decision is null then
    raise exception 'A request to close without a return is already waiting for a decision'; end if;
  update equipment_exchanges set no_return_requested_by = auth.uid(), no_return_requested_at = now(), no_return_reason = trim(p_reason),
    no_return_decision = null, no_return_decided_by = null, no_return_decided_at = null, no_return_decision_note = null
  where id = p_exchange_id;
  perform write_audit_log(v_org, 'exchange.no_return_request', 'equipment_exchange', p_exchange_id, v_e.hub_station_id, null, null, trim(p_reason));
end $$;

create or replace function decide_exchange_no_return(p_exchange_id uuid, p_approve boolean, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid := auth_organization_id(); v_e equipment_exchanges%rowtype; v_o equipment_transfers%rowtype;
begin
  if auth.uid() is null or v_org is null then raise exception 'Not authenticated'; end if;
  select * into v_e from equipment_exchanges where id = p_exchange_id and organization_id = v_org for update;
  if not found then raise exception 'Exchange not found'; end if;
  if v_e.closed_at is not null then raise exception 'This exchange is already closed'; end if;
  if not auth_has_permission('approve_transfer') then raise exception 'Missing permission: approve_transfer'; end if;
  if not (auth_has_station_access(v_e.hub_station_id) or auth_has_station_access(v_e.outstation_id)) then
    raise exception 'No station access to either side of this exchange'; end if;
  if v_e.no_return_requested_at is null or v_e.no_return_decision is not null then
    raise exception 'There is no pending request to close without a return'; end if;
  if v_e.no_return_requested_by = auth.uid() then
    raise exception 'The person who requested closure without a return cannot decide it'; end if;
  if coalesce(trim(p_note), '') = '' then raise exception 'A note is required with the decision'; end if;
  if p_approve then
    v_o := _exchange_leg(p_exchange_id, 'OUTBOUND');
    if v_o.id is null or v_o.status <> 'CLOSED' then
      raise exception 'The outbound movement must be reconciled and closed first (status: %)', coalesce(v_o.status, 'none'); end if;
    if (_exchange_leg(p_exchange_id, 'RETURN')).id is not null then
      raise exception 'A return movement already exists for this exchange'; end if;
    update equipment_exchanges set no_return_decision = 'APPROVED', no_return_decided_by = auth.uid(), no_return_decided_at = now(),
      no_return_decision_note = trim(p_note), return_required = false, closed_by = auth.uid(), closed_at = now(),
      close_kind = 'NO_RETURN_EXCEPTION', close_note = v_e.no_return_reason where id = p_exchange_id;
  else
    update equipment_exchanges set no_return_decision = 'REJECTED', no_return_decided_by = auth.uid(), no_return_decided_at = now(),
      no_return_decision_note = trim(p_note) where id = p_exchange_id;
  end if;
  perform write_audit_log(v_org, case when p_approve then 'exchange.no_return_approve' else 'exchange.no_return_reject' end,
    'equipment_exchange', p_exchange_id, v_e.hub_station_id, null, jsonb_build_object('decision', case when p_approve then 'APPROVED' else 'REJECTED' end), trim(p_note));
end $$;

revoke execute on function create_exchange(uuid, jsonb, text, text, text, date, text), start_exchange_return(uuid, jsonb, text, text, text, date),
  close_exchange(uuid, text), request_exchange_no_return(uuid, text), decide_exchange_no_return(uuid, boolean, text) from public, anon;
grant execute on function create_exchange(uuid, jsonb, text, text, text, date, text), start_exchange_return(uuid, jsonb, text, text, text, date),
  close_exchange(uuid, text), request_exchange_no_return(uuid, text), decide_exchange_no_return(uuid, boolean, text) to authenticated;
