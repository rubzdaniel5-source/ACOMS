import { createClient } from "@/lib/supabase/server";

export type RoleRow = {
  id: string;
  code: string;
  name: string;
  description: string | null;
  permissions: string[];
  /** True when the current user holds every permission this role carries. */
  assignable: boolean;
};

export async function getRolesWithPermissions(myPerms: Set<string>): Promise<RoleRow[]> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("roles")
    .select("id, code, name, description, is_active, role_permissions(permissions(code))")
    .eq("is_active", true)
    .order("name");
  return ((data ?? []) as any[]).map((r) => {
    const permissions = (r.role_permissions ?? []).map((rp: any) => rp.permissions?.code).filter(Boolean) as string[];
    return {
      id: r.id,
      code: r.code,
      name: r.name,
      description: r.description,
      permissions,
      assignable: permissions.every((p) => myPerms.has(p)),
    };
  });
}
