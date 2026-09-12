import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { TransferStatusBadge } from "@/components/ui/TransferStatusBadge";

export default async function MovementPage() {
  const supabase = await createClient();
  const { data } = await supabase
    .from("equipment_transfers")
    .select("id, transfer_number, status, priority, requested_at, from_station:from_station_id(code), to_station:to_station_id(code)")
    .not("status", "in", "(CLOSED,REJECTED,CANCELLED)")
    .order("requested_at", { ascending: false });

  return (
    <div className="mx-auto max-w-6xl px-4 py-8">
      <Link href="/dashboard" className="mb-4 inline-block text-sm text-(--steel) hover:text-(--navy)">← Back to Dashboard</Link>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-(--navy)">Equipment Movement &amp; Exchange</h1>
          <p className="text-sm text-(--steel)">All transfers currently requiring action.</p>
        </div>
        <Link href="/transfers/new" className="btn-primary px-4 py-2 text-sm">+ New Equipment Transfer Request</Link>
      </div>

      <div className="panel overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-(--steel-light) text-left text-xs font-medium uppercase tracking-wide text-(--steel)">
            <tr>
              <th className="px-3 py-2">Transfer</th>
              <th className="px-3 py-2">Route</th>
              <th className="px-3 py-2">Status</th>
              <th className="px-3 py-2">Priority</th>
            </tr>
          </thead>
          <tbody className="divide-y" style={{ borderColor: "var(--border)" }}>
            {(data ?? []).map((t: any) => (
              <tr key={t.id}>
                <td className="px-3 py-2"><Link href={`/transfers/${t.id}`} className="id-code font-medium text-(--navy) hover:underline">{t.transfer_number}</Link></td>
                <td className="id-code px-3 py-2 text-(--steel)">{t.from_station?.code} → {t.to_station?.code}</td>
                <td className="px-3 py-2"><TransferStatusBadge status={t.status} /></td>
                <td className="px-3 py-2">{t.priority}</td>
              </tr>
            ))}
            {(!data || data.length === 0) && (
              <tr><td colSpan={4} className="px-3 py-6 text-center text-(--steel)">No transfers requiring action.</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
