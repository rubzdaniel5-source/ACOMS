import { cache } from "react";
import { createClient } from "@/lib/supabase/server";

// One sign-in check per request. The layout and each page used to repeat it (a network call each time).
export const getCurrentUser = cache(async () => {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return user;
});

/**
 * Returns the set of permission codes the current user holds, across all
 * their role assignments. Used purely to decide which UI actions to SHOW —
 * the real enforcement is server-side in the SQL functions (see
 * migration 011). Never trust this alone for authorization decisions.
 */
export const getCurrentUserPermissions = cache(async (): Promise<Set<string>> => {
  const supabase = await createClient();
  const user = await getCurrentUser();

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
});

export async function getCurrentUserId(): Promise<string | null> {
  return (await getCurrentUser())?.id ?? null;
}
