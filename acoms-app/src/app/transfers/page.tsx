import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { TransferStatusBadge } from "@/components/ui/TransferStatusBadge";
import type { EquipmentTransfer } from "@/types/transfers";

export default async function TransfersPage() {
  const supabase = await createClient();

  const { data: transfers, error } = await supabase
    .from("equipment_transfers")
    .select(
      "id, transfer_number, status, priority, reason, requested_at, from_station:from_station_id(id, code, name), to_station:to_station_id(id, code, name)"
    )
    .order("requested_at", { ascending: false })
    .limit(50);

  return (
    <div className="mx-auto max-w-5xl px-4 py-8">
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-(--navy)">Equipment Transfers</h1>
          <p className="text-sm text-(--steel)">
            What&apos;s in transit, what needs action, what&apos;s recently moved.
          </p>
        </div>
        <Link href="/transfers/new" className="btn-primary px-4 py-2 text-sm">
          New Transfer
        </Link>
      </div>

      {error && (
        <div className="panel px-4 py-3 text-sm text-(--brick)" style={{ borderColor: "#E2BEBE" }}>
          {error.message}
        </div>
      )}

      {!error && (!transfers || transfers.length === 0) && (
        <div className="panel border-dashed px-6 py-12 text-center text-sm text-(--steel)">
          No transfers yet. Create the first one to get started.
        </div>
      )}

      {transfers && transfers.length > 0 && (
        <div className="panel overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-(--steel-light) text-left text-xs font-medium uppercase tracking-wide text-(--steel)">
              <tr>
                <th className="px-4 py-3">Transfer #</th>
                <th className="px-4 py-3">Route</th>
                <th className="px-4 py-3">Status</th>
                <th className="px-4 py-3">Priority</th>
                <th className="px-4 py-3">Requested</th>
              </tr>
            </thead>
            <tbody className="divide-y" style={{ borderColor: "var(--border)" }}>
              {(transfers as unknown as EquipmentTransfer[]).map((t) => (
                <tr key={t.id} className="hover:bg-(--steel-light)">
                  <td className="px-4 py-3">
                    <Link href={`/transfers/${t.id}`} className="id-code font-medium text-(--navy) hover:underline">
                      {t.transfer_number}
                    </Link>
                  </td>
                  <td className="id-code px-4 py-3 text-(--steel)">
                    {t.from_station?.code} → {t.to_station?.code}
                  </td>
                  <td className="px-4 py-3">
                    <TransferStatusBadge status={t.status} />
                  </td>
                  <td className="px-4 py-3 text-(--foreground)">{t.priority}</td>
                  <td className="id-code px-4 py-3 text-(--steel)">
                    {new Date(t.requested_at).toLocaleDateString()}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
