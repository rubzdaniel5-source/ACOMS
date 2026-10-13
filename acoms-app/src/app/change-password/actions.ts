"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";

export async function changePassword(newPassword: string): Promise<{ error: string } | void> {
  if (typeof newPassword !== "string" || newPassword.length < 10) {
    return { error: "Password must be at least 10 characters." };
  }
  if (/^\d+$/.test(newPassword)) return { error: "Password cannot be only digits." };

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Your session has expired. Please sign in again." };

  const { error } = await supabase.auth.updateUser({ password: newPassword });
  if (error) return { error: error.message };

  // Clear the forced-change flag. app_metadata can only be written with the
  // service role, so users cannot clear it themselves.
  try {
    const admin = createAdminClient();
    const { error: metaError } = await admin.auth.admin.updateUserById(user.id, {
      app_metadata: { must_change_password: false },
    });
    if (metaError) return { error: metaError.message };
  } catch (e: any) {
    return { error: e.message ?? "Could not finish the password change." };
  }

  await supabase.auth.refreshSession();
  redirect("/dashboard");
}
