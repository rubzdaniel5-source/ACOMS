import { redirect } from "next/navigation";
import { getCurrentUserPermissions } from "@/features/auth/permissions";
import { canEnterAdmin, visibleSections } from "@/features/admin/access";
import { AdminSubNav } from "./AdminSubNav";

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const perms = await getCurrentUserPermissions();
  if (!canEnterAdmin(perms)) redirect("/dashboard");

  const sections = visibleSections(perms).map((s) => ({ href: s.href, label: s.label }));

  return (
    <div className="mx-auto flex w-full max-w-6xl flex-1 flex-col gap-4 px-4 py-6 md:flex-row md:gap-8 md:py-8">
      <aside className="min-w-0 md:w-48 md:shrink-0">
        <h2 className="mb-2 text-xs font-semibold text-(--steel) md:mb-3">Administration</h2>
        <AdminSubNav sections={sections} />
      </aside>
      <div className="min-w-0 flex-1">{children}</div>
    </div>
  );
}
