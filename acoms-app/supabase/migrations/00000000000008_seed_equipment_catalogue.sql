-- ============================================================================
-- ACOMS Migration 008: Seed Equipment Categories + Initial Catalogue
--
-- Source: Equipment Inventory-LGW.xlsx, as documented in
-- initial-equipment-catalogue.md. Reorder thresholds preserved verbatim.
-- Placeholder codes (X, XX, xxx, xxxx, xxxxx) are NOT replaced — flagged
-- instead, per workbook-migration.md Critical Rule.
-- ============================================================================

insert into equipment_categories (organization_id, code, name)
select o.id, c.code, c.name
from organizations o, (values
  ('CROCKERY', 'Crockery / Serving'),
  ('GLASSWARE', 'Glassware'),
  ('CUTLERY', 'Cutlery'),
  ('MEAL_TRAYS', 'Meal Trays / Containers'),
  ('HANDLING_EQUIPMENT', 'Handling Equipment'),
  ('TROLLEYS', 'Trolleys'),
  ('LINEN_ACCESSORIES', 'Linen / Service Accessories'),
  ('CONSUMABLES', 'Consumables / Supplies')
) as c(code, name)
where o.code = 'UGANDA_AIRLINES';

-- Helper: all inserts below resolve organization + category by code, so the
-- statements are self-contained and re-runnable order-independently as long
-- as categories exist first.

-- ----------------------------------------------------------------------------
-- CROCKERY / SERVING (11 items)
-- ----------------------------------------------------------------------------
insert into equipment_types (
  organization_id, category_id, source_code, name, unit_of_measure,
  tracking_method, is_consumable, reorder_threshold, reconciliation_tolerance,
  has_data_quality_flag, data_quality_note
)
select o.id, cat.id, v.source_code, v.name, 'EACH', 'QUANTITY', false,
       v.reorder_threshold, 1, v.flagged, v.note
from organizations o
join equipment_categories cat on cat.organization_id = o.id and cat.code = 'CROCKERY'
join (values
  ('RZ001', 'JC Main Course Casserole', 96,  false, null),
  ('RZ004', 'JC Casserole Underplate', 240,  false, null),
  ('RZ008', 'JC Bowl - Salad/Dessert', 346,  false, null),
  ('RZ012', 'JC Bread Plate', 164,           false, null),
  ('R047',  'Bowl Oval (Melamine)', 96,      false, null),
  ('RZ013', 'JC Butter Dish', 164,           false, null),
  ('RZ019', 'JC Tea/Coffee Mug', 120,        false, null),
  ('RZ022', 'Espresso Cup', 96,              false, null),
  ('RZ023', 'Espresso Saucer', 96,           false, null),
  ('RZ078', 'Milk Jug', 60,                  false, null),
  ('xxx',   'YC Bowls', 904,                 true,  'Placeholder source code (xxx) — needs a confirmed code from operations. JC/YC naming inconsistency also present across the catalogue.')
) as v(source_code, name, reorder_threshold, flagged, note) on true
where o.code = 'UGANDA_AIRLINES';

-- ----------------------------------------------------------------------------
-- GLASSWARE (4 items)
-- ----------------------------------------------------------------------------
insert into equipment_types (
  organization_id, category_id, source_code, name, unit_of_measure,
  tracking_method, is_consumable, reorder_threshold, reconciliation_tolerance
)
select o.id, cat.id, v.source_code, v.name, 'EACH', 'QUANTITY', false, v.reorder_threshold, 1
from organizations o
join equipment_categories cat on cat.organization_id = o.id and cat.code = 'GLASSWARE'
join (values
  ('RZ029', 'JC White Wine Glass', 144),
  ('RZ028', 'JC Red Wine Glass', 48),
  ('RZ031', 'JC Champagne Glass', 48),
  ('RZ025', 'JC Tumbler Glass', 168)
) as v(source_code, name, reorder_threshold) on true
where o.code = 'UGANDA_AIRLINES';

-- ----------------------------------------------------------------------------
-- CUTLERY (6 items)
-- ----------------------------------------------------------------------------
insert into equipment_types (
  organization_id, category_id, source_code, name, unit_of_measure,
  tracking_method, is_consumable, reorder_threshold, reconciliation_tolerance,
  has_data_quality_flag, data_quality_note
)
select o.id, cat.id, v.source_code, v.name, 'EACH', 'QUANTITY', false,
       v.reorder_threshold, 1, v.flagged, v.note
