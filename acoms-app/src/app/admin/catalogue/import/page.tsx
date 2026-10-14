import Link from "next/link";
import { requireAnyPermission } from "@/features/admin/access";
import { ImportWizard } from "./ImportWizard";

export default async function ImportPage() {
  await requireAnyPermission(["manage_catalogue"]);
  return (
    <div>
      <Link href="/admin/catalogue" className="mb-4 inline-block text-sm text-(--steel) hover:text-(--navy)">← Back to catalogue</Link>
      <h1 className="mb-1 text-xl font-semibold text-(--navy)">Import equipment from CSV</h1>
      <p className="mb-6 text-sm text-(--steel)">
        Existing codes are updated, new codes are created. Blank cells leave the current value unchanged.
        Nothing is saved until you confirm the preview, and a single bad row cancels the whole import.
      </p>
      <ImportWizard />
    </div>
  );
}
