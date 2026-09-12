import Link from "next/link";
import { createClient } from "@/lib/supabase/server";

export default async function EquipmentOverviewPage() {
  const supabase = await createClient();
  const { data } = await supabase
    .from("v_network_inventory_summary")
    .select("*")
    .order("source_code");

  return (
    <div className="mx-auto max-w-6xl px-4 py-8">
      <Link href="/dashboard" className="mb-4 inline-block text-sm text-(--steel) hover:text-(--navy)">← Back to Dashboard</Link>
      <h1 className="mb-1 text-xl font-semibold text-(--navy)">Equipment Overview</h1>
      <p className="mb-6 text-sm text-(--steel)">Network-wide position by equipment type.</p>

      <div className="panel overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="bg-(--steel-light) text-left text-xs font-medium uppercase tracking-wide text-(--steel)">
            <tr>
              <th className="px-3 py-2">Equipment</th>
              <th className="px-3 py-2">Category</th>
              <th className="px-3 py-2 text-right">Available</th>
              <th className="px-3 py-2 text-right">In Transit</th>
              <th className="px-3 py-2 text-right">Damaged</th>
              <th className="px-3 py-2 text-right">Missing</th>
            </tr>
          </thead>
          <tbody className="divide-y" style={{ borderColor: "var(--border)" }}>
            {(data ?? []).map((r: any, i: number) => (
              <tr key={i}>
                <td className="px-3 py-2"><span className="id-code">{r.source_code}</span> {r.name}</td>
                <td className="px-3 py-2 text-(--steel)">{r.category_name}</td>
                <td className="id-code px-3 py-2 text-right">{r.total_available}</td>
                <td className="id-code px-3 py-2 text-right">{r.total_in_transit}</td>
                <td className="id-code px-3 py-2 text-right">{r.total_damaged}</td>
                <td className="id-code px-3 py-2 text-right">{r.total_missing}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
