-- ============================================================================
-- ACOMS Migration 007: Equipment Catalogue Schema
--
-- Per equipment-management.md and initial-equipment-catalogue.md.
-- Design notes:
-- - tracking_method distinguishes quantity/bulk vs individual/serialized
--   (ADR-009: trolleys are individually tracked from MVP).
-- - Placeholder/ambiguous source codes (X, XX, xxx, xxxx, xxxxx) are
--   preserved as-is, never invented/replaced (workbook-migration.md
--   "Critical Rule" + master spec §18/§84). A data-quality flag records
--   which rows need operational confirmation instead.
-- - Packaging fields (packaging_unit, pack_size) support consumables sold
--   in cartons while base_unit stays the countable unit (master spec §24).
-- ============================================================================

create table equipment_categories (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete restrict,
  code text not null,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (organization_id, code)
);

create table equipment_types (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete restrict,
  category_id uuid not null references equipment_categories(id) on delete restrict,

  -- Source-of-truth code from the workbook, preserved verbatim even when
  -- it's a placeholder like 'X' or 'xxx'. Never invented or replaced.
  source_code text not null,
  name text not null,

  description text,

  unit_of_measure text not null default 'EACH',
  packaging_unit text,      -- e.g. 'CARTON' — null if sold/counted as base_unit only
  pack_size integer,        -- e.g. 4000 for a carton of tray mats

  tracking_method text not null default 'QUANTITY'
    check (tracking_method in ('QUANTITY', 'INDIVIDUAL', 'BATCH')),

  is_consumable boolean not null default false,
  is_returnable boolean not null default true,
  is_active boolean not null default true,

  reorder_threshold integer,   -- preserved verbatim from workbook terminology
                                -- (master spec §25 — not renamed to minimum_stock)
  minimum_stock integer,
  target_stock integer,
  maximum_stock integer,

  ownership_type text,         -- e.g. 'AIRLINE_OWNED' — null until confirmed

  -- Data quality flags (master spec §18/§84) — never silently "corrected".
  has_data_quality_flag boolean not null default false,
  data_quality_note text,

  reconciliation_tolerance integer not null default 1,
    -- Default per ADR-008: 0 for INDIVIDUAL tracking, 1 for QUANTITY bulk,
    -- overridden per-row below for consumables (2) and trolleys (0).

  notes text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id, source_code)
);

create index idx_equipment_types_category on equipment_types (category_id);
create index idx_equipment_types_org on equipment_types (organization_id);

comment on column equipment_types.source_code is
  'Verbatim from Equipment Inventory-LGW.xlsx. Includes placeholder values (X, XX, xxx, xxxx, xxxxx) by design — see data_quality_note.';
comment on column equipment_types.reconciliation_tolerance is
  'Fixed-unit tolerance per ADR-008, not percentage. Provisional pending operational validation.';

-- ----------------------------------------------------------------------------
-- Aliases: supports search, normalization, and future import matching
-- (master spec §21). Free to grow over time without touching equipment_types.
-- ----------------------------------------------------------------------------
create table equipment_aliases (
  id uuid primary key default gen_random_uuid(),
  equipment_type_id uuid not null references equipment_types(id) on delete cascade,
  alias text not null,
  created_at timestamptz not null default now(),
  unique (equipment_type_id, alias)
);

create index idx_equipment_aliases_alias on equipment_aliases (lower(alias));

create trigger trg_equipment_categories_updated_at before update on equipment_categories
  for each row execute function set_updated_at();
create trigger trg_equipment_types_updated_at before update on equipment_types
  for each row execute function set_updated_at();

-- ----------------------------------------------------------------------------
-- RLS
-- ----------------------------------------------------------------------------
alter table equipment_categories enable row level security;
alter table equipment_types enable row level security;
alter table equipment_aliases enable row level security;

create policy "equipment_categories_select_own_org"
  on equipment_categories for select
  using (organization_id = auth_organization_id());

create policy "equipment_categories_manage"
  on equipment_categories for all
  using (organization_id = auth_organization_id() and auth_has_permission('manage_catalogue'))
  with check (organization_id = auth_organization_id() and auth_has_permission('manage_catalogue'));

create policy "equipment_types_select_own_org"
  on equipment_types for select
  using (organization_id = auth_organization_id());

create policy "equipment_types_manage"
  on equipment_types for all
  using (organization_id = auth_organization_id() and auth_has_permission('manage_catalogue'))
  with check (organization_id = auth_organization_id() and auth_has_permission('manage_catalogue'));

create policy "equipment_aliases_select_own_org"
  on equipment_aliases for select
  using (
    exists (
      select 1 from equipment_types et
      where et.id = equipment_aliases.equipment_type_id
        and et.organization_id = auth_organization_id()
    )
  );

create policy "equipment_aliases_manage"
  on equipment_aliases for all
  using (
    auth_has_permission('manage_catalogue')
    and exists (
      select 1 from equipment_types et
      where et.id = equipment_aliases.equipment_type_id
        and et.organization_id = auth_organization_id()
    )
  )
  with check (
    auth_has_permission('manage_catalogue')
    and exists (
      select 1 from equipment_types et
      where et.id = equipment_aliases.equipment_type_id
        and et.organization_id = auth_organization_id()
    )
  );
