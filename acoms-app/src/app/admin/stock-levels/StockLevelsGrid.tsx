"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { saveStationStockLevels } from "./actions";

type Eq = { id: string; source_code: string; name: string; reorder_threshold: number | null; minimum_stock: number | null; target_stock: number | null; maximum_stock: number | null };
type Ov = { equipment_type_id: string; reorder_threshold: number | null; minimum_stock: number | null; target_stock: number | null; maximum_stock: number | null };
const FIELDS = ["reorder_threshold", "minimum_stock", "target_stock", "maximum_stock"] as const;
const LABEL = { reorder_threshold: "Reorder at", minimum_stock: "Minimum", target_stock: "Target", maximum_stock: "Maximum" };
type Vals = Record<(typeof FIELDS)[number], string>;

export function StockLevelsGrid({ stationId, equipment, overrides }: { stationId: string; equipment: Eq[]; overrides: Ov[] }) {
  const router = useRouter();
  const ovMap = new Map(overrides.map((o) => [o.equipment_type_id, o]));
  const initial = (id: string): Vals => {
    const o = ovMap.get(id);
    return Object.fromEntries(FIELDS.map((f) => [f, o?.[f] == null ? "" : String(o[f])])) as Vals;
  };
  const [vals, setVals] = useState<Record<string, Vals>>(() => Object.fromEntries(equipment.map((e) => [e.id, initial(e.id)])));
  const [search, setSearch] = useState("");
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [pending, startTransition] = useTransition();

  const changed = equipment.filter((e) => FIELDS.some((f) => vals[e.id][f] !== initial(e.id)[f]));
  const q = search.trim().toLowerCase();
  const shown = equipment.filter((e) => !q || e.name.toLowerCase().includes(q) || e.source_code.toLowerCase().includes(q));

  function save() {
    setMsg(null);
    const items = changed.map((e) => ({
      equipment_type_id: e.id,
      ...(Object.fromEntries(FIELDS.map((f) => [f, vals[e.id][f].trim() === "" ? null : Number(vals[e.id][f])])) as any),
    }));
    startTransition(async () => {
      const r = await saveStationStockLevels(stationId, items);
      if (!r.ok) return setMsg({ ok: false, text: r.error });
      setMsg({ ok: true, text: `Saved ${r.count} item${r.count === 1 ? "" : "s"}.` });
      router.refresh();
    });
  }

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-3">
        <input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search equipment" className="w-full max-w-xs rounded-sm border border-(--border) px-3 py-2 text-sm" />
        <span className="text-sm text-(--steel)">{changed.length} unsaved change{changed.length === 1 ? "" : "s"}</span>
        <button className="btn-primary px-4 py-2 text-sm" disabled={pending || changed.length === 0} onClick={save}>{pending ? "Saving…" : "Save changes"}</button>
      </div>
      {msg && <p className={`rounded-sm px-3 py-2 text-sm ${msg.ok ? "text-(--teal)" : "text-(--brick)"}`} style={{ background: msg.ok ? "var(--teal-surface)" : "var(--brick-surface)" }}>{msg.text}</p>}
      <div className="panel max-h-[34rem] overflow-auto">
        <table className="w-full text-sm">
          <thead className="sticky top-0 bg-(--color-surface) text-left text-xs uppercase text-(--steel)">
            <tr><th className="p-3">Equipment</th>{FIELDS.map((f) => <th key={f} className="p-3 text-right">{LABEL[f]}</th>)}</tr>
          </thead>
          <tbody>
            {shown.map((e) => (
              <tr key={e.id} className="border-t border-(--border)">
                <td className="p-3"><div>{e.name}</div><div className="id-code text-xs text-(--steel)">{e.source_code}</div></td>
                {FIELDS.map((f) => (
                  <td key={f} className="p-2 text-right">
                    <input type="number" min={0} value={vals[e.id][f]} placeholder={e[f] == null ? "—" : String(e[f])}
                      onChange={(ev) => setVals({ ...vals, [e.id]: { ...vals[e.id], [f]: ev.target.value } })}
                      className="w-24 rounded-sm border border-(--border) px-2 py-1 text-right" />
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="text-xs text-(--steel)">Grey placeholder = network default currently in use. Clear all four cells in a row to return it to the default.</p>
    </div>
  );
}
