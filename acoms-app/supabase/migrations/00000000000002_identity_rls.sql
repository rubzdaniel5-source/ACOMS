-- ============================================================================
-- ACOMS Migration 002: Row Level Security for Identity Foundation
-- Per CLAUDE.md > Authorization and security.md — RLS is a hard boundary,
-- not a convenience. Every table gets RLS enabled with explicit policies.
-- ============================================================================

alter table organizations enable row level security;
alter table stations enable row level security;
alter table roles enable row level security;
alter table permissions enable row level security;
alter table role_permissions enable row level security;
alter table user_profiles enable row level security;
alter table user_roles enable row level security;

-- ----------------------------------------------------------------------------
-- Organizations: users may only see their own organization.
-- ----------------------------------------------------------------------------
create policy "org_select_own"
  on organizations for select
  using (id = auth_organization_id());

-- Writes to organizations are an admin-only, rare operation — handled via
-- service role / admin tooling, not general application RLS. No insert/update
-- policy is created here deliberately; add one explicitly if a UI need arises.

-- ----------------------------------------------------------------------------
-- Stations: read within own org; station management requires explicit
-- capability (manage_configuration), not just org membership.
-- ----------------------------------------------------------------------------
create policy "stations_select_own_org"
  on stations for select
  using (organization_id = auth_organization_id());

create policy "stations_manage"
  on stations for all
  using (
    organization_id = auth_organization_id()
    and auth_has_permission('manage_configuration')
  )
  with check (
    organization_id = auth_organization_id()
    and auth_has_permission('manage_configuration')
  );

-- ----------------------------------------------------------------------------
-- Roles / Permissions: readable within org (needed for UI to render role
-- names etc.), writable only by manage_users capability.
-- ----------------------------------------------------------------------------
create policy "roles_select_own_org"
  on roles for select
  using (organization_id = auth_organization_id());

create policy "roles_manage"
  on roles for all
  using (
    organization_id = auth_organization_id()
    and auth_has_permission('manage_users')
  )
  with check (
    organization_id = auth_organization_id()
    and auth_has_permission('manage_users')
  );

create policy "permissions_select_all_authenticated"
  on permissions for select
  using (auth.uid() is not null);

create policy "role_permissions_select_own_org"
  on role_permissions for select
  using (
    exists (
      select 1 from roles r
      where r.id = role_permissions.role_id
        and r.organization_id = auth_organization_id()
    )
  );

create policy "role_permissions_manage"
  on role_permissions for all
  using (
    auth_has_permission('manage_users')
    and exists (
      select 1 from roles r
      where r.id = role_permissions.role_id
        and r.organization_id = auth_organization_id()
    )
  )
  with check (
    auth_has_permission('manage_users')
    and exists (
      select 1 from roles r
      where r.id = role_permissions.role_id
        and r.organization_id = auth_organization_id()
    )
  );

-- ----------------------------------------------------------------------------
-- User profiles: a user can always read their own profile; broader visibility
-- requires manage_users. Users cannot edit their own role/org/affiliation.
-- ----------------------------------------------------------------------------
create policy "user_profiles_select_self"
  on user_profiles for select
  using (id = auth.uid());

create policy "user_profiles_select_org_with_permission"
  on user_profiles for select
  using (
    organization_id = auth_organization_id()
    and auth_has_permission('manage_users')
  );

create policy "user_profiles_update_self_limited"
  on user_profiles for update
  using (id = auth.uid())
  with check (
    id = auth.uid()
    and organization_id = auth_organization_id()
  );

create policy "user_profiles_manage_with_permission"
  on user_profiles for all
  using (
    organization_id = auth_organization_id()
    and auth_has_permission('manage_users')
  )
  with check (
    organization_id = auth_organization_id()
    and auth_has_permission('manage_users')
  );

-- ----------------------------------------------------------------------------
-- User roles: visible to self and to manage_users; writable only by
-- manage_users. This is the assignment table that grants station scope.
-- ----------------------------------------------------------------------------
create policy "user_roles_select_self"
  on user_roles for select
  using (user_id = auth.uid());

create policy "user_roles_select_with_permission"
  on user_roles for select
  using (
    auth_has_permission('manage_users')
    and exists (
      select 1 from user_profiles up
      where up.id = user_roles.user_id
        and up.organization_id = auth_organization_id()
    )
  );

create policy "user_roles_manage"
  on user_roles for all
  using (
    auth_has_permission('manage_users')
    and exists (
      select 1 from user_profiles up
      where up.id = user_roles.user_id
        and up.organization_id = auth_organization_id()
    )
  )
  with check (
    auth_has_permission('manage_users')
    and exists (
      select 1 from user_profiles up
      where up.id = user_roles.user_id
        and up.organization_id = auth_organization_id()
    )
  );