from organizations o
join equipment_categories cat on cat.organization_id = o.id and cat.code = 'CUTLERY'
join (values
  ('RZ033', 'JC Knife', 280,               false, null),
  ('RZ035', 'JC Fork', 280,                false, null),
  ('RZ038', 'JC Dessert Spoon', 280,       false, null),
  ('RZ041', 'JC Coffee/Tea Spoon', 60,     false, null),
  ('RZ040', 'Espresso Spoons', 96,         false, null),
  ('C058',  '7 in 1 Cutlery (Bamboo)', 6000, true, 'Name implies a multi-piece set ("7 in 1") — unit of measure and pack composition need operational confirmation; currently defaulted to EACH.')
) as v(source_code, name, reorder_threshold, flagged, note) on true
where o.code = 'UGANDA_AIRLINES';

-- ----------------------------------------------------------------------------
-- MEAL TRAYS / CONTAINERS (6 items)
-- ----------------------------------------------------------------------------
insert into equipment_types (
  organization_id, category_id, source_code, name, unit_of_measure,
  tracking_method, is_consumable, reorder_threshold, reconciliation_tolerance,
  has_data_quality_flag, data_quality_note
)
select o.id, cat.id, v.source_code, v.name, 'EACH', 'QUANTITY', v.consumable,
       v.reorder_threshold, v.tolerance, v.flagged, v.note
from organizations o
join equipment_categories cat on cat.organization_id = o.id and cat.code = 'MEAL_TRAYS'
join (values
  ('R066', 'JC Meal Tray 1/2 - Brown Plastic, Non-Slip', 56,  false, 1, false, null),
  ('R067', 'JC Meal Tray 1/1 - Brown Plastic, Non-Slip', 224, false, 1, false, null),
  ('R068', 'YC Meal Trays 1/2 - Grey Plastic, Cabin Crew', 444, false, 1, false, null),
  ('R069', 'JC Meal Trays 1/1 - Grey Plastic, Cockpit Crew', 10, false, 1, false, null),
  ('xxxxx', 'Aluminium Foil Casserole', 6000, true, 2,
    true, 'Placeholder source code (xxxxx). Likely single-use consumable, not returnable — flagged is_consumable=true, is_returnable=false; confirm with operations.'),
  ('xxxx',  'Aluminium Foil Casserole Lid', 6000, true, 2,
    true, 'Placeholder source code (xxxx). Same consumable assumption as the matching casserole item above — confirm with operations.')
) as v(source_code, name, reorder_threshold, consumable, tolerance, flagged, note) on true
where o.code = 'UGANDA_AIRLINES';

-- Foil casserole items are consumable and not meant to be returned/tracked
-- like reusable crockery — set is_returnable = false explicitly.
update equipment_types
set is_returnable = false
where source_code in ('xxxxx', 'xxxx')
  and organization_id = (select id from organizations where code = 'UGANDA_AIRLINES');

-- ----------------------------------------------------------------------------
-- HANDLING EQUIPMENT (5 items)
-- ----------------------------------------------------------------------------
insert into equipment_types (
  organization_id, category_id, source_code, name, unit_of_measure,
  tracking_method, is_consumable, reorder_threshold, reconciliation_tolerance,
  has_data_quality_flag, data_quality_note
)
select o.id, cat.id, v.source_code, v.name, 'EACH', 'QUANTITY', false,
       v.reorder_threshold, 1, v.flagged, v.note
from organizations o
join equipment_categories cat on cat.organization_id = o.id and cat.code = 'HANDLING_EQUIPMENT'
join (values
  ('RN098', 'Plastic Glass Rack - 24 Partitions', 8,  false, null),
  ('RN099', 'Plastic Glass Rack - 12 Partitions', 18, false, null),
  ('R056',  'Atlas Plastic Drawer - 38 x 27.4 x 11 cm', 41, false, null),
  ('XX',    'Comb Divider Large', 106,
    true, 'Placeholder source code (XX) — needs confirmed code from operations.'),
  ('X',     'Comb Dividers Small', 106,
    true, 'Placeholder source code (X) — needs confirmed code from operations.')
) as v(source_code, name, reorder_threshold, flagged, note) on true
where o.code = 'UGANDA_AIRLINES';

