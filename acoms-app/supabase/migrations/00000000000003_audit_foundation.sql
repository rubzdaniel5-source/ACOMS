-- ============================================================================
-- ACOMS Migration 003: Audit Foundation
-- Per CLAUDE.md > Auditability: who, what, when, where, before/after, reason.
-- This is a shared platform service (system.md), not owned by any one domain.
-- ============================================================================

create table audit_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete restrict,

  actor_id uuid references user_profiles(id) on delete set null,
  actor_label text, -- denormalized snapshot of actor name at time of action,
                     -- survives user deactivation/deletion

  action text not null,            -- e.g. 'transfer.approve', 'equipment.create'
  entity_type text not null,       -- e.g. 'equipment_transfer'
  entity_id uuid not null,

  station_id uuid references stations(id) on delete set null,

  before_state jsonb,
  after_state jsonb,
  reason text,

  created_at timestamptz not null default now()
);

create index idx_audit_logs_entity on audit_logs (entity_type, entity_id);
create index idx_audit_logs_org_created on audit_logs (organization_id, created_at desc);
create index idx_audit_logs_actor on audit_logs (actor_id);

comment on table audit_logs is
  'Append-only. No update/delete policy is defined — audit records must never be editable, including by admins, through the application layer.';

alter table audit_logs enable row level security;

-- Audit logs are readable by anyone with view_reports or manage_configuration,
-- scoped to their own organization. No general write policy — inserts happen
-- exclusively via SECURITY DEFINER functions/triggers in each domain module,
-- never directly from client code.
create policy "audit_logs_select_with_permission"
  on audit_logs for select
  using (
    organization_id = auth_organization_id()
    and (auth_has_permission('view_reports') or auth_has_permission('manage_configuration'))
  );

-- Deliberately no insert/update/delete policy for regular roles.
-- Writes go through a SECURITY DEFINER helper (see below) so application
-- code cannot forge or omit audit entries.
create or replace function write_audit_log(
  p_action text,
  p_entity_type text,
  p_entity_id uuid,
  p_station_id uuid,
  p_before jsonb,
  p_after jsonb,
  p_reason text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_org uuid;
  v_actor_label text;
begin
  select organization_id, full_name into v_org, v_actor_label
  from user_profiles where id = auth.uid();

  insert into audit_logs (
    organization_id, actor_id, actor_label, action, entity_type,
    entity_id, station_id, before_state, after_state, reason
  ) values (
    v_org, auth.uid(), v_actor_label, p_action, p_entity_type,
    p_entity_id, p_station_id, p_before, p_after, p_reason
  ) returning id into v_id;

  return v_id;
end;
$$;

comment on function write_audit_log is
  'The only sanctioned way to write an audit entry. Domain-specific functions (e.g. approve_transfer) call this internally so audit trails cannot be bypassed or forged by application code.';
