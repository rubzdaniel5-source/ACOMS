-- ============================================================================
-- ACOMS Migration 018: User & Role Management (Admin Batch 2)
--
-- SECURITY FIX: migration 002 let anyone holding manage_users write directly
-- to roles, role_permissions, user_roles and user_profiles through the API,
-- i.e. grant themselves System Administrator. It also let every user update
-- their own profile row (including is_active). All of those write policies
-- are dropped; every change now goes through SECURITY DEFINER functions that
-- enforce: capability, same organisation, no self-modification, no privilege
-- escalation (you can only grant what you hold), last-admin protection, and
-- an audit entry.
--
-- Also: deactivated users immediately lose all access (not only at next
-- token refresh), because the auth_* helpers now require is_active.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Deactivated users lose access immediately
-- ----------------------------------------------------------------------------
create or replace function auth_organization_id()
returns uuid language sql stable security definer set search_path = public as $$
  select organization_id from user_profiles where id = auth.uid() and is_active;
$$;

create or replace function auth_has_permission(perm_code text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from user_profiles up
    join user_roles ur on ur.user_id = up.id
    join role_permissions rp on rp.role_id = ur.role_id
    join permissions p on p.id = rp.permission_id
    join roles r on r.id = ur.role_id and r.is_active
    where up.id = auth.uid() and up.is_active and p.code = perm_code
  );
$$;

create or replace function auth_has_station_access(target_station_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from user_profiles up
    join user_roles ur on ur.user_id = up.id
    where up.id = auth.uid() and up.is_active
      and (ur.station_id is null or ur.station_id = target_station_id)
  );
$$;

-- ----------------------------------------------------------------------------
-- 2. Remove direct-write policies
-- ----------------------------------------------------------------------------
drop policy if exists "roles_manage" on roles;
drop policy if exists "role_permissions_manage" on role_permissions;
drop policy if exists "user_profiles_update_self_limited" on user_profiles;
drop policy if exists "user_profiles_manage_with_permission" on user_profiles;
drop policy if exists "user_roles_manage" on user_roles;

-- ----------------------------------------------------------------------------
-- 3. New permission
-- ----------------------------------------------------------------------------
insert into permissions (code, description) values
  ('manage_roles', 'Create roles and edit which permissions each role carries')
on conflict (code) do nothing;

insert into role_permissions (role_id, permission_id)
select r.id, p.id from roles r, permissions p
where r.code = 'system_admin' and p.code = 'manage_roles'
  and r.organization_id = (select id from organizations where code = 'UGANDA_AIRLINES')
on conflict do nothing;

