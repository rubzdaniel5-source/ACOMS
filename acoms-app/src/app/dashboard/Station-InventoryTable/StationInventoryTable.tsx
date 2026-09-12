"use client";

import { useMemo, useState } from "react";
import Link from "next/link";

interface Row {
  station_code: string;
  station_name: string;
  source_code: string;
  equipment_name: string;
  current_stock: number;
  minimum_level: number | null;
  variance: number;
  status: string;
}

const STATUS_TAG: Record<string, string> = {
  CRITICAL_SHORTAGE: "tag-brick",
  SHORTAGE: "tag-amber",
  NORMAL: "tag-teal",
  SURPLUS: "tag-navy",
  CRITICAL_SURPLUS: "tag-brick",
  NO_THRESHOLD_SET: "tag-neutral",
  NO_DATA: "tag-neutral",
};

export function StationInventoryTable({ rows }: { rows: Row[] }) {
  const [station, setStation] = useState("All");
  const [equipment, setEquipment] = useState("All");
  const [status, setStatus] = useState("All");

  const stations = useMemo(() => Array.from(new Set(rows.map((r) => r.station_code))).sort(), [rows]);
  const equipmentNames = useMemo(() => Array.from(new Set(rows.map((r) => r.equipment_name))).sort(), [rows]);
  const statuses = useMemo(() => Array.from(new Set(rows.map((r) => r.status))), [rows]);

  const filtered = rows.filter(
    (r) =>
      (station === "All" || r.station_code === station) &&
      (equipment === "All" || r.equipment_name === equipment) &&
      (status === "All" || r.status === status)
  );

  return (
    <>
      <div className="mb-4 flex flex-wrap gap-3">
        <select value={station} onChange={(e) => setStation(e.target.value)} className="rounded-md border border-(--border) px-3 py-1.5 text-sm">
          <option>All</option>
          {stations.map((s) => <option key={s}>{s}</option>)}
        </select>
        <select value={equipment} onChange={(e) => setEquipment(e.target.value)} className="rounded-md border border-(--border) px-3 py-1.5 text-sm">
          <option>All</option>
          {equipmentNames.map((e) => <option key={e}>{e}</option>)}
        </select>
        <select value={status} onChange={(e) => setStatus(e.target.value)} className="rounded-md border border-(--border) px-3 py-1.5 text-sm">
          <option>All</option>
          {statuses.map((s) => <option key={s}>{s.replace(/_/g, " ")}</option>)}
        </select>
      </div>

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
            {filtered.map((r, i) => (
              <tr key={i}>
                <td className="id-code px-3 py-2 text-(--navy)">{r.station_code}</td>
                <td className="px-3 py-2"><span className="id-code">{r.source_code}</span> {r.equipment_name}</td>
                <td className="id-code px-3 py-2 text-right">{r.current_stock}</td>
                <td className="id-code px-3 py-2 text-right">{r.minimum_level ?? "—"}</td>
                <td className={`id-code px-3 py-2 text-right ${r.variance < 0 ? "text-(--brick)" : "text-(--teal)"}`}>
                  {r.variance > 0 ? "+" : ""}{r.variance}
                </td>
                <td className="px-3 py-2"><span className={`tag ${STATUS_TAG[r.status] ?? "tag-neutral"}`}>{r.status.replace(/_/g, " ")}</span></td>
                <td className="px-3 py-2">
                  {(r.status === "CRITICAL_SHORTAGE" || r.status === "SHORTAGE") && (
                    <Link href="/transfers/new" className="text-xs font-semibold text-(--navy) hover:underline">Request Transfer</Link>
                  )}
                </td>
              </tr>
            ))}
            {filtered.length === 0 && (
              <tr><td colSpan={7} className="px-3 py-6 text-center text-(--steel)">No matching rows.</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </>
  );
}
