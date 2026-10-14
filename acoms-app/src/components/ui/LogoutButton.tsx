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
      className="inline-flex min-h-11 items-center rounded-md px-2.5 text-sm font-medium text-(--color-header-text) sm:px-3 hover:bg-(--color-header-hover)"
    >
      Log out
    </button>
  );
}
