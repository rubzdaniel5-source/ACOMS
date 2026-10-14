import Link from "next/link";
import { createClient } from "@/lib/supabase/server";

const BUCKETS: Record<string, { col: string; label: string }> = {
  available: { col: "total_available", label: "Available units" },
  in_transit: { col: "total_in_transit", label: "Units in transit" },
  damaged: { col: "total_damaged", label: "Damaged units" },
  missing: { col: "total_missing", label: "Missing units" },
};

export default async function EquipmentOverviewPage({ searchParams }: { searchParams: Promise<{ bucket?: string }> }) {
  const { bucket } = await searchParams;
  const b = bucket ? BUCKETS[bucket] : undefined;
  const supabase = await createClient();
  let q = supabase.from("v_network_inventory_summary").select("*");
  q = b ? q.gt(b.col, 0).order(b.col, { ascending: false }) : q.order("source_code");
  const { data, error } = await q;

  return (
    <div className="mx-auto max-w-6xl px-4 py-8">
      <Link href="/dashboard" className="mb-4 inline-block text-sm text-(--steel) hover:text-(--navy)">← Back to Dashboard</Link>
      <h1 className="mb-1 text-xl font-semibold text-(--navy)">Equipment Overview</h1>
      <p className="mb-4 text-sm text-(--steel)">Network-wide position by equipment type, in units.</p>
      {b && (
        <p className="mb-4 flex flex-wrap items-center gap-3 text-sm text-(--color-text-muted)">
          Showing: <span className="tag tag-info">{b.label}, highest first</span>
          <Link href="/dashboard/equipment-overview" className="font-semibold text-(--color-primary) hover:underline">Show all equipment</Link>
        </p>
      )}
      {error && <div className="alert alert-danger mb-4" role="alert">Equipment figures could not be loaded. Refresh the page to try again.</div>}

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
            {!error && (data ?? []).length === 0 && (
              <tr><td colSpan={6} className="px-3 py-6 text-center text-(--color-text-muted)">No equipment matches this view.</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
