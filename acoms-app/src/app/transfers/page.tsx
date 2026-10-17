import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { TransferStatusBadge } from "@/components/ui/TransferStatusBadge";
import type { EquipmentTransfer } from "@/types/transfers";

const VIEW_LABEL: Record<string, string> = {
  REQUESTED: "Awaiting approval",
  APPROVED: "Awaiting dispatch",
  IN_TRANSIT: "In transit",
  PARTIALLY_RECEIVED: "Partly received",
  RECEIVED: "Awaiting reconciliation",
  RECONCILIATION: "Reconciled, pending close",
  DISCREPANCY: "Discrepancies",
  CLOSED: "Closed",
  receipt: "Awaiting receipt",
  open: "Requiring action",
};

export default async function TransfersPage({ searchParams }: { searchParams: Promise<{ status?: string }> }) {
  const { status } = await searchParams;
  const supabase = await createClient();

  let query = supabase
    .from("equipment_transfers")
    .select(
      "id, transfer_number, status, priority, reason, requested_at, from_station:from_station_id(id, code, name), to_station:to_station_id(id, code, name)"
    )
    .order("requested_at", { ascending: false })
    .limit(50);
  if (status === "open") query = query.not("status", "in", "(CLOSED,REJECTED,CANCELLED)");
  else if (status === "receipt") query = query.in("status", ["IN_TRANSIT", "PARTIALLY_RECEIVED"]);
  else if (status && VIEW_LABEL[status]) query = query.eq("status", status);
  const { data: transfers, error } = await query;

  return (
    <div className="mx-auto w-full max-w-7xl px-3 py-6 sm:px-6">
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-(--navy)">Equipment Transfers</h1>
          <p className="text-sm text-(--steel)">
            What&apos;s in transit, what needs action, what&apos;s recently moved.
          </p>
        </div>
        <div className="flex gap-3">
          <Link href="/exchanges" className="btn-secondary px-4 py-2 text-sm">Exchanges</Link>
          <Link href="/transfers/new" className="btn-primary px-4 py-2 text-sm">
            New Transfer
          </Link>
        </div>
      </div>

      {status && VIEW_LABEL[status] && (
        <p className="mb-4 flex flex-wrap items-center gap-3 text-sm text-(--color-text-muted)">
          Showing: <span className="tag tag-info">{VIEW_LABEL[status]}</span>
          <Link href="/transfers" className="font-semibold text-(--color-primary) hover:underline">Show all transfers</Link>
        </p>
      )}

      {error && (
        <div className="panel px-4 py-3 text-sm text-(--brick)" style={{ borderColor: "var(--color-danger)" }}>
          {error.message}
        </div>
      )}

      {!error && (!transfers || transfers.length === 0) && (
        <div className="panel border-dashed px-6 py-12 text-center text-sm text-(--steel)">
          No transfers yet. Create the first one to get started.
        </div>
      )}

      {transfers && transfers.length > 0 && (
        <div className="panel overflow-x-auto">
          <table className="w-full min-w-[640px] text-sm">
            <thead className="bg-(--steel-light) text-left text-sm font-medium text-(--steel)">
              <tr>
                <th className="px-4 py-3">Transfer #</th>
                <th className="px-4 py-3">Route</th>
                <th className="px-4 py-3">Status</th>
                <th className="px-4 py-3">Priority</th>
                <th className="px-4 py-3">Requested</th>
              </tr>
            </thead>
            <tbody className="divide-y">
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
