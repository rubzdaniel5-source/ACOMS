import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { requireAnyPermission } from "@/features/admin/access";
import { UsersTable } from "./UsersTable";

export default async function UsersPage() {
  await requireAnyPermission(["manage_users"]);
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("admin_list_users");

  return (
    <div>
      <div className="mb-4 flex items-start justify-between gap-4">
        <div>
          <h1 className="mb-1 text-xl font-semibold text-(--navy)">Users</h1>
          <p className="text-sm text-(--steel)">Create accounts, assign roles and stations, reset passwords and deactivate leavers.</p>
        </div>
        <Link href="/admin/users/new" className="btn-primary whitespace-nowrap px-4 py-2 text-sm">New user</Link>
      </div>
      {error && <p className="mb-4 text-sm text-(--brick)">{error.message}</p>}
      <UsersTable users={(data ?? []) as any} />
    </div>
  );
}
