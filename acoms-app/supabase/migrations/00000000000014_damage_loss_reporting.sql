-- ============================================================================
-- ACOMS Migration 014: Standalone Damage & Loss Reporting
--
-- Distinct from transfer-reconciliation damage/loss (migration 011) — this
-- covers equipment damaged/lost during normal daily use, not tied to a
-- transfer. Per damage-loss.md lifecycles.
--
-- Damage: REPORTED -> UNDER_REVIEW -> ASSESSED -> REPAIR -> RETURNED_TO_SERVICE
--                                              -> RETIRED -> DISPOSED
-- Loss:   REPORTED -> INVESTIGATION -> RECOVERED
--                                   -> CONFIRMED_LOSS -> CLOSED
--
-- Ledger: reporting moves quantity OUT of available_quantity (via
-- apply_inventory_transaction) and into the damaged_quantity/
-- missing_quantity bucket directly. Returning to service / recovering
-- moves it back via RECOVERY. Disposal / confirmed loss permanently
-- removes it from the bucket with no further available_quantity change
-- (already removed when first reported).
-- ============================================================================

create table damage_reports (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete restrict,
  station_id uuid not null references stations(id) on delete restrict,
  equipment_type_id uuid not null references equipment_types(id) on delete restrict,
  quantity integer not null check (quantity > 0),

  status text not null default 'REPORTED' check (status in (
    'REPORTED', 'UNDER_REVIEW', 'ASSESSED', 'REPAIR', 'RETURNED_TO_SERVICE',
    'RETIRED', 'DISPOSED'
  )),
  assessment_outcome text check (assessment_outcome in ('REPAIRABLE', 'RETIRE')),

  reported_by uuid not null references user_profiles(id) on delete restrict,
  reported_at timestamptz not null default now(),
  reason text not null,

  assessed_by uuid references user_profiles(id) on delete restrict,
  assessed_at timestamptz,
  assessment_notes text,

  resolved_by uuid references user_profiles(id) on delete restrict,
  resolved_at timestamptz,

  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table loss_reports (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete restrict,
  station_id uuid not null references stations(id) on delete restrict,
  equipment_type_id uuid not null references equipment_types(id) on delete restrict,
  quantity integer not null check (quantity > 0),

  status text not null default 'REPORTED' check (status in (
    'REPORTED', 'INVESTIGATION', 'RECOVERED', 'CONFIRMED_LOSS', 'CLOSED'
  )),

  reported_by uuid not null references user_profiles(id) on delete restrict,
  reported_at timestamptz not null default now(),
  circumstances text not null,

  investigator uuid references user_profiles(id) on delete restrict,
  investigation_started_at timestamptz,
  resolution_notes text,
  resolved_by uuid references user_profiles(id) on delete restrict,
  resolved_at timestamptz,

  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_damage_reports_station on damage_reports (station_id, status);
create index idx_loss_reports_station on loss_reports (station_id, status);

create trigger trg_damage_reports_updated_at before update on damage_reports
  for each row execute function set_updated_at();
create trigger trg_loss_reports_updated_at before update on loss_reports
  for each row execute function set_updated_at();

alter table damage_reports enable row level security;
alter table loss_reports enable row level security;

create policy "damage_reports_select_station_scoped"
  on damage_reports for select
  using (organization_id = auth_organization_id() and auth_has_station_access(station_id));

create policy "loss_reports_select_station_scoped"
  on loss_reports for select
  using (organization_id = auth_organization_id() and auth_has_station_access(station_id));

-- No direct write policies — all writes go through the functions below,
-- same pattern as equipment_transfers.

-- ----------------------------------------------------------------------------
-- DAMAGE functions
-- ----------------------------------------------------------------------------
create or replace function report_damage(
  p_equipment_type_id uuid,
  p_station_id uuid,
  p_quantity integer,
  p_reason text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org uuid;
  v_report_id uuid;
begin
  if not auth_has_permission('report_damage') then
    raise exception 'Missing permission: report_damage';
  end if;
  if not auth_has_station_access(p_station_id) then
    raise exception 'No station access to %', p_station_id;
  end if;

  select organization_id into v_org from stations where id = p_station_id;

  insert into damage_reports (organization_id, station_id, equipment_type_id, quantity, reported_by, reason)
  values (v_org, p_station_id, p_equipment_type_id, p_quantity, auth.uid(), p_reason)
  returning id into v_report_id;

  perform apply_inventory_transaction(
    p_equipment_type_id, p_station_id, 'DAMAGE', p_quantity,
    'damage_report', v_report_id, 'Reported damage: ' || p_reason
  );
  update inventory_balances
  set damaged_quantity = damaged_quantity + p_quantity, updated_at = now()
  where equipment_type_id = p_equipment_type_id and station_id = p_station_id;

  perform write_audit_log(v_org, 'damage.report', 'damage_report', v_report_id,
    p_station_id, null, jsonb_build_object('quantity', p_quantity), p_reason);

  return v_report_id;
end;
$$;

create or replace function start_damage_review(p_report_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_report damage_reports%rowtype;
begin
  select * into v_report from damage_reports where id = p_report_id;
  if not found then raise exception 'Damage report % not found', p_report_id; end if;
  if v_report.status <> 'REPORTED' then
    raise exception 'Must be REPORTED to start review (current: %)', v_report.status;
  end if;
  if not auth_has_permission('report_damage') then raise exception 'Missing permission'; end if;

  update damage_reports set status = 'UNDER_REVIEW' where id = p_report_id;
  perform write_audit_log(v_report.organization_id, 'damage.start_review', 'damage_report', p_report_id,
    v_report.station_id, jsonb_build_object('status','REPORTED'), jsonb_build_object('status','UNDER_REVIEW'), null);
end; $$;

create or replace function assess_damage(
  p_report_id uuid,
  p_outcome text,
  p_notes text
) returns void
language plpgsql security definer set search_path = public as $$
declare v_report damage_reports%rowtype;
begin
  select * into v_report from damage_reports where id = p_report_id;
  if not found then raise exception 'Damage report % not found', p_report_id; end if;
  if v_report.status <> 'UNDER_REVIEW' then
    raise exception 'Must be UNDER_REVIEW to assess (current: %)', v_report.status;
  end if;
  if p_outcome not in ('REPAIRABLE', 'RETIRE') then
    raise exception 'outcome must be REPAIRABLE or RETIRE';
  end if;
  if not auth_has_permission('report_damage') then raise exception 'Missing permission'; end if;

  update damage_reports
  set status = 'ASSESSED', assessment_outcome = p_outcome, assessment_notes = p_notes,
      assessed_by = auth.uid(), assessed_at = now()
  where id = p_report_id;

  perform write_audit_log(v_report.organization_id, 'damage.assess', 'damage_report', p_report_id,
    v_report.station_id, jsonb_build_object('status','UNDER_REVIEW'),
    jsonb_build_object('status','ASSESSED','outcome',p_outcome), p_notes);
end; $$;

create or replace function start_repair(p_report_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_report damage_reports%rowtype;
begin
  select * into v_report from damage_reports where id = p_report_id;
  if not found then raise exception 'Damage report % not found', p_report_id; end if;
  if v_report.status <> 'ASSESSED' or v_report.assessment_outcome <> 'REPAIRABLE' then
    raise exception 'Must be ASSESSED as REPAIRABLE to start repair (current: %, outcome: %)', v_report.status, v_report.assessment_outcome;
  end if;
  if not auth_has_permission('report_damage') then raise exception 'Missing permission'; end if;

  update damage_reports set status = 'REPAIR' where id = p_report_id;
  perform write_audit_log(v_report.organization_id, 'damage.start_repair', 'damage_report', p_report_id,
    v_report.station_id, jsonb_build_object('status','ASSESSED'), jsonb_build_object('status','REPAIR'), null);
end; $$;

create or replace function return_to_service(p_report_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_report damage_reports%rowtype;
begin
  select * into v_report from damage_reports where id = p_report_id;
  if not found then raise exception 'Damage report % not found', p_report_id; end if;
  if v_report.status <> 'REPAIR' then
    raise exception 'Must be REPAIR to return to service (current: %)', v_report.status;
  end if;
  if not auth_has_permission('report_damage') then raise exception 'Missing permission'; end if;

  perform apply_inventory_transaction(
    v_report.equipment_type_id, v_report.station_id, 'RECOVERY', v_report.quantity,
    'damage_report', p_report_id, 'Returned to service after repair'
  );
  update inventory_balances
  set damaged_quantity = greatest(0, damaged_quantity - v_report.quantity), updated_at = now()
  where equipment_type_id = v_report.equipment_type_id and station_id = v_report.station_id;

  update damage_reports
  set status = 'RETURNED_TO_SERVICE', resolved_by = auth.uid(), resolved_at = now()
  where id = p_report_id;

  perform write_audit_log(v_report.organization_id, 'damage.return_to_service', 'damage_report', p_report_id,
    v_report.station_id, jsonb_build_object('status','REPAIR'), jsonb_build_object('status','RETURNED_TO_SERVICE'), null);
end; $$;

create or replace function retire_equipment(p_report_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_report damage_reports%rowtype;
begin
  select * into v_report from damage_reports where id = p_report_id;
  if not found then raise exception 'Damage report % not found', p_report_id; end if;
  if v_report.status <> 'ASSESSED' or v_report.assessment_outcome <> 'RETIRE' then
    raise exception 'Must be ASSESSED as RETIRE (current: %, outcome: %)', v_report.status, v_report.assessment_outcome;
  end if;
  if not auth_has_permission('report_damage') then raise exception 'Missing permission'; end if;

  update damage_reports set status = 'RETIRED' where id = p_report_id;
  perform write_audit_log(v_report.organization_id, 'damage.retire', 'damage_report', p_report_id,
    v_report.station_id, jsonb_build_object('status','ASSESSED'), jsonb_build_object('status','RETIRED'), null);
end; $$;

create or replace function dispose_equipment(p_report_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_report damage_reports%rowtype;
begin
  select * into v_report from damage_reports where id = p_report_id;
  if not found then raise exception 'Damage report % not found', p_report_id; end if;
  if v_report.status <> 'RETIRED' then
    raise exception 'Must be RETIRED to dispose (current: %)', v_report.status;
  end if;
  if not auth_has_permission('manage_catalogue') then raise exception 'Missing permission: manage_catalogue'; end if;

  update inventory_balances
  set damaged_quantity = greatest(0, damaged_quantity - v_report.quantity), updated_at = now()
  where equipment_type_id = v_report.equipment_type_id and station_id = v_report.station_id;

  update damage_reports
  set status = 'DISPOSED', resolved_by = auth.uid(), resolved_at = now()
  where id = p_report_id;

  perform write_audit_log(v_report.organization_id, 'damage.dispose', 'damage_report', p_report_id,
    v_report.station_id, jsonb_build_object('status','RETIRED'), jsonb_build_object('status','DISPOSED'), null);
end; $$;

-- ----------------------------------------------------------------------------
-- LOSS functions
-- ----------------------------------------------------------------------------
create or replace function report_loss(
  p_equipment_type_id uuid,
  p_station_id uuid,
  p_quantity integer,
  p_circumstances text
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_org uuid;
  v_report_id uuid;
begin
  if not auth_has_permission('confirm_loss') then
    raise exception 'Missing permission: confirm_loss';
  end if;
  if not auth_has_station_access(p_station_id) then
    raise exception 'No station access to %', p_station_id;
  end if;

  select organization_id into v_org from stations where id = p_station_id;

  insert into loss_reports (organization_id, station_id, equipment_type_id, quantity, reported_by, circumstances)
  values (v_org, p_station_id, p_equipment_type_id, p_quantity, auth.uid(), p_circumstances)
  returning id into v_report_id;

  perform apply_inventory_transaction(
    p_equipment_type_id, p_station_id, 'LOSS', p_quantity,
    'loss_report', v_report_id, 'Reported loss: ' || p_circumstances
  );
  update inventory_balances
  set missing_quantity = missing_quantity + p_quantity, updated_at = now()
  where equipment_type_id = p_equipment_type_id and station_id = p_station_id;

  perform write_audit_log(v_org, 'loss.report', 'loss_report', v_report_id,
    p_station_id, null, jsonb_build_object('quantity', p_quantity), p_circumstances);

  return v_report_id;
end; $$;

create or replace function start_loss_investigation(p_report_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_report loss_reports%rowtype;
begin
  select * into v_report from loss_reports where id = p_report_id;
  if not found then raise exception 'Loss report % not found', p_report_id; end if;
  if v_report.status <> 'REPORTED' then
    raise exception 'Must be REPORTED to start investigation (current: %)', v_report.status;
  end if;
  if not auth_has_permission('confirm_loss') then raise exception 'Missing permission'; end if;

  update loss_reports
  set status = 'INVESTIGATION', investigator = auth.uid(), investigation_started_at = now()
  where id = p_report_id;

  perform write_audit_log(v_report.organization_id, 'loss.start_investigation', 'loss_report', p_report_id,
    v_report.station_id, jsonb_build_object('status','REPORTED'), jsonb_build_object('status','INVESTIGATION'), null);
end; $$;

create or replace function recover_loss(p_report_id uuid, p_resolution_notes text) returns void
language plpgsql security definer set search_path = public as $$
declare v_report loss_reports%rowtype;
begin
  select * into v_report from loss_reports where id = p_report_id;
  if not found then raise exception 'Loss report % not found', p_report_id; end if;
  if v_report.status <> 'INVESTIGATION' then
    raise exception 'Must be INVESTIGATION to recover (current: %)', v_report.status;
  end if;
  if not auth_has_permission('confirm_loss') then raise exception 'Missing permission'; end if;

  perform apply_inventory_transaction(
    v_report.equipment_type_id, v_report.station_id, 'RECOVERY', v_report.quantity,
    'loss_report', p_report_id, 'Recovered: ' || coalesce(p_resolution_notes, '')
  );
  update inventory_balances
  set missing_quantity = greatest(0, missing_quantity - v_report.quantity), updated_at = now()
  where equipment_type_id = v_report.equipment_type_id and station_id = v_report.station_id;

  update loss_reports
  set status = 'RECOVERED', resolution_notes = p_resolution_notes, resolved_by = auth.uid(), resolved_at = now()
  where id = p_report_id;

  perform write_audit_log(v_report.organization_id, 'loss.recover', 'loss_report', p_report_id,
    v_report.station_id, jsonb_build_object('status','INVESTIGATION'), jsonb_build_object('status','RECOVERED'), p_resolution_notes);
end; $$;

create or replace function confirm_loss(p_report_id uuid, p_resolution_notes text) returns void
language plpgsql security definer set search_path = public as $$
declare v_report loss_reports%rowtype;
begin
  select * into v_report from loss_reports where id = p_report_id;
  if not found then raise exception 'Loss report % not found', p_report_id; end if;
  if v_report.status <> 'INVESTIGATION' then
    raise exception 'Must be INVESTIGATION to confirm loss (current: %)', v_report.status;
  end if;
  if not auth_has_permission('confirm_loss') then raise exception 'Missing permission'; end if;
  if p_resolution_notes is null or length(trim(p_resolution_notes)) = 0 then
    raise exception 'A resolution reason is required to confirm a loss';
  end if;

  update inventory_balances
  set missing_quantity = greatest(0, missing_quantity - v_report.quantity), updated_at = now()
  where equipment_type_id = v_report.equipment_type_id and station_id = v_report.station_id;

  update loss_reports
  set status = 'CONFIRMED_LOSS', resolution_notes = p_resolution_notes, resolved_by = auth.uid(), resolved_at = now()
  where id = p_report_id;

  perform write_audit_log(v_report.organization_id, 'loss.confirm', 'loss_report', p_report_id,
    v_report.station_id, jsonb_build_object('status','INVESTIGATION'), jsonb_build_object('status','CONFIRMED_LOSS'), p_resolution_notes);
end; $$;

create or replace function close_loss_report(p_report_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_report loss_reports%rowtype;
begin
  select * into v_report from loss_reports where id = p_report_id;
  if not found then raise exception 'Loss report % not found', p_report_id; end if;
  if v_report.status <> 'CONFIRMED_LOSS' then
    raise exception 'Must be CONFIRMED_LOSS to close (current: %)', v_report.status;
  end if;
  if not auth_has_permission('confirm_loss') then raise exception 'Missing permission'; end if;

  update loss_reports set status = 'CLOSED' where id = p_report_id;
  perform write_audit_log(v_report.organization_id, 'loss.close', 'loss_report', p_report_id,
    v_report.station_id, jsonb_build_object('status','CONFIRMED_LOSS'), jsonb_build_object('status','CLOSED'), null);
end; $$;
