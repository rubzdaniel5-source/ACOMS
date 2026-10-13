import { redirect } from "next/navigation";
import { getCurrentUserPermissions } from "@/features/auth/permissions";
import { canEnterAdmin, visibleSections } from "@/features/admin/access";
import { AdminSubNav } from "./AdminSubNav";

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const perms = await getCurrentUserPermissions();
  if (!canEnterAdmin(perms)) redirect("/dashboard");

  const sections = visibleSections(perms).map((s) => ({ href: s.href, label: s.label }));

  return (
    <div className="mx-auto flex w-full max-w-6xl flex-1 gap-8 px-4 py-8">
      <aside className="w-48 shrink-0">
        <h2 className="mb-3 text-xs font-semibold uppercase tracking-wide text-(--steel)">Administration</h2>
        <AdminSubNav sections={sections} />
      </aside>
      <div className="min-w-0 flex-1">{children}</div>
    </div>
  );
}
