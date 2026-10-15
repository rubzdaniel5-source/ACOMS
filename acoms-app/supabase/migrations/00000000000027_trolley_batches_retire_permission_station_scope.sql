-- ============================================================================
-- ACOMS Migration 027: trolleys tracked in batches; retiring needs a manager;
-- damage/loss steps respect station scope
--
-- 1. Atlas trolleys (R052 full size, R053 half size) are counted in batches by
--    type, not one by one (ADR-009 superseded, see ADR-015). They were seeded
--    as INDIVIDUAL; switched to BATCH. Tolerance stays 0 (any count difference
--    is a discrepancy), editable in the catalogue.
-- 2. New permission retire_equipment (catering manager, catering supervisor,
--    system administrator). Required to assess a report as RETIRE and to
--    retire. Editable in Roles & permissions.
-- 3. SECURITY FIX: the damage and loss workflow steps checked the permission
--    but not the station, so a user at one station could move another
--    station's report along by id. Every step now requires access to the
--    report's station.
-- ============================================================================

update equipment_types set tracking_method = 'BATCH'
where source_code in ('R052', 'R053') and tracking_method = 'INDIVIDUAL';

insert into permissions (code, description) values
  ('retire_equipment', 'Decide that damaged equipment is retired from service')
on conflict (code) do nothing;

insert into role_permissions (role_id, permission_id)
select r.id, p.id from roles r, permissions p
where p.code = 'retire_equipment'
  and r.organization_id = (select id from organizations where code = 'UGANDA_AIRLINES')
  and r.code in ('system_admin', 'catering_manager', 'catering_supervisor')
on conflict do nothing;

create or replace function start_damage_review(p_report_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_report damage_reports%rowtype;
begin
  select * into v_report from damage_reports where id = p_report_id;
  if not found then raise exception 'Damage report % not found', p_report_id; end if;
  if not auth_has_station_access(v_report.station_id) then raise exception 'No station access to this report'; end if;
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
  if not auth_has_station_access(v_report.station_id) then raise exception 'No station access to this report'; end if;
  if v_report.status <> 'UNDER_REVIEW' then
    raise exception 'Must be UNDER_REVIEW to assess (current: %)', v_report.status;
  end if;
  if p_outcome not in ('REPAIRABLE', 'RETIRE') then
    raise exception 'outcome must be REPAIRABLE or RETIRE';
  end if;
  if not auth_has_permission('report_damage') then raise exception 'Missing permission'; end if;
  if p_outcome = 'RETIRE' and not auth_has_permission('retire_equipment') then
    raise exception 'Missing permission: retire_equipment (retiring equipment needs a manager or supervisor)';
  end if;

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
  if not auth_has_station_access(v_report.station_id) then raise exception 'No station access to this report'; end if;
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
  if not auth_has_station_access(v_report.station_id) then raise exception 'No station access to this report'; end if;
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
  if not auth_has_station_access(v_report.station_id) then raise exception 'No station access to this report'; end if;
  if v_report.status <> 'ASSESSED' or v_report.assessment_outcome <> 'RETIRE' then
    raise exception 'Must be ASSESSED as RETIRE (current: %, outcome: %)', v_report.status, v_report.assessment_outcome;
  end if;
  if not auth_has_permission('retire_equipment') then raise exception 'Missing permission: retire_equipment'; end if;

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
  if not auth_has_station_access(v_report.station_id) then raise exception 'No station access to this report'; end if;
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

create or replace function start_loss_investigation(p_report_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_report loss_reports%rowtype;
begin
  select * into v_report from loss_reports where id = p_report_id;
  if not found then raise exception 'Loss report % not found', p_report_id; end if;
  if not auth_has_station_access(v_report.station_id) then raise exception 'No station access to this report'; end if;
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
  if not auth_has_station_access(v_report.station_id) then raise exception 'No station access to this report'; end if;
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
  if not auth_has_station_access(v_report.station_id) then raise exception 'No station access to this report'; end if;
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
  if not auth_has_station_access(v_report.station_id) then raise exception 'No station access to this report'; end if;
  if v_report.status <> 'CONFIRMED_LOSS' then
    raise exception 'Must be CONFIRMED_LOSS to close (current: %)', v_report.status;
  end if;
  if not auth_has_permission('confirm_loss') then raise exception 'Missing permission'; end if;

  update loss_reports set status = 'CLOSED' where id = p_report_id;
  perform write_audit_log(v_report.organization_id, 'loss.close', 'loss_report', p_report_id,
    v_report.station_id, jsonb_build_object('status','CONFIRMED_LOSS'), jsonb_build_object('status','CLOSED'), null);
end; $$;
