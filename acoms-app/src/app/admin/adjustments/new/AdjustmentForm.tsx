"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { requestAdjustment } from "../actions";
import { REASON_LABELS } from "@/features/admin/adjustments";

type Station = { id: string; code: string; name: string };
type Equipment = { id: string; source_code: string; name: string };
const input = "w-full rounded-sm border border-(--border) px-3 py-2 text-sm";

export function AdjustmentForm({ stations, equipment, available }: { stations: Station[]; equipment: Equipment[]; available: Record<string, number> }) {
  const router = useRouter();
  const [stationId, setStationId] = useState("");
  const [search, setSearch] = useState("");
  const [equipmentId, setEquipmentId] = useState("");
  const [direction, setDirection] = useState("INCREASE");
  const [quantity, setQuantity] = useState("");
  const [reason, setReason] = useState("COUNT_CORRECTION");
  const [notes, setNotes] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const q = search.trim().toLowerCase();
  const options = equipment.filter((e) => !q || e.name.toLowerCase().includes(q) || e.source_code.toLowerCase().includes(q));
  const current = stationId && equipmentId ? available[`${stationId}:${equipmentId}`] ?? 0 : null;
  const qty = Number(quantity);
  const after = current !== null && qty > 0 ? current + (direction === "INCREASE" ? qty : -qty) : null;

  function submit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    startTransition(async () => {
      const res = await requestAdjustment({ stationId, equipmentId, direction, quantity: qty, reasonCode: reason, notes });
      if (!res.ok) return setError(res.error);
      router.push(`/admin/adjustments/${res.id}`);
    });
  }

  return (
    <form onSubmit={submit} className="panel max-w-2xl space-y-4 p-6">
      <div className="grid gap-4 sm:grid-cols-2">
        <div><label className="mb-1 block text-sm font-medium">Station</label>
          <select required value={stationId} onChange={(e) => setStationId(e.target.value)} className={input}>
            <option value="">Select…</option>{stations.map((s) => <option key={s.id} value={s.id}>{s.code} — {s.name}</option>)}
          </select></div>
        <div><label className="mb-1 block text-sm font-medium">Find equipment</label>
          <input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search name or code" className={input} /></div>
      </div>
      <div><label className="mb-1 block text-sm font-medium">Equipment</label>
        <select required value={equipmentId} onChange={(e) => setEquipmentId(e.target.value)} className={input} size={Math.min(6, Math.max(2, options.length))}>
          {options.map((e) => <option key={e.id} value={e.id}>{e.source_code} — {e.name}</option>)}
        </select></div>

      {current !== null && (
        <p className="rounded-sm px-3 py-2 text-sm" style={{ background: "var(--steel-light)" }}>
          Currently available at this station: <strong>{current}</strong>
          {after !== null && <> → after adjustment: <strong className={after < 0 ? "text-(--brick)" : ""}>{after}</strong></>}
        </p>
      )}

      <div className="grid gap-4 sm:grid-cols-3">
        <div><label className="mb-1 block text-sm font-medium">Direction</label>
          <select value={direction} onChange={(e) => setDirection(e.target.value)} className={input}>
            <option value="INCREASE">Increase stock</option><option value="DECREASE">Decrease stock</option>
          </select></div>
        <div><label className="mb-1 block text-sm font-medium">Quantity</label>
          <input required type="number" min={1} step={1} value={quantity} onChange={(e) => setQuantity(e.target.value)} className={input} /></div>
        <div><label className="mb-1 block text-sm font-medium">Reason</label>
          <select value={reason} onChange={(e) => setReason(e.target.value)} className={input}>
            {Object.entries(REASON_LABELS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select></div>
      </div>
      <div><label className="mb-1 block text-sm font-medium">Explanation</label>
        <textarea required minLength={10} rows={3} value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="What happened and how do you know? (at least 10 characters)" className={input} /></div>

      {error && <p className="rounded-sm px-3 py-2 text-sm text-(--brick)" style={{ background: "var(--brick-surface)" }}>{error}</p>}
      <button disabled={pending || !equipmentId || !stationId} className="btn-primary px-5 py-2 text-sm">{pending ? "Submitting…" : "Submit for approval"}</button>
    </form>
  );
}
