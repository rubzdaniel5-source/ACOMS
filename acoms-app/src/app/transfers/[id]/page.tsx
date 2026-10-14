import { createClient } from "@/lib/supabase/server";
import { TransferStatusBadge } from "@/components/ui/TransferStatusBadge";
import { getCurrentUserPermissions, getCurrentUserId } from "@/features/auth/permissions";
import { TransferActionPanel } from "@/features/transfers/TransferActionPanel";
import type { EquipmentTransfer, EquipmentTransferItem } from "@/types/transfers";

export default async function TransferDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();

  const [{ data: transfer, error }, { data: items }, permissions, currentUserId] = await Promise.all([
    supabase
      .from("equipment_transfers")
      .select(
        "*, from_station:from_station_id(id, code, name, station_type), to_station:to_station_id(id, code, name, station_type)"
      )
      .eq("id", id)
      .single(),
    supabase
      .from("equipment_transfer_items")
      .select("*, equipment_type:equipment_type_id(id, source_code, name, reconciliation_tolerance)")
      .eq("transfer_id", id),
    getCurrentUserPermissions(),
    getCurrentUserId(),
  ]);

  if (error || !transfer) {
    return (
      <div className="mx-auto max-w-3xl px-4 py-8">
        <p className="rounded-md bg-(--color-danger-soft) px-4 py-3 text-sm text-(--color-danger)">
          {error?.message ?? "Transfer not found."}
        </p>
      </div>
    );
  }

  const t = transfer as unknown as EquipmentTransfer;
  const transferItems = (items ?? []) as unknown as EquipmentTransferItem[];

  return (
    <div className="mx-auto max-w-3xl px-4 py-8">
      <div className="mb-6 flex items-start justify-between">
        <div>
          <h1 className="text-xl font-semibold text-(--color-text)">{t.transfer_number}</h1>
          <p className="text-sm text-(--color-text-subtle)">
            {t.from_station?.code} ({t.from_station?.name}) &rarr; {t.to_station?.code} ({t.to_station?.name})
          </p>
        </div>
        <TransferStatusBadge status={t.status} />
      </div>

      {t.reason && (
        <div className="mb-4 rounded-md bg-(--color-surface-subtle) px-4 py-3 text-sm text-(--color-text-muted)">
          <span className="font-medium">Reason: </span>
          {t.reason}
        </div>
      )}

      <div className="mb-6 overflow-hidden rounded-lg border border-(--color-border)">
        <table className="w-full text-sm">
          <thead className="bg-(--color-surface-subtle) text-left text-xs font-medium uppercase tracking-wide text-(--color-text-subtle)">
            <tr>
              <th className="px-4 py-2">Equipment</th>
              <th className="px-4 py-2">Requested</th>
              <th className="px-4 py-2">Approved</th>
              <th className="px-4 py-2">Dispatched</th>
              <th className="px-4 py-2">Received</th>
              <th className="px-4 py-2">Damaged</th>
              <th className="px-4 py-2">Missing</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-(--color-border)">
            {transferItems.map((item) => (
              <tr key={item.id}>
                <td className="px-4 py-2">
                  <div className="font-medium text-(--color-text)">{item.equipment_type?.source_code}</div>
                  <div className="text-xs text-(--color-text-subtle)">{item.equipment_type?.name}</div>
                </td>
                <td className="px-4 py-2">{item.quantity_requested}</td>
                <td className="px-4 py-2">{item.quantity_approved ?? "—"}</td>
                <td className="px-4 py-2">{item.quantity_dispatched ?? "—"}</td>
                <td className="px-4 py-2">{item.quantity_received ?? "—"}</td>
                <td className="px-4 py-2">{item.quantity_damaged || "—"}</td>
                <td className="px-4 py-2">{item.quantity_missing || "—"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <TransferActionPanel
        transfer={t}
        items={transferItems}
        permissions={Array.from(permissions)}
        currentUserId={currentUserId}
      />
    </div>
  );
}
