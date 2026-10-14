import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { requireAnyPermission } from "@/features/admin/access";
import { getRolesWithPermissions } from "@/features/admin/roles";
import { getCurrentUserId } from "@/features/auth/permissions";
import { UserDetailPanel } from "./UserDetailPanel";

export default async function UserDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const perms = await requireAnyPermission(["manage_users"]);
  const supabase = await createClient();
  const me = await getCurrentUserId();

  const [users, roles, stations, history] = await Promise.all([
    supabase.rpc("admin_list_users"),
    getRolesWithPermissions(perms),
    supabase.from("stations").select("id, code, name").eq("is_active", true).order("code"),
    supabase.from("audit_logs").select("id, created_at, action, actor_label, reason").eq("entity_type", "user").eq("entity_id", id).order("created_at", { ascending: false }).limit(15),
  ]);
  const user = ((users.data ?? []) as any[]).find((u) => u.id === id);
  if (!user) notFound();

  return (
    <div>
      <Link href="/admin/users" className="mb-4 inline-block text-sm text-(--steel) hover:text-(--navy)">← Back to Users</Link>
      <UserDetailPanel
        user={user}
        isSelf={me === id}
        roles={roles.filter((r) => r.assignable).map((r) => ({ id: r.id, name: r.name }))}
        stations={(stations.data ?? []) as any}
      />
      <h2 className="mb-2 mt-8 text-sm font-semibold text-(--steel)">Recent changes</h2>
      <div className="panel">
        {(history.data ?? []).length === 0 && <p className="p-4 text-sm text-(--steel)">No recorded changes.</p>}
        {((history.data ?? []) as any[]).map((h) => (
          <div key={h.id} className="flex justify-between gap-4 border-t border-(--border) p-3 text-sm first:border-t-0">
            <span><span className="id-code">{h.action}</span>{h.reason ? <span className="text-(--steel)"> — {h.reason}</span> : null}</span>
            <span className="whitespace-nowrap text-(--steel)">{h.actor_label ?? "System"} · {new Date(h.created_at).toLocaleString("en-GB", { dateStyle: "short", timeStyle: "short" })}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
