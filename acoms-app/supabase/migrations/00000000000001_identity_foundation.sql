-- ============================================================================
-- ACOMS Migration 001: Identity Foundation
-- Organizations, Roles, Permissions, Users, Stations
--
-- Design notes (see docs/architecture/decisions.md ADR-007/ADR-010):
-- - Single organization in production today, but every table is org-scoped
--   from day one so multi-airline adoption later does not require redesign.
-- - Roles/permissions are data, not code — new roles are a data change.
-- - User "affiliation" (internal vs external_provider) is tracked separately
--   from role, since outstation catering staff belong to a service provider,
--   not the airline (see decisions.md ADR-011).
-- ============================================================================

create extension if not exists "pgcrypto";

-- ----------------------------------------------------------------------------
-- Organizations
-- ----------------------------------------------------------------------------
create table organizations (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table organizations is
  'Single row today. Table exists so multi-airline adoption does not require schema redesign (ADR-010).';

-- ----------------------------------------------------------------------------
-- Stations
-- ----------------------------------------------------------------------------
create table stations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete restrict,
  code text not null,
  name text not null,
  airport_code text,
  country text,
  timezone text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, code)
);

-- ----------------------------------------------------------------------------
-- Roles (provisional set per decisions.md ADR-009; fully data-driven)
-- ----------------------------------------------------------------------------
create table roles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references organizations(id) on delete restrict,
  code text not null,
  name text not null,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, code)
);

-- ----------------------------------------------------------------------------
-- Permissions (capability-based, per CLAUDE.md > Authorization)
-- ----------------------------------------------------------------------------
create table permissions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  description text,
  created_at timestamptz not null default now()
);

create table role_permissions (
  role_id uuid not null references roles(id) on delete cascade,
  permission_id uuid not null references permissions(id) on delete cascade,
  primary key (role_id, permission_id)
);

-- ----------------------------------------------------------------------------
-- Users (extends Supabase auth.users)
-- ----------------------------------------------------------------------------
create table user_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  organization_id uuid not null references organizations(id) on delete restrict,
  full_name text not null,
  email text not null,
  affiliation text not null default 'internal'
    check (affiliation in ('internal', 'external_provider')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on column user_profiles.affiliation is
  'internal = airline employee (e.g. base/hub Catering Assistant). external_provider = outstation catering service provider staff (ADR-011).';

-- A user may hold multiple roles, and role assignment may be station-scoped
-- (e.g. a Station Manager scoped to one station only).
create table user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references user_profiles(id) on delete cascade,
  role_id uuid not null references roles(id) on delete cascade,
  station_id uuid references stations(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_id, role_id, station_id)
);

comment on column user_roles.station_id is
  'NULL = role applies network-wide (e.g. Catering Manager). Set = role scoped to one station only (e.g. Station Manager at LGW).';

-- ----------------------------------------------------------------------------
-- Helper functions used throughout RLS policies (kept here since they are
-- identity-layer primitives every other domain depends on).
-- ----------------------------------------------------------------------------
create or replace function auth_organization_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select organization_id from user_profiles where id = auth.uid();
$$;

create or replace function auth_has_permission(perm_code text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from user_roles ur
    join role_permissions rp on rp.role_id = ur.role_id
    join permissions p on p.id = rp.permission_id
    where ur.user_id = auth.uid()
      and p.code = perm_code
  );
$$;

create or replace function auth_has_station_access(target_station_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from user_roles ur
    where ur.user_id = auth.uid()
      and (ur.station_id is null or ur.station_id = target_station_id)
  );
$$;

comment on function auth_has_station_access is
  'True if the user has any role that is either network-wide (station_id null) or scoped to the target station.';

-- ----------------------------------------------------------------------------
-- updated_at trigger, reused by every table with an updated_at column
-- ----------------------------------------------------------------------------
create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_organizations_updated_at before update on organizations
  for each row execute function set_updated_at();
create trigger trg_stations_updated_at before update on stations
  for each row execute function set_updated_at();
create trigger trg_roles_updated_at before update on roles
  for each row execute function set_updated_at();
create trigger trg_user_profiles_updated_at before update on user_profiles
  for each row execute function set_updated_at();
