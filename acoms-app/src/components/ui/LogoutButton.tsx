"use client";

import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export function LogoutButton() {
  const router = useRouter();

  async function handleLogout() {
    const supabase = createClient();
    await supabase.auth.signOut();
    router.push("/login");
    router.refresh();
  }

  return (
    <button
      onClick={handleLogout}
      className="inline-flex min-h-11 items-center rounded-md px-2 text-sm font-medium text-(--color-text-muted) hover:bg-(--color-surface-hover) hover:text-(--color-text)"
    >
      Log out
    </button>
  );
}
