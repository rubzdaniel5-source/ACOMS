-- ============================================================================
-- ACOMS Migration 005: Station Type + Full Station List
--
-- Corrects the placeholder 2-station seed from migration 004 with the real
-- 20-station network, and introduces station_type to model the operational
-- distinction the business described:
--
-- - HUB: EBB. Always holds equipment, is the source for all exchanges.
-- - STOCK_HOLDING: outstation that keeps its own equipment on the ground
--   and participates in transfers/exchange with the hub or other stations.
-- - NO_STOCK_TURNAROUND: outstation with no equipment held locally. The hub
--   loads enough equipment/meals for both the outbound and inbound sectors,
--   and everything returns on the same rotation. These stations never
--   appear as a transfer destination for standing inventory — flagging
--   this now so the transfer UI doesn't mistakenly imply they hold stock.
--
-- Default: all non-hub stations are seeded as STOCK_HOLDING (the safer
-- assumption — better to show a station as holding equipment and be
-- corrected, than to hide a real shortage). Update specific stations to
-- NO_STOCK_TURNAROUND once operationally confirmed (see docs/development/
-- decisions.md — flagged as provisional, ADR-012).
-- ============================================================================

alter table stations
  add column station_type text not null default 'STOCK_HOLDING'
    check (station_type in ('HUB', 'STOCK_HOLDING', 'NO_STOCK_TURNAROUND'));

comment on column stations.station_type is
  'HUB = base station (EBB), always source of exchange. STOCK_HOLDING = outstation holding own equipment. NO_STOCK_TURNAROUND = outstation with no local equipment; hub loads outbound+inbound needs, all returns on same rotation.';

-- Remove the placeholder seed from migration 004 and replace with the real
-- 20-station network. Safe because no dependent data exists yet (no
-- inventory, transfers, or user_roles reference these station rows).
delete from stations where organization_id = (select id from organizations where code = 'AIRLINE01');

insert into stations (organization_id, code, name, station_type)
select o.id, s.code, s.name, s.station_type
from organizations o, (values
  ('EBB', 'Entebbe',        'HUB'),
  ('ABJ', 'Abuja',          'STOCK_HOLDING'),
  ('BJM', 'Bujumbura',      'STOCK_HOLDING'),
  ('ACC', 'Accra',          'STOCK_HOLDING'),
  ('DAR', 'Dar es Salaam',  'STOCK_HOLDING'),
  ('DXB', 'Dubai',          'STOCK_HOLDING'),
  ('HRE', 'Harare',         'STOCK_HOLDING'),
  ('JNB', 'Johannesburg',   'STOCK_HOLDING'),
  ('JUB', 'Juba',           'STOCK_HOLDING'),
  ('KGL', 'Kigali',         'STOCK_HOLDING'),
  ('JRO', 'Kilimanjaro',    'STOCK_HOLDING'),
  ('FIH', 'Kinshasa',       'STOCK_HOLDING'),
  ('LGW', 'London Gatwick', 'STOCK_HOLDING'),
  ('LOS', 'Lagos',          'STOCK_HOLDING'),
  ('LUN', 'Lusaka',         'STOCK_HOLDING'),
  ('MGQ', 'Mogadishu',      'STOCK_HOLDING'),
  ('MBA', 'Mombasa',        'STOCK_HOLDING'),
  ('BOM', 'Mumbai',         'STOCK_HOLDING'),
  ('NBO', 'Nairobi',        'STOCK_HOLDING'),
  ('ZNZ', 'Zanzibar',       'STOCK_HOLDING')
) as s(code, name, station_type)
where o.code = 'AIRLINE01';
