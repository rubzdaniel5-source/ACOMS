import { createClient as createSupabaseClient } from "@supabase/supabase-js";

/**
 * Service-role client. SERVER ONLY — bypasses RLS entirely.
 * Used exclusively for Supabase Auth admin operations (create user, set
 * password, ban). Every caller must authorise the acting user through a
 * database function BEFORE using this client. Never import from a Client
 * Component, and never expose the key via a NEXT_PUBLIC_ variable.
 */
export function createAdminClient() {
  if (typeof window !== "undefined") throw new Error("Admin client must never run in the browser");
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) {
    throw new Error("SUPABASE_SERVICE_ROLE_KEY is not configured on the server. Add it in Vercel → Settings → Environment Variables, then redeploy.");
  }
  return createSupabaseClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, key, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}
