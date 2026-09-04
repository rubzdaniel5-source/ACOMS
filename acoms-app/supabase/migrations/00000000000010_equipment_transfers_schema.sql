-- ============================================================================
-- ACOMS Migration 010: Equipment Transfers — Schema
--
-- Per equipment-transfers.md. Lifecycle:
-- REQUESTED -> APPROVED -> DISPATCHED -> IN_TRANSIT -> RECEIVED
--   -> RECONCILIATION -> CLOSED
-- Exceptions: REJECTED, CANCELLED, PARTIALLY_RECEIVED, DISPUTED, DISCREPANCY
--
-- DRAFT is omitted from the MVP state machine deliberately — requests are
-- created directly as REQUESTED. A DRAFT pre-submission state can be added
-- later without breaking this schema; flagging as a known simplification,
-- not a silent scope decision (CLAUDE.md > Change Control).
-- ============================================================================

create sequence transfer_number_seq start 1;

create table equipment_transfers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete restrict,

  transfer_number text not null unique default (
    'TR-' || extract(year from now()) || '-' || lpad(nextval('transfer_number_seq')::text, 6, '0')
  ),

  from_station_id uuid not null references stations(id) on delete restrict,
  to_station_id uuid not null references stations(id) on delete restrict,

  status text not null default 'REQUESTED' check (status in (
    'REQUESTED', 'APPROVED', 'DISPATCHED', 'IN_TRANSIT', 'RECEIVED',
    'RECONCILIATION', 'CLOSED',
    'REJECTED', 'CANCELLED', 'PARTIALLY_RECEIVED', 'DISPUTED', 'DISCREPANCY'
  )),

  requested_by uuid not null references user_profiles(id) on delete restrict,
  requested_at timestamptz not null default now(),

  approved_by uuid references user_profiles(id) on delete restrict,
  approved_at timestamptz,

  dispatched_by uuid references user_profiles(id) on delete restrict,
  dispatched_at timestamptz,

  received_by uuid references user_profiles(id) on delete restrict,
  received_at timestamptz,

  closed_by uuid references user_profiles(id) on delete restrict,
  closed_at timestamptz,

  reason text,
  priority text not null default 'NORMAL' check (priority in ('LOW', 'NORMAL', 'HIGH', 'URGENT')),
  notes text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint chk_transfer_stations_differ check (from_station_id <> to_station_id)
);

comment on column equipment_transfers.transfer_number is
  'Human-readable reference per master spec §60, e.g. TR-2026-000001. UUID id remains the internal key.';

create index idx_transfers_status on equipment_transfers (status);
create index idx_transfers_from_station on equipment_transfers (from_station_id);
create index idx_transfers_to_station on equipment_transfers (to_station_id);

create table equipment_transfer_items (
  id uuid primary key default gen_random_uuid(),
  transfer_id uuid not null references equipment_transfers(id) on delete cascade,
  equipment_type_id uuid not null references equipment_types(id) on delete restrict,

  quantity_requested integer not null check (quantity_requested > 0),
  quantity_approved integer,
  quantity_dispatched integer,
  quantity_received integer,
  quantity_damaged integer not null default 0,
  quantity_missing integer not null default 0,
  quantity_rejected integer not null default 0,

  notes text,

  unique (transfer_id, equipment_type_id)
);

create index idx_transfer_items_transfer on equipment_transfer_items (transfer_id);

create trigger trg_transfers_updated_at before update on equipment_transfers
  for each row execute function set_updated_at();

alter table equipment_transfers enable row level security;
alter table equipment_transfer_items enable row level security;

-- A user can see a transfer if they have station access to EITHER side of it
-- (source or destination), plus view_inventory. Station-scoped roles at the
-- destination need visibility to receive; source-station roles need
-- visibility to dispatch.
create policy "transfers_select_station_scoped"
  on equipment_transfers for select
  using (
    organization_id = auth_organization_id()
    and auth_has_permission('view_inventory')
    and (auth_has_station_access(from_station_id) or auth_has_station_access(to_station_id))
  );

-- No direct insert/update/delete policy — all writes go through the
-- SECURITY DEFINER functions in migration 011, which perform the real
-- state-machine and authorization checks. This is deliberate: the state
-- machine cannot be enforced by RLS alone (RLS checks a row, not a
-- transition), so functions are the actual authorization boundary here.

create policy "transfer_items_select_via_transfer"
  on equipment_transfer_items for select
  using (
    exists (
      select 1 from equipment_transfers t
      where t.id = equipment_transfer_items.transfer_id
        and t.organization_id = auth_organization_id()
        and (auth_has_station_access(t.from_station_id) or auth_has_station_access(t.to_station_id))
    )
  );
