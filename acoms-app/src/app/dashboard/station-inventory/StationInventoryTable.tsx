"use client";

import { useMemo, useState } from "react";
import Link from "next/link";

export interface InventoryRow {
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
  SURPLUS: "tag-surplus",
  CRITICAL_SURPLUS: "tag-surplus",
  NO_THRESHOLD_SET: "tag-neutral",
  NO_DATA: "tag-neutral",
};

// Most urgent first; used for the default sort.
const SEVERITY = ["CRITICAL_SHORTAGE", "SHORTAGE", "CRITICAL_SURPLUS", "SURPLUS", "NORMAL", "NO_THRESHOLD_SET", "NO_DATA"];
const sev = (s: string) => {
  const i = SEVERITY.indexOf(s);
  return i === -1 ? SEVERITY.length : i;
};
const label = (s: string) => {
  const t = s.replace(/_/g, " ").toLowerCase();
  return t.charAt(0).toUpperCase() + t.slice(1);
};

type SortKey = "severity" | "station" | "equipment" | "current" | "minimum" | "variance";

export interface InitialFilters {
  station?: string;
  /** one or more statuses */
  statuses?: string[];
  q?: string;
}

export function StationInventoryTable({
  rows,
  canRequestTransfer,
  initial,
  pageSize = 10,
  detailsBase,
}: {
  rows: InventoryRow[];
  canRequestTransfer: boolean;
  initial?: InitialFilters;
  pageSize?: number;
  /** Where "View details" goes; the station and item code are added as filters. */
  detailsBase: string;
}) {
  const [station, setStation] = useState(initial?.station ?? "All");
  const [equipment, setEquipment] = useState("All");
  const [statusSel, setStatusSel] = useState(initial?.statuses?.length === 1 ? initial.statuses[0] : "All");
  const [multi, setMulti] = useState<string[] | null>(
    initial?.statuses && initial.statuses.length > 1 ? initial.statuses : null
  );
  const [q, setQ] = useState(initial?.q ?? "");
  const [sort, setSort] = useState<{ key: SortKey; dir: 1 | -1 }>({ key: "severity", dir: 1 });
  const [page, setPage] = useState(0);

  const stations = useMemo(() => Array.from(new Set(rows.map((r) => r.station_code))).sort(), [rows]);
  const equipmentNames = useMemo(() => Array.from(new Set(rows.map((r) => r.equipment_name))).sort(), [rows]);
  const statuses = useMemo(
    () => Array.from(new Set(rows.map((r) => r.status))).sort((a, b) => sev(a) - sev(b)),
    [rows]
  );

  const needle = q.trim().toLowerCase();
  const filtered = rows.filter(
    (r) =>
      (station === "All" || r.station_code === station) &&
      (equipment === "All" || r.equipment_name === equipment) &&
      (multi ? multi.includes(r.status) : statusSel === "All" || r.status === statusSel) &&
      (!needle ||
        r.station_code.toLowerCase().includes(needle) ||
        r.station_name.toLowerCase().includes(needle) ||
        r.source_code.toLowerCase().includes(needle) ||
        r.equipment_name.toLowerCase().includes(needle))
  );

  const sorted = [...filtered].sort((a, b) => {
    let c = 0;
    switch (sort.key) {
      case "severity": c = sev(a.status) - sev(b.status) || a.variance - b.variance; break;
      case "station": c = a.station_code.localeCompare(b.station_code); break;
      case "equipment": c = a.equipment_name.localeCompare(b.equipment_name); break;
      case "current": c = a.current_stock - b.current_stock; break;
      case "minimum": c = (a.minimum_level ?? -1) - (b.minimum_level ?? -1); break;
      case "variance": c = a.variance - b.variance; break;
    }
    return c * sort.dir;
  });

  const pages = Math.max(1, Math.ceil(sorted.length / pageSize));
  const cur = Math.min(page, pages - 1);
  const visible = sorted.slice(cur * pageSize, cur * pageSize + pageSize);
  const filtersActive = station !== "All" || equipment !== "All" || statusSel !== "All" || multi !== null || needle !== "";

  function clear() {
    setStation("All"); setEquipment("All"); setStatusSel("All"); setMulti(null); setQ(""); setPage(0);
  }
  function toggleSort(key: SortKey) {
    setSort((s) => (s.key === key ? { key, dir: (s.dir * -1) as 1 | -1 } : { key, dir: 1 }));
    setPage(0);
  }
  const ariaSort = (key: SortKey) => (sort.key === key ? (sort.dir === 1 ? "ascending" : "descending") : "none");
  const sortHead = (k: SortKey, text: string, right?: boolean) => (
    <th key={k} scope="col" aria-sort={ariaSort(k)} className={`px-3 py-2 ${right ? "text-right" : ""}`}>
      <button type="button" onClick={() => toggleSort(k)} className="inline-flex min-h-8 items-center gap-1 font-medium hover:text-(--color-text)">
        {text}
        <span aria-hidden="true" className="text-[10px]">{sort.key === k ? (sort.dir === 1 ? "▲" : "▼") : ""}</span>
      </button>
    </th>
  );

  const sel = "min-h-11 rounded-md px-3 py-1.5 text-sm";

  return (
    <>
      <div className="mb-3 grid grid-cols-2 gap-2 sm:flex sm:flex-wrap sm:items-end sm:gap-3">
        <label className="col-span-2 flex flex-col text-xs text-(--color-text-muted) sm:min-w-56">
          Search
          <input
            type="search"
            value={q}
            onChange={(e) => { setQ(e.target.value); setPage(0); }}
            placeholder="Station, item code or name"
            className={sel}
          />
        </label>
        <label className="flex flex-col text-xs text-(--color-text-muted)">
          Station
          <select value={station} onChange={(e) => { setStation(e.target.value); setPage(0); }} className={sel}>
            <option>All</option>
            {stations.map((s) => <option key={s}>{s}</option>)}
          </select>
        </label>
        <label className="flex flex-col text-xs text-(--color-text-muted)">
          Equipment
          <select value={equipment} onChange={(e) => { setEquipment(e.target.value); setPage(0); }} className={sel}>
            <option>All</option>
            {equipmentNames.map((e) => <option key={e}>{e}</option>)}
          </select>
        </label>
        <label className="flex flex-col text-xs text-(--color-text-muted)">
          Status
          <select
            value={multi ? "__multi" : statusSel}
            onChange={(e) => { setMulti(null); setStatusSel(e.target.value); setPage(0); }}
            className={sel}
          >
            <option>All</option>
            {multi && <option value="__multi">Needs attention</option>}
            {statuses.map((s) => <option key={s} value={s}>{label(s)}</option>)}
          </select>
        </label>
        <button type="button" onClick={clear} disabled={!filtersActive} className="btn-secondary min-h-11 px-4 text-sm">
          Clear filters
        </button>
      </div>

      <p className="mb-2 text-xs text-(--color-text-subtle)" role="status" aria-live="polite">
        {sorted.length} {sorted.length === 1 ? "row" : "rows"}. Variance is current stock minus minimum level, in units.
      </p>

      <div className="panel overflow-x-auto">
        <table className="w-full min-w-[720px] text-sm">
          <caption className="sr-only">Station inventory against minimum levels</caption>
          <thead className="bg-(--color-surface-subtle) text-left text-xs text-(--color-text-muted)">
            <tr>
              {sortHead("station", "Station")}
              {sortHead("equipment", "Equipment")}
              {sortHead("current", "Current stock", true)}
              {sortHead("minimum", "Minimum level", true)}
              {sortHead("variance", "Variance", true)}
              {sortHead("severity", "Status")}
              <th scope="col" className="px-3 py-2 font-medium">Action</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-(--color-border)">
            {visible.map((r, i) => {
              const short = r.status === "CRITICAL_SHORTAGE" || r.status === "SHORTAGE";
              const details = `${detailsBase}?station=${encodeURIComponent(r.station_code)}&q=${encodeURIComponent(r.source_code)}`;
              return (
                <tr key={`${r.station_code}-${r.source_code}-${i}`} className="hover:bg-(--color-surface-hover)">
                  <td className="id-code px-3 py-2 text-(--color-text)">{r.station_code}</td>
                  <td className="px-3 py-2"><span className="id-code">{r.source_code}</span> {r.equipment_name}</td>
                  <td className="id-code px-3 py-2 text-right">{r.current_stock}</td>
                  <td className="id-code px-3 py-2 text-right">{r.minimum_level ?? "—"}</td>
                  <td className={`id-code px-3 py-2 text-right ${r.minimum_level == null ? "" : r.variance < 0 ? "text-(--color-danger)" : ""}`}>
                    {r.minimum_level == null ? "—" : `${r.variance > 0 ? "+" : ""}${r.variance}`}
                  </td>
                  <td className="px-3 py-2"><span className={`tag ${STATUS_TAG[r.status] ?? "tag-neutral"}`}>{label(r.status)}</span></td>
                  <td className="px-3 py-2">
                    <div className="flex flex-wrap gap-x-3">
                      <Link href={details} className="inline-flex min-h-8 items-center text-xs font-semibold text-(--color-primary) hover:underline">
                        View details
                      </Link>
                      {short && canRequestTransfer && (
                        <Link href="/transfers/new" className="inline-flex min-h-8 items-center text-xs font-semibold text-(--color-primary) hover:underline">
                          Request transfer
                        </Link>
                      )}
                    </div>
                  </td>
                </tr>
              );
            })}
            {visible.length === 0 && (
              <tr>
                <td colSpan={7} className="px-3 py-6 text-center text-(--color-text-muted)">
                  {rows.length === 0 ? "No inventory records are available to you yet." : "No rows match these filters."}
                  {filtersActive && rows.length > 0 && (
                    <> <button type="button" onClick={clear} className="font-semibold text-(--color-primary) hover:underline">Clear filters</button></>
                  )}
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {pages > 1 && (
        <nav aria-label="Pagination" className="mt-3 flex items-center justify-between gap-3 text-sm">
          <button type="button" onClick={() => setPage(cur - 1)} disabled={cur === 0} className="btn-secondary min-h-11 px-4">Previous</button>
          <span className="text-(--color-text-muted)">Page {cur + 1} of {pages}</span>
          <button type="button" onClick={() => setPage(cur + 1)} disabled={cur >= pages - 1} className="btn-secondary min-h-11 px-4">Next</button>
        </nav>
      )}
    </>
  );
}
