"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

type Result = { ok: true } | { ok: false; error: string };

export async function createRole(code: string, name: string, description: string): Promise<Result> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("create_role", { p_code: code, p_name: name, p_description: description || null });
  if (error) return { ok: false, error: error.message };
  revalidatePath("/admin/roles");
  return { ok: true };
}

export async function setRolePermission(roleId: string, permissionCode: string, granted: boolean): Promise<Result> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("set_role_permission", { p_role_id: roleId, p_permission_code: permissionCode, p_granted: granted });
  if (error) return { ok: false, error: error.message };
  revalidatePath("/admin/roles");
  return { ok: true };
}
