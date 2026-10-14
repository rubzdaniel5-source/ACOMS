"use client";

import Link from "next/link";
import { useState } from "react";
import { ExportCsvButton } from "@/components/ui/ExportCsvButton";

type Row = {
  id: string; source_code: string; name: string; category: string; is_active: boolean;
  has_data_quality_flag: boolean; tracking_method: string; reorder_threshold: number | null;
  minimum_stock: number | null; target_stock: number | null; maximum_stock: number | null;
  reconciliation_tolerance: number; unit_of_measure: string;
};

export function CatalogueTable({ rows }: { rows: Row[] }) {
  const [q, setQ] = useState("");
  const [cat, setCat] = useState("");
  const [status, setStatus] = useState("active");
  const categories = Array.from(new Set(rows.map((r) => r.category))).sort();

  const shown = rows.filter((r) => {
    if (status === "active" && !r.is_active) return false;
    if (status === "inactive" && r.is_active) return false;
    if (status === "flagged" && !r.has_data_quality_flag) return false;
    if (cat && r.category !== cat) return false;
    const t = q.trim().toLowerCase();
    return !t || r.name.toLowerCase().includes(t) || r.source_code.toLowerCase().includes(t);
  });

  return (
    <div>
      <div className="mb-3 flex flex-wrap items-center gap-3">
        <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search name or code" className="w-full max-w-xs rounded-sm border border-(--border) px-3 py-2 text-sm" />
        <select value={cat} onChange={(e) => setCat(e.target.value)} className="rounded-sm border border-(--border) px-3 py-2 text-sm">
          <option value="">All categories</option>
          {categories.map((c) => <option key={c}>{c}</option>)}
        </select>
        <select value={status} onChange={(e) => setStatus(e.target.value)} className="rounded-sm border border-(--border) px-3 py-2 text-sm">
          <option value="active">Active</option><option value="inactive">Inactive</option>
          <option value="flagged">Needs review</option><option value="all">All</option>
        </select>
        <ExportCsvButton filename="equipment-catalogue.csv"
          rows={shown.map((r) => ({
            source_code: r.source_code, name: r.name, category: r.category, unit_of_measure: r.unit_of_measure,
            tracking_method: r.tracking_method, reorder_threshold: r.reorder_threshold, minimum_stock: r.minimum_stock,
            target_stock: r.target_stock, maximum_stock: r.maximum_stock, reconciliation_tolerance: r.reconciliation_tolerance,
          }))} />
      </div>
      <div className="panel overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="text-left text-xs uppercase text-(--steel)">
            <tr><th className="p-3">Code</th><th className="p-3">Name</th><th className="p-3">Category</th>
              <th className="p-3 text-right">Reorder at</th><th className="p-3 text-right">Tolerance</th><th className="p-3">Status</th></tr>
          </thead>
          <tbody>
            {shown.length === 0 && <tr><td colSpan={6} className="p-6 text-center text-(--steel)">Nothing matches.</td></tr>}
            {shown.map((r) => (
              <tr key={r.id} className="border-t border-(--border)">
                <td className="id-code p-3">{r.source_code}</td>
                <td className="p-3"><Link href={`/admin/catalogue/${r.id}`} className="font-medium text-(--navy) hover:underline">{r.name}</Link></td>
                <td className="p-3 text-(--steel)">{r.category}</td>
                <td className="p-3 text-right">{r.reorder_threshold ?? "—"}</td>
                <td className="p-3 text-right">±{r.reconciliation_tolerance}</td>
                <td className="p-3">
                  {!r.is_active ? <span className="tag tag-brick">Inactive</span>
                    : r.has_data_quality_flag ? <span className="tag tag-amber">Needs review</span>
                    : <span className="tag tag-teal">Active</span>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="mt-2 text-xs text-(--steel)">{shown.length} of {rows.length} items</p>
    </div>
  );
}
