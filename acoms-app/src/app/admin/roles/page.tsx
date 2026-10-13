import { createClient } from "@/lib/supabase/server";
import { requireAnyPermission } from "@/features/admin/access";
import { getRolesWithPermissions } from "@/features/admin/roles";
import { RoleMatrix } from "./RoleMatrix";

export default async function RolesPage() {
  const perms = await requireAnyPermission(["manage_roles", "manage_users"]);
  const supabase = await createClient();
  const [roles, permissions] = await Promise.all([
    getRolesWithPermissions(perms),
    supabase.from("permissions").select("code, description").order("code"),
  ]);

  return (
    <div>
      <h1 className="mb-1 text-xl font-semibold text-(--navy)">Roles and permissions</h1>
      <p className="mb-6 text-sm text-(--steel)">
        What each role is allowed to do. Changes apply immediately to everyone holding the role.
        You can only grant or revoke permissions you hold yourself, and the System Administrator role is locked.
      </p>
      <RoleMatrix
        roles={roles}
        permissions={(permissions.data ?? []) as any}
        myPerms={Array.from(perms)}
        canEdit={perms.has("manage_roles")}
      />
    </div>
  );
}
