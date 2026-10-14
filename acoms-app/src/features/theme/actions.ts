"use server";

import { createClient } from "@/lib/supabase/server";
import { isThemePreference } from "./theme";

// Best-effort: the local preference already applied the theme, so a failure here
// (for example before migration 024 is applied) must never block the user.
export async function saveThemePreference(pref: string): Promise<{ success: boolean }> {
  if (!isThemePreference(pref)) return { success: false };
  const supabase = await createClient();
  const { error } = await supabase.rpc("set_my_theme_preference", { p_theme: pref });
  return { success: !error };
}
