import Link from "next/link";
import { getCurrentUserPermissions } from "@/features/auth/permissions";
import { visibleSections } from "@/features/admin/access";

export default async function AdminHome() {
  const perms = await getCurrentUserPermissions();
  const sections = visibleSections(perms);

  return (
    <div>
      <h1 className="mb-1 text-xl font-semibold text-(--navy)">Administration</h1>
      <p className="mb-6 text-sm text-(--steel)">Only the tools your role permits are shown here.</p>
      <div className="grid gap-4 sm:grid-cols-2">
        {sections.map((s) => (
          <Link key={s.href} href={s.href} className="panel block p-5 hover:border-(--navy)">
            <div className="mb-1 font-semibold text-(--navy)">{s.label}</div>
            <p className="text-sm text-(--steel)">{s.description}</p>
          </Link>
        ))}
      </div>
    </div>
  );
}
