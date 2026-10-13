"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";

type Result = { ok: true; message?: string } | { ok: false; error: string };

const fail = (e: unknown): Result => ({ ok: false, error: e instanceof Error ? e.message : "Something went wrong" });

function validPassword(pw: unknown): pw is string {
  return typeof pw === "string" && pw.length >= 10 && !/^\d+$/.test(pw);
}

export async function createUser(input: {
  fullName: string;
  email: string;
  affiliation: string;
  roleId: string;
  stationId: string | null;
  password: string;
}): Promise<Result> {
  try {
    const email = String(input.email ?? "").trim().toLowerCase();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return { ok: false, error: "Enter a valid email address." };
    if (!validPassword(input.password)) return { ok: false, error: "Temporary password must be at least 10 characters and not only digits." };

    const supabase = await createClient();
    // 1. Authorise BEFORE touching the service role.
    const auth = await supabase.rpc("authorize_user_creation", { p_role_id: input.roleId, p_station_id: input.stationId });
    if (auth.error) return { ok: false, error: auth.error.message };

    // 2. Create the auth user with a temporary password and the forced-change flag.
    const admin = createAdminClient();
    const created = await admin.auth.admin.createUser({
      email,
      password: input.password,
      email_confirm: true,
      app_metadata: { must_change_password: true },
    });
    if (created.error || !created.data.user) return { ok: false, error: created.error?.message ?? "Could not create the login." };
    const newId = created.data.user.id;

    // 3. Finalise profile + role in the caller's session (so the audit log has the actor).
    const fin = await supabase.rpc("finalize_user_creation", {
      p_user_id: newId,
      p_full_name: input.fullName,
      p_email: email,
      p_affiliation: input.affiliation,
      p_role_id: input.roleId,
      p_station_id: input.stationId,
    });
    if (fin.error) {
      await admin.auth.admin.deleteUser(newId); // roll back the orphan login
      return { ok: false, error: fin.error.message };
    }
    revalidatePath("/admin/users");
    return { ok: true, message: newId };
  } catch (e) {
    return fail(e);
  }
}

export async function resetPassword(userId: string, password: string): Promise<Result> {
  try {
    if (!validPassword(password)) return { ok: false, error: "Temporary password must be at least 10 characters and not only digits." };
    const supabase = await createClient();
    const auth = await supabase.rpc("authorize_password_reset", { p_user_id: userId });
    if (auth.error) return { ok: false, error: auth.error.message };

    const admin = createAdminClient();
    const upd = await admin.auth.admin.updateUserById(userId, {
      password,
      app_metadata: { must_change_password: true },
    });
    if (upd.error) return { ok: false, error: upd.error.message };

    const rec = await supabase.rpc("record_password_reset", { p_user_id: userId });
    if (rec.error) return { ok: false, error: rec.error.message };
    revalidatePath(`/admin/users/${userId}`);
    return { ok: true };
  } catch (e) {
    return fail(e);
  }
}

export async function setUserActive(userId: string, active: boolean, reason: string): Promise<Result> {
  try {
    const supabase = await createClient();
    const res = await supabase.rpc("set_user_active", { p_user_id: userId, p_active: active, p_reason: reason || null });
    if (res.error) return { ok: false, error: res.error.message };

    // Also block sign-in at the auth layer (the database already denies all access).
    const admin = createAdminClient();
    const ban = await admin.auth.admin.updateUserById(userId, { ban_duration: active ? "none" : "876000h" });
    if (ban.error) return { ok: false, error: `Access was removed in ACOMS, but the login ban failed: ${ban.error.message}` };

    revalidatePath("/admin/users");
    revalidatePath(`/admin/users/${userId}`);
    return { ok: true };
  } catch (e) {
    return fail(e);
  }
}

export async function updateProfile(userId: string, fullName: string, affiliation: string): Promise<Result> {
  const supabase = await createClient();
  const res = await supabase.rpc("update_user_profile", { p_user_id: userId, p_full_name: fullName, p_affiliation: affiliation });
  if (res.error) return { ok: false, error: res.error.message };
  revalidatePath(`/admin/users/${userId}`);
  revalidatePath("/admin/users");
  return { ok: true };
}

export async function assignRole(userId: string, roleId: string, stationId: string | null): Promise<Result> {
  const supabase = await createClient();
  const res = await supabase.rpc("assign_user_role", { p_user_id: userId, p_role_id: roleId, p_station_id: stationId });
  if (res.error) return { ok: false, error: res.error.message };
  revalidatePath(`/admin/users/${userId}`);
  revalidatePath("/admin/users");
  return { ok: true };
}

export async function removeRole(userId: string, userRoleId: string): Promise<Result> {
  const supabase = await createClient();
  const res = await supabase.rpc("remove_user_role", { p_user_role_id: userRoleId });
  if (res.error) return { ok: false, error: res.error.message };
  revalidatePath(`/admin/users/${userId}`);
  revalidatePath("/admin/users");
  return { ok: true };
}
