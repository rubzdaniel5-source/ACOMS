-- ============================================================================
-- ACOMS Migration 006: Confirmed Station Types + Real Organization Identity
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Organization: now confirmed as Uganda Airlines. Migrations 001-005 used a
-- placeholder code ('AIRLINE01') deliberately, since org identity wasn't
-- confirmed at the time. Updating in place rather than re-seeding, since
-- roles/stations/permissions already reference this organization_id.
-- ----------------------------------------------------------------------------
update organizations
set code = 'UGANDA_AIRLINES',
    name = 'Uganda Airlines'
where code = 'AIRLINE01';

-- ----------------------------------------------------------------------------
-- Station types confirmed operationally:
-- Stock-holding: ABJ, ACC, DAR, DXB, JNB, FIH, LGW, LOS, LUN, BOM, NBO
-- (plus EBB, already HUB)
-- Pure turnaround (no local stock): BJM, HRE, JUB, KGL, JRO, MGQ, MBA, ZNZ
-- ----------------------------------------------------------------------------
update stations
set station_type = 'NO_STOCK_TURNAROUND'
where code in ('BJM', 'HRE', 'JUB', 'KGL', 'JRO', 'MGQ', 'MBA', 'ZNZ')
  and organization_id = (select id from organizations where code = 'UGANDA_AIRLINES');

-- Explicitly confirm the stock-holding list stays STOCK_HOLDING (defensive —
-- these were already correct from migration 005's default, this just makes
-- the confirmed list unambiguous in the migration history itself).
update stations
set station_type = 'STOCK_HOLDING'
where code in ('ABJ', 'ACC', 'DAR', 'DXB', 'JNB', 'FIH', 'LGW', 'LOS', 'LUN', 'BOM', 'NBO')
  and organization_id = (select id from organizations where code = 'UGANDA_AIRLINES');
