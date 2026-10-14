import { requireAnyPermission } from "@/features/admin/access";
import { IntegrityRunner } from "./IntegrityRunner";

export default async function IntegrityPage() {
  await requireAnyPermission(["manage_configuration"]);
  return (
    <div>
      <h1 className="mb-1 text-xl font-semibold text-(--navy)">Integrity check</h1>
      <p className="mb-6 text-sm text-(--steel)">
        Proves that every stock figure can be explained by the records behind it: ledger, damage and loss reports, and open transfers.
        Each run is recorded in the audit log.
      </p>
      <IntegrityRunner />
    </div>
  );
}
