"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

type Result = { ok: true } | { ok: false; error: string };

function refresh() {
  revalidatePath("/admin/settings");
  revalidatePath("/dashboard", "layout");
}

export async function saveSetting(key: string, value: number, reason: string): Promise<Result> {
  if (!Number.isFinite(value)) return { ok: false, error: "Enter a number." };
  const supabase = await createClient();
  const { error } = await supabase.rpc("update_setting", { p_key: key, p_value: value, p_reason: reason || null });
  if (error) return { ok: false, error: error.message };
  refresh();
  return { ok: true };
}

export async function resetSetting(key: string): Promise<Result> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("reset_setting", { p_key: key, p_reason: "Reset to default" });
  if (error) return { ok: false, error: error.message };
  refresh();
  return { ok: true };
}