-- ----------------------------------------------------------------------------
-- 4. Internal helpers (callable only by other definer functions)
-- ----------------------------------------------------------------------------
-- True if the caller holds EVERY permission the role carries (no escalation).
create or replace function _caller_covers_role(p_role_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (
    select 1 from role_permissions rp
    join permissions p on p.id = rp.permission_id
    where rp.role_id = p_role_id and not auth_has_permission(p.code)
  );
$$;

-- True if the caller covers every role currently held by the target user.
create or replace function _caller_covers_user(p_user_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (
    select 1 from user_roles ur
    where ur.user_id = p_user_id and not _caller_covers_role(ur.role_id)
  );
$$;

-- Active users holding system_admin, optionally ignoring one user / one assignment.
create or replace function _other_active_admins(p_exclude_user uuid, p_exclude_user_role uuid default null)
returns integer language sql stable security definer set search_path = public as $$
  select count(distinct up.id)::integer
  from user_roles ur
  join roles r on r.id = ur.role_id and r.code = 'system_admin' and r.is_active
  join user_profiles up on up.id = ur.user_id and up.is_active
  where up.organization_id = auth_organization_id()
    and up.id <> coalesce(p_exclude_user, '00000000-0000-0000-0000-000000000000')
    and ur.id <> coalesce(p_exclude_user_role, '00000000-0000-0000-0000-000000000000');
$$;

create or replace function _require_manage_users() returns uuid
language plpgsql stable security definer set search_path = public as $$
declare v_org uuid := auth_organization_id();
begin
  if auth.uid() is null or v_org is null then raise exception 'Not authenticated'; end if;
  if not auth_has_permission('manage_users') then
    raise exception 'Permission denied: manage_users required';
  end if;
  return v_org;
end;
$$;

revoke execute on function _caller_covers_role(uuid), _caller_covers_user(uuid),
  _other_active_admins(uuid, uuid), _require_manage_users() from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- 5. User listing (includes last sign-in and password-change flag from auth)
-- ----------------------------------------------------------------------------
create or replace function admin_list_users()
returns table (
  id uuid, full_name text, email text, affiliation text, is_active boolean,
  created_at timestamptz, last_sign_in_at timestamptz, must_change_password boolean,
  roles jsonb
)
language plpgsql stable security definer set search_path = public as $$
declare v_org uuid := _require_manage_users();
begin
  return query
  select up.id, up.full_name, up.email, up.affiliation, up.is_active, up.created_at,
         au.last_sign_in_at,
         coalesce((au.raw_app_meta_data->>'must_change_password')::boolean, false),
         coalesce((
           select jsonb_agg(jsonb_build_object(
             'user_role_id', ur.id, 'role_id', r.id, 'role_name', r.name, 'role_code', r.code,
             'station_id', ur.station_id, 'station_code', s.code
           ) order by r.name)
           from user_roles ur
           join roles r on r.id = ur.role_id
           left join stations s on s.id = ur.station_id
           where ur.user_id = up.id
         ), '[]'::jsonb)
  from user_profiles up
  left join auth.users au on au.id = up.id
  where up.organization_id = v_org
  order by up.full_name;
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. Creating users: authorise first, create the auth user (server, service
--    role), then finalise. All checks are repeated at finalise.
-- ----------------------------------------------------------------------------
create or replace function authorize_user_creation(p_role_id uuid, p_station_id uuid)
returns void language plpgsql stable security definer set search_path = public as $$
declare v_org uuid := _require_manage_users();
begin
  if not exists (select 1 from roles where id = p_role_id and organization_id = v_org and is_active) then
    raise exception 'Unknown or inactive role';
  end if;
  if not _caller_covers_role(p_role_id) then
    raise exception 'You cannot assign a role with permissions you do not hold yourself';
  end if;
  if p_station_id is not null then
    if not exists (select 1 from stations where id = p_station_id and organization_id = v_org) then
      raise exception 'Unknown station';
    end if;
    if not auth_has_station_access(p_station_id) then
      raise exception 'You have no access to that station';
    end if;
  end if;
end;
$$;

create or replace function finalize_user_creation(
  p_user_id uuid, p_full_name text, p_email text, p_affiliation text,
  p_role_id uuid, p_station_id uuid
) returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid := _require_manage_users();
begin
  perform authorize_user_creation(p_role_id, p_station_id);
  if coalesce(trim(p_full_name), '') = '' then raise exception 'Full name is required'; end if;
  if p_affiliation not in ('internal', 'external_provider') then raise exception 'Invalid affiliation'; end if;
  if not exists (
    select 1 from auth.users
    where id = p_user_id and lower(email) = lower(p_email)
      and created_at > now() - interval '10 minutes'
  ) then
    raise exception 'Auth user not found or not newly created';
  end if;
  if exists (select 1 from user_profiles where id = p_user_id) then
    raise exception 'Profile already exists';
  end if;

  insert into user_profiles (id, organization_id, full_name, email, affiliation)
  values (p_user_id, v_org, trim(p_full_name), lower(p_email), p_affiliation);
  insert into user_roles (user_id, role_id, station_id) values (p_user_id, p_role_id, p_station_id);

  perform write_audit_log(v_org, 'user.create', 'user', p_user_id, p_station_id, null,
    jsonb_build_object('email', lower(p_email), 'role_id', p_role_id, 'affiliation', p_affiliation), null);
end;
$$;

-- ----------------------------------------------------------------------------
-- 7. Existing users
-- ----------------------------------------------------------------------------
create or replace function update_user_profile(p_user_id uuid, p_full_name text, p_affiliation text)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid := _require_manage_users(); v_old user_profiles%rowtype;
begin
  select * into v_old from user_profiles where id = p_user_id and organization_id = v_org;
  if not found then raise exception 'User not found'; end if;
  if coalesce(trim(p_full_name), '') = '' then raise exception 'Full name is required'; end if;
  if p_affiliation not in ('internal', 'external_provider') then raise exception 'Invalid affiliation'; end if;
  if not _caller_covers_user(p_user_id) then raise exception 'You cannot modify a user with permissions you do not hold'; end if;

  update user_profiles set full_name = trim(p_full_name), affiliation = p_affiliation, updated_at = now()
  where id = p_user_id;
  perform write_audit_log(v_org, 'user.update', 'user', p_user_id, null,
    jsonb_build_object('full_name', v_old.full_name, 'affiliation', v_old.affiliation),
    jsonb_build_object('full_name', trim(p_full_name), 'affiliation', p_affiliation), null);
end;
$$;

create or replace function assign_user_role(p_user_id uuid, p_role_id uuid, p_station_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid := _require_manage_users();
begin
  if p_user_id = auth.uid() then raise exception 'You cannot change your own roles'; end if;
  if not exists (select 1 from user_profiles where id = p_user_id and organization_id = v_org) then
    raise exception 'User not found';
  end if;
  perform authorize_user_creation(p_role_id, p_station_id);
  if exists (
    select 1 from user_roles
    where user_id = p_user_id and role_id = p_role_id and station_id is not distinct from p_station_id
  ) then raise exception 'User already has this role at this scope'; end if;

  insert into user_roles (user_id, role_id, station_id) values (p_user_id, p_role_id, p_station_id);
  perform write_audit_log(v_org, 'user.role_assign', 'user', p_user_id, p_station_id, null,
    jsonb_build_object('role_id', p_role_id), null);
end;
$$;

create or replace function remove_user_role(p_user_role_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid := _require_manage_users(); v_ur user_roles%rowtype; v_code text;
begin
  select ur.* into v_ur from user_roles ur
  join user_profiles up on up.id = ur.user_id
  where ur.id = p_user_role_id and up.organization_id = v_org;
  if not found then raise exception 'Role assignment not found'; end if;
  if v_ur.user_id = auth.uid() then raise exception 'You cannot change your own roles'; end if;
  if not _caller_covers_role(v_ur.role_id) then
    raise exception 'You cannot remove a role with permissions you do not hold yourself';
  end if;
  select code into v_code from roles where id = v_ur.role_id;
  if v_code = 'system_admin' and _other_active_admins(v_ur.user_id, v_ur.id) < 1 then
    raise exception 'Cannot remove the last System Administrator';
  end if;

  delete from user_roles where id = p_user_role_id;
  perform write_audit_log(v_org, 'user.role_remove', 'user', v_ur.user_id, v_ur.station_id,
    jsonb_build_object('role_id', v_ur.role_id), null, null);
end;
$$;

create or replace function set_user_active(p_user_id uuid, p_active boolean, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid := _require_manage_users(); v_prof user_profiles%rowtype;
begin
  if p_user_id = auth.uid() then raise exception 'You cannot deactivate or reactivate yourself'; end if;
  select * into v_prof from user_profiles where id = p_user_id and organization_id = v_org;
  if not found then raise exception 'User not found'; end if;
  if not _caller_covers_user(p_user_id) then raise exception 'You cannot modify a user with permissions you do not hold'; end if;
  if not p_active then
    if coalesce(trim(p_reason), '') = '' then raise exception 'A reason is required to deactivate a user'; end if;
    if exists (select 1 from user_roles ur join roles r on r.id = ur.role_id
               where ur.user_id = p_user_id and r.code = 'system_admin')
       and _other_active_admins(p_user_id) < 1 then
      raise exception 'Cannot deactivate the last System Administrator';
    end if;
  end if;

  update user_profiles set is_active = p_active, updated_at = now() where id = p_user_id;
  perform write_audit_log(v_org, case when p_active then 'user.activate' else 'user.deactivate' end,
    'user', p_user_id, null, jsonb_build_object('is_active', v_prof.is_active),
    jsonb_build_object('is_active', p_active), p_reason);
end;
$$;

-- Password reset: server action authorises here, performs the reset with the
-- service role, then records the event.
create or replace function authorize_password_reset(p_user_id uuid)
returns void language plpgsql stable security definer set search_path = public as $$
declare v_org uuid := _require_manage_users();
begin
  if p_user_id = auth.uid() then raise exception 'Use Change Password for your own account'; end if;
  if not exists (select 1 from user_profiles where id = p_user_id and organization_id = v_org) then
    raise exception 'User not found';
  end if;
  if not _caller_covers_user(p_user_id) then raise exception 'You cannot reset a user with permissions you do not hold'; end if;
end;
$$;

create or replace function record_password_reset(p_user_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid := _require_manage_users();
begin
  perform authorize_password_reset(p_user_id);
  perform write_audit_log(v_org, 'user.password_reset', 'user', p_user_id, null, null, null, 'Temporary password set by administrator');
end;
$$;

-- ----------------------------------------------------------------------------
-- 8. Roles & permission matrix
-- ----------------------------------------------------------------------------
create or replace function _require_manage_roles() returns uuid
language plpgsql stable security definer set search_path = public as $$
declare v_org uuid := auth_organization_id();
begin
  if auth.uid() is null or v_org is null then raise exception 'Not authenticated'; end if;
  if not auth_has_permission('manage_roles') then raise exception 'Permission denied: manage_roles required'; end if;
  return v_org;
end;
$$;
revoke execute on function _require_manage_roles() from public, anon, authenticated;

create or replace function create_role(p_code text, p_name text, p_description text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_org uuid := _require_manage_roles(); v_id uuid;
begin
  if p_code !~ '^[a-z][a-z0-9_]{2,40}$' then
    raise exception 'Role code must be 3-41 characters: lowercase letters, digits, underscores, starting with a letter';
  end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'Role name is required'; end if;
  insert into roles (organization_id, code, name, description)
  values (v_org, p_code, trim(p_name), nullif(trim(p_description), '')) returning id into v_id;
  perform write_audit_log(v_org, 'role.create', 'role', v_id, null, null,
    jsonb_build_object('code', p_code, 'name', trim(p_name)), null);
  return v_id;
end;
$$;

create or replace function update_role(p_role_id uuid, p_name text, p_description text)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid := _require_manage_roles();
begin
  if not exists (select 1 from roles where id = p_role_id and organization_id = v_org) then raise exception 'Role not found'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'Role name is required'; end if;
  update roles set name = trim(p_name), description = nullif(trim(p_description), ''), updated_at = now() where id = p_role_id;
  perform write_audit_log(v_org, 'role.update', 'role', p_role_id, null, null,
    jsonb_build_object('name', trim(p_name)), null);
end;
$$;

create or replace function set_role_permission(p_role_id uuid, p_permission_code text, p_granted boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_org uuid := _require_manage_roles(); v_role roles%rowtype; v_perm uuid;
begin
  select * into v_role from roles where id = p_role_id and organization_id = v_org;
  if not found then raise exception 'Role not found'; end if;
  if v_role.code = 'system_admin' then raise exception 'The System Administrator role is locked'; end if;
  select id into v_perm from permissions where code = p_permission_code;
  if v_perm is null then raise exception 'Unknown permission'; end if;
  if not auth_has_permission(p_permission_code) then
    raise exception 'You cannot grant or revoke a permission you do not hold yourself';
  end if;

  if p_granted then
    insert into role_permissions (role_id, permission_id) values (p_role_id, v_perm) on conflict do nothing;
  else
    delete from role_permissions where role_id = p_role_id and permission_id = v_perm;
  end if;
  perform write_audit_log(v_org, case when p_granted then 'role.permission_grant' else 'role.permission_revoke' end,
    'role', p_role_id, null, null, jsonb_build_object('permission', p_permission_code), null);
end;
$$;

-- Grants: only the intended entry points are callable by signed-in users.
revoke execute on function admin_list_users(), authorize_user_creation(uuid, uuid),
  finalize_user_creation(uuid, text, text, text, uuid, uuid), update_user_profile(uuid, text, text),
  assign_user_role(uuid, uuid, uuid), remove_user_role(uuid), set_user_active(uuid, boolean, text),
  authorize_password_reset(uuid), record_password_reset(uuid), create_role(text, text, text),
  update_role(uuid, text, text), set_role_permission(uuid, text, boolean) from public, anon;
grant execute on function admin_list_users(), authorize_user_creation(uuid, uuid),
  finalize_user_creation(uuid, text, text, text, uuid, uuid), update_user_profile(uuid, text, text),
  assign_user_role(uuid, uuid, uuid), remove_user_role(uuid), set_user_active(uuid, boolean, text),
  authorize_password_reset(uuid), record_password_reset(uuid), create_role(text, text, text),
  update_role(uuid, text, text), set_role_permission(uuid, text, boolean) to authenticated;
