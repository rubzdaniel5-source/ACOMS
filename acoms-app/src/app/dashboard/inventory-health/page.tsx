import Link from "next/link";
import { createClient } from "@/lib/supabase/server";

const STATUS_TAG: Record<string, string> = {
  CRITICAL_SHORTAGE: "tag-brick",
  SHORTAGE: "tag-amber",
  NORMAL: "tag-teal",
  SURPLUS: "tag-navy",
  CRITICAL_SURPLUS: "tag-brick",
  NO_THRESHOLD_SET: "tag-neutral",
  NO_DATA: "tag-neutral",
};

export default async function InventoryHealthPage() {
  const supabase = await createClient();
  const { data } = await supabase
    .from("v_inventory_health")
    .select("*")
    .in("status", ["CRITICAL_SHORTAGE", "SHORTAGE", "SURPLUS", "CRITICAL_SURPLUS"])
    .order("status");

  return (
    <div className="mx-auto max-w-6xl px-4 py-8">
      <Link href="/dashboard" className="mb-4 inline-block text-sm text-(--steel) hover:text-(--navy)">← Back to Dashboard</Link>
      <h1 className="mb-1 text-xl font-semibold text-(--navy)">Inventory Health</h1>
      <p className="mb-6 text-sm text-(--steel)">
        Stations/items outside the normal range. Reorder threshold ratios are provisional — see migration notes.
      </p>

      <div className="panel overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="bg-(--steel-light) text-left text-xs font-medium uppercase tracking-wide text-(--steel)">
            <tr>
              <th className="px-3 py-2">Station</th>
              <th className="px-3 py-2">Equipment</th>
              <th className="px-3 py-2 text-right">Current</th>
              <th className="px-3 py-2 text-right">Minimum</th>
              <th className="px-3 py-2 text-right">Variance</th>
              <th className="px-3 py-2">Status</th>
              <th className="px-3 py-2">Action</th>
            </tr>
          </thead>
          <tbody className="divide-y" style={{ borderColor: "var(--border)" }}>
            {(data ?? []).map((r: any, i: number) => (
              <tr key={i}>
                <td className="id-code px-3 py-2 text-(--navy)">{r.station_code}</td>
                <td className="px-3 py-2"><span className="id-code">{r.source_code}</span> {r.equipment_name}</td>
                <td className="id-code px-3 py-2 text-right">{r.current_stock}</td>
                <td className="id-code px-3 py-2 text-right">{r.minimum_level ?? "—"}</td>
                <td className={`id-code px-3 py-2 text-right ${r.variance < 0 ? "text-(--brick)" : "text-(--teal)"}`}>
                  {r.variance > 0 ? "+" : ""}{r.variance}
                </td>
                <td className="px-3 py-2"><span className={`tag ${STATUS_TAG[r.status]}`}>{r.status.replace(/_/g, " ")}</span></td>
                <td className="px-3 py-2">
                  {(r.status === "CRITICAL_SHORTAGE" || r.status === "SHORTAGE") && (
                    <Link href="/transfers/new" className="text-xs font-semibold text-(--navy) hover:underline">Request Transfer</Link>
                  )}
                  {(r.status === "SURPLUS" || r.status === "CRITICAL_SURPLUS") && (
                    <Link href="/transfers/new" className="text-xs font-semibold text-(--navy) hover:underline">Redistribute</Link>
                  )}
                </td>
              </tr>
            ))}
            {(!data || data.length === 0) && (
              <tr><td colSpan={7} className="px-3 py-6 text-center text-(--steel)">No stations outside normal range.</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
