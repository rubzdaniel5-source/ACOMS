import { createClient } from "@/lib/supabase/server";

/**
 * Returns the set of permission codes the current user holds, across all
 * their role assignments. Used purely to decide which UI actions to SHOW —
 * the real enforcement is server-side in the SQL functions (see
 * migration 011). Never trust this alone for authorization decisions.
 */
export async function getCurrentUserPermissions(): Promise<Set<string>> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return new Set();

  const { data, error } = await supabase
    .from("user_roles")
    .select("roles(role_permissions(permissions(code)))")
    .eq("user_id", user.id);

  if (error || !data) return new Set();

  const codes = new Set<string>();
  for (const row of data as any[]) {
    const perms = row.roles?.role_permissions ?? [];
    for (const rp of perms) {
      if (rp.permissions?.code) codes.add(rp.permissions.code);
    }
  }
  return codes;
}

export async function getCurrentUserId(): Promise<string | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return user?.id ?? null;
}
