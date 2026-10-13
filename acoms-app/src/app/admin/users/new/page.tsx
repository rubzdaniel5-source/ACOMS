import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { requireAnyPermission } from "@/features/admin/access";
import { getRolesWithPermissions } from "@/features/admin/roles";
import { NewUserForm } from "./NewUserForm";

export default async function NewUserPage() {
  const perms = await requireAnyPermission(["manage_users"]);
  const supabase = await createClient();
  const [roles, stations] = await Promise.all([
    getRolesWithPermissions(perms),
    supabase.from("stations").select("id, code, name").eq("is_active", true).order("code"),
  ]);

  return (
    <div>
      <Link href="/admin/users" className="mb-4 inline-block text-sm text-(--steel) hover:text-(--navy)">← Back to Users</Link>
      <h1 className="mb-1 text-xl font-semibold text-(--navy)">New user</h1>
      <p className="mb-6 text-sm text-(--steel)">The user must choose their own password the first time they sign in.</p>
      <NewUserForm roles={roles.filter((r) => r.assignable)} stations={(stations.data ?? []) as any} />
    </div>
  );
}
