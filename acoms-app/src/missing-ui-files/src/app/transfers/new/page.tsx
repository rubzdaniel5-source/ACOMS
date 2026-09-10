"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { requestTransferAction } from "@/features/transfers/actions";
import type { Station, EquipmentType } from "@/types/transfers";

interface LineItem {
  equipment_type_id: string;
  quantity: number;
}

export default function NewTransferPage() {
  const router = useRouter();
  const [stations, setStations] = useState<Station[]>([]);
  const [equipmentTypes, setEquipmentTypes] = useState<EquipmentType[]>([]);
  const [fromStationId, setFromStationId] = useState("");
  const [toStationId, setToStationId] = useState("");
  const [reason, setReason] = useState("");
  const [priority, setPriority] = useState("NORMAL");
  const [items, setItems] = useState<LineItem[]>([{ equipment_type_id: "", quantity: 1 }]);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    const supabase = createClient();
    supabase
      .from("stations")
      .select("id, code, name, station_type")
      .eq("is_active", true)
      .order("code")
      .then(({ data }) => setStations((data as Station[]) ?? []));

    supabase
      .from("equipment_types")
      .select("id, source_code, name, reconciliation_tolerance")
      .eq("is_active", true)
      .order("name")
      .then(({ data }) => setEquipmentTypes((data as EquipmentType[]) ?? []));
  }, []);

  function updateItem(index: number, patch: Partial<LineItem>) {
    setItems((prev) => prev.map((it, i) => (i === index ? { ...it, ...patch } : it)));
  }

  function addItem() {
    setItems((prev) => [...prev, { equipment_type_id: "", quantity: 1 }]);
  }

  function removeItem(index: number) {
    setItems((prev) => prev.filter((_, i) => i !== index));
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    if (fromStationId === toStationId) {
      setError("Source and destination stations must be different.");
      return;
    }
    const validItems = items.filter((it) => it.equipment_type_id && it.quantity > 0);
    if (validItems.length === 0) {
      setError("Add at least one equipment line with a quantity.");
      return;
    }

    setSubmitting(true);
    const result = await requestTransferAction({
      fromStationId,
      toStationId,
      items: validItems,
      reason,
      priority,
    });
    setSubmitting(false);

    if (!result.success) {
      setError(result.error ?? "Failed to create transfer request.");
      return;
    }
    router.push(`/transfers/${result.transferId}`);
  }

  // Turnaround stations never hold stock — flag this in the UI so nobody
  // tries to request a transfer FROM one (station_type is available for
  // that check once wired up; kept simple here to avoid over-building
  // ahead of real usage feedback).
  const fromStation = stations.find((s) => s.id === fromStationId);

  return (
    <div className="mx-auto max-w-2xl px-4 py-8">
      <h1 className="mb-6 text-xl font-semibold text-slate-900">New Transfer Request</h1>

      <form onSubmit={handleSubmit} className="space-y-5">
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">From Station</label>
            <select
              required
              value={fromStationId}
              onChange={(e) => setFromStationId(e.target.value)}
              className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
            >
              <option value="">Select...</option>
              {stations.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.code} — {s.name}
                </option>
              ))}
            </select>
            {fromStation?.station_type === "NO_STOCK_TURNAROUND" && (
              <p className="mt-1 text-xs text-amber-600">
                Warning: this is a no-stock turnaround station and likely holds no equipment to transfer out.
              </p>
            )}
          </div>
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">To Station</label>
            <select
              required
              value={toStationId}
              onChange={(e) => setToStationId(e.target.value)}
              className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
            >
              <option value="">Select...</option>
              {stations.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.code} — {s.name}
                </option>
              ))}
            </select>
          </div>
        </div>

        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Priority</label>
          <select
            value={priority}
            onChange={(e) => setPriority(e.target.value)}
            className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
          >
            <option value="LOW">Low</option>
            <option value="NORMAL">Normal</option>
            <option value="HIGH">High</option>
            <option value="URGENT">Urgent</option>
          </select>
        </div>

        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Reason</label>
          <textarea
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            rows={2}
            className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
            placeholder="e.g. ABJ running low on main course casseroles"
          />
        </div>

        <div>
          <div className="mb-2 flex items-center justify-between">
            <label className="text-sm font-medium text-slate-700">Equipment</label>
            <button
              type="button"
              onClick={addItem}
              className="text-sm font-medium text-slate-600 hover:text-slate-900"
            >
              + Add line
            </button>
          </div>
          <div className="space-y-2">
            {items.map((item, index) => (
              <div key={index} className="flex gap-2">
                <select
                  required
                  value={item.equipment_type_id}
                  onChange={(e) => updateItem(index, { equipment_type_id: e.target.value })}
                  className="flex-1 rounded-md border border-slate-300 px-3 py-2 text-sm"
                >
                  <option value="">Select equipment...</option>
                  {equipmentTypes.map((et) => (
                    <option key={et.id} value={et.id}>
                      {et.source_code} — {et.name}
                    </option>
                  ))}
                </select>
                <input
                  type="number"
                  min={1}
                  required
                  value={item.quantity}
                  onChange={(e) => updateItem(index, { quantity: parseInt(e.target.value, 10) || 0 })}
                  className="w-24 rounded-md border border-slate-300 px-3 py-2 text-sm"
                />
                {items.length > 1 && (
                  <button
                    type="button"
                    onClick={() => removeItem(index)}
                    className="px-2 text-slate-400 hover:text-red-600"
                  >
                    &times;
                  </button>
                )}
              </div>
            ))}
          </div>
        </div>

        {error && <p className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>}

        <div className="flex gap-3">
          <button
            type="submit"
            disabled={submitting}
            className="rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-50"
          >
            {submitting ? "Submitting..." : "Submit Request"}
          </button>
        </div>
      </form>
    </div>
  );
}