-- ----------------------------------------------------------------------------
-- TROLLEYS (2 items) — INDIVIDUAL tracking per ADR-009, zero tolerance
-- ----------------------------------------------------------------------------
insert into equipment_types (
  organization_id, category_id, source_code, name, unit_of_measure,
  tracking_method, is_consumable, reorder_threshold, reconciliation_tolerance,
  has_data_quality_flag, data_quality_note
)
select o.id, cat.id, v.source_code, v.name, 'EACH', 'INDIVIDUAL', false,
       v.reorder_threshold, 0, v.flagged, v.note
from organizations o
join equipment_categories cat on cat.organization_id = o.id and cat.code = 'TROLLEYS'
join (values
  ('R052', 'Atlas Trolleys FS', 14, false, null),
  ('R053', 'Atlas Trolleys HS', 0,
    true, 'Reorder threshold recorded as 0 in the source workbook — confirm whether this means no threshold is set, or genuinely zero stock is acceptable, before relying on it for alerts.')
) as v(source_code, name, reorder_threshold, flagged, note) on true
where o.code = 'UGANDA_AIRLINES';

-- ----------------------------------------------------------------------------
-- LINEN / SERVICE ACCESSORIES (5 items)
-- ----------------------------------------------------------------------------
insert into equipment_types (
  organization_id, category_id, source_code, name, unit_of_measure,
  tracking_method, is_consumable, reorder_threshold, reconciliation_tolerance
)
select o.id, cat.id, v.source_code, v.name, 'EACH', 'QUANTITY', v.consumable, v.reorder_threshold, v.tolerance
from organizations o
join equipment_categories cat on cat.organization_id = o.id and cat.code = 'LINEN_ACCESSORIES'
join (values
  ('RN103', 'Table Cloth - Square (JC A330)', 80, false, 1),
  ('RN102', 'Table Cloth - Rectangular (JC CRJ/A320/PY A330)', 112, false, 1),
  ('RN104', 'JC/PY Napkins', 192, true, 2),
  ('C1001', 'Linen Bag', 4, false, 1),
  ('CZ105', 'JC/PY Napkin Rings', 6000, false, 2)
) as v(source_code, name, reorder_threshold, consumable, tolerance) on true
where o.code = 'UGANDA_AIRLINES';

-- ----------------------------------------------------------------------------
-- CONSUMABLES / SUPPLIES (9 items) — packaging fields populated where the
-- workbook's product name specified pack size (e.g. "4000PCS/CTN").
-- ----------------------------------------------------------------------------
insert into equipment_types (
  organization_id, category_id, source_code, name, unit_of_measure,
  packaging_unit, pack_size, tracking_method, is_consumable,
  reorder_threshold, reconciliation_tolerance
)
select o.id, cat.id, v.source_code, v.name, 'EACH', v.packaging_unit, v.pack_size,
       'QUANTITY', true, v.reorder_threshold, 2
from organizations o
join equipment_categories cat on cat.organization_id = o.id and cat.code = 'CONSUMABLES'
join (values
  ('C1002', 'Dental Floss', 6000, null::text, null::integer),
  ('C078',  'YC Tray Mat - Crew Tray/Drawer Liner 1/2', 8000, 'CARTON', 4000),
  ('C1000', 'JC Tray Mat - Crew Tray/Drawer Liner 1/1', 2000, 'CARTON', 2000),
  ('C081',  'Refreshing Wipes', 10000, null, null),
  ('C092',  'Plastic Security Seals - White', 8000, null, null),
  ('CCC1',  'Snack Bags - Chicken', 4000, null, null),
  ('CCC2',  'Snack Bags - Beef', 4000, null, null),
  ('CCC3',  'Snack Bags - Veg', 4000, null, null),
  ('CCC4',  'Serviettes', 30, null, null)
) as v(source_code, name, reorder_threshold, packaging_unit, pack_size) on true
where o.code = 'UGANDA_AIRLINES';
