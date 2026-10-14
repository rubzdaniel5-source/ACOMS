"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { saveEquipment } from "./actions";

type Category = { id: string; name: string };
export type EquipmentValues = {
  id?: string; category_id: string; source_code: string; name: string; description: string | null;
  unit_of_measure: string; packaging_unit: string | null; pack_size: number | null; tracking_method: string;
  is_consumable: boolean; is_returnable: boolean; reorder_threshold: number | null; minimum_stock: number | null;
  target_stock: number | null; maximum_stock: number | null; reconciliation_tolerance: number;
  ownership_type: string | null; notes: string | null;
};

const EMPTY: EquipmentValues = {
  category_id: "", source_code: "", name: "", description: "", unit_of_measure: "EACH", packaging_unit: "", pack_size: null,
  tracking_method: "QUANTITY", is_consumable: false, is_returnable: true, reorder_threshold: null, minimum_stock: null,
  target_stock: null, maximum_stock: null, reconciliation_tolerance: 1, ownership_type: "", notes: "",
};

const input = "w-full rounded-sm border border-(--border) px-3 py-2 text-sm";
const numOrNull = (v: string) => (v.trim() === "" ? null : Number(v));

export function EquipmentForm({ categories, initial }: { categories: Category[]; initial?: EquipmentValues }) {
  const router = useRouter();
  const [v, setV] = useState<EquipmentValues>(initial ?? EMPTY);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const [pending, startTransition] = useTransition();
  const set = (patch: Partial<EquipmentValues>) => { setV({ ...v, ...patch }); setSaved(false); };

  function submit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    startTransition(async () => {
      const { id, category_id, ...rest } = v;
      const res = await saveEquipment(initial?.id ?? null, category_id, rest);
      if (!res.ok) return setError(res.error);
      setSaved(true);
      if (!initial) router.push(`/admin/catalogue/${res.id}`);
      else router.refresh();
    });
  }

  const num = (label: string, key: keyof EquipmentValues, hint?: string) => (
    <div>
      <label className="mb-1 block text-sm font-medium">{label}</label>
      <input type="number" min={0} value={(v[key] as number | null) ?? ""} onChange={(e) => set({ [key]: numOrNull(e.target.value) } as any)} className={input} />
      {hint && <p className="mt-1 text-xs text-(--steel)">{hint}</p>}
    </div>
  );

  return (
    <form onSubmit={submit} className="space-y-6">
      <section className="panel space-y-4 p-4">
        <h2 className="font-semibold text-(--navy)">Identity</h2>
        <div className="grid gap-4 sm:grid-cols-2">
          <div><label className="mb-1 block text-sm font-medium">Code</label>
            <input required value={v.source_code} onChange={(e) => set({ source_code: e.target.value })} className={`${input} id-code`} /></div>
          <div><label className="mb-1 block text-sm font-medium">Category</label>
            <select required value={v.category_id} onChange={(e) => set({ category_id: e.target.value })} className={input}>
              <option value="">Select…</option>
              {categories.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select></div>
        </div>
        <div><label className="mb-1 block text-sm font-medium">Name</label>
          <input required value={v.name} onChange={(e) => set({ name: e.target.value })} className={input} /></div>
        <div><label className="mb-1 block text-sm font-medium">Description</label>
          <input value={v.description ?? ""} onChange={(e) => set({ description: e.target.value })} className={input} /></div>
      </section>

      <section className="panel space-y-4 p-4">
        <h2 className="font-semibold text-(--navy)">Counting and packaging</h2>
        <div className="grid gap-4 sm:grid-cols-3">
          <div><label className="mb-1 block text-sm font-medium">Unit</label>
            <input value={v.unit_of_measure} onChange={(e) => set({ unit_of_measure: e.target.value })} className={input} /></div>
          <div><label className="mb-1 block text-sm font-medium">Packaging unit</label>
            <input value={v.packaging_unit ?? ""} onChange={(e) => set({ packaging_unit: e.target.value })} placeholder="e.g. CARTON" className={input} /></div>
          {num("Pack size", "pack_size")}
        </div>
        <div className="grid gap-4 sm:grid-cols-3">
          <div><label className="mb-1 block text-sm font-medium">Tracking</label>
            <select value={v.tracking_method} onChange={(e) => set({ tracking_method: e.target.value, ...(e.target.value === "INDIVIDUAL" ? { reconciliation_tolerance: 0 } : {}) })} className={input}>
              <option value="QUANTITY">By quantity</option><option value="INDIVIDUAL">Individually (serialised)</option><option value="BATCH">By batch</option>
            </select></div>
          <label className="flex items-center gap-2 pt-6 text-sm"><input type="checkbox" checked={v.is_consumable} onChange={(e) => set({ is_consumable: e.target.checked })} /> Consumable</label>
          <label className="flex items-center gap-2 pt-6 text-sm"><input type="checkbox" checked={v.is_returnable} onChange={(e) => set({ is_returnable: e.target.checked })} /> Returnable</label>
        </div>
      </section>

      <section className="panel space-y-4 p-4">
        <h2 className="font-semibold text-(--navy)">Stock levels and tolerance</h2>
        <div className="grid gap-4 sm:grid-cols-4">
          {num("Reorder threshold", "reorder_threshold", "Drives shortage alerts")}
          {num("Minimum", "minimum_stock")}
          {num("Target", "target_stock")}
          {num("Maximum", "maximum_stock")}
        </div>
        <div className="max-w-xs">
          {num("Reconciliation tolerance (units)", "reconciliation_tolerance", "Allowed unexplained difference on a transfer. Must be 0 for individually tracked items.")}
        </div>
      </section>

      <section className="panel space-y-4 p-4">
        <h2 className="font-semibold text-(--navy)">Other</h2>
        <div><label className="mb-1 block text-sm font-medium">Ownership</label>
          <input value={v.ownership_type ?? ""} onChange={(e) => set({ ownership_type: e.target.value })} placeholder="e.g. AIRLINE_OWNED" className={input} /></div>
        <div><label className="mb-1 block text-sm font-medium">Notes</label>
          <textarea value={v.notes ?? ""} onChange={(e) => set({ notes: e.target.value })} rows={2} className={input} /></div>
      </section>

      {error && <p className="rounded-sm px-3 py-2 text-sm text-(--brick)" style={{ background: "var(--brick-surface)" }}>{error}</p>}
      {saved && <p className="rounded-sm px-3 py-2 text-sm text-(--teal)" style={{ background: "var(--teal-surface)" }}>Saved.</p>}
      <button type="submit" disabled={pending} className="btn-primary px-5 py-2 text-sm">{pending ? "Saving…" : initial ? "Save changes" : "Create equipment"}</button>
    </form>
  );
}
