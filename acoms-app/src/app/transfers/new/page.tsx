"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
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

  const field = "min-h-11 w-full px-3 py-2 text-sm";
  const lbl = "mb-1 block text-sm font-medium text-(--color-text-muted)";
  const req = <span className="text-(--color-danger)" aria-hidden="true"> *</span>;

  return (
    <div className="mx-auto w-full max-w-3xl px-3 py-6 sm:px-6">
      <Link href="/transfers" className="mb-4 inline-block text-sm text-(--color-primary) hover:underline">Back to transfers</Link>
      <h1 className="mb-1 text-2xl font-semibold text-(--color-text)">New Transfer Request</h1>
      <p className="mb-6 text-sm text-(--color-text-muted)">
        A request does not move stock. It must be approved, dispatched and received before balances change.
      </p>

      <form onSubmit={handleSubmit} className="space-y-5" noValidate={false}>
        <section className="panel space-y-4 p-4 sm:p-5">
          <h2 className="text-base font-semibold text-(--color-text)">Route</h2>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div>
              <label htmlFor="from-station" className={lbl}>From station{req}</label>
              <select id="from-station" required value={fromStationId} onChange={(e) => setFromStationId(e.target.value)} className={field}>
                <option value="">Select station</option>
                {stations.map((s) => (
                  <option key={s.id} value={s.id}>{s.code} — {s.name}</option>
                ))}
              </select>
              {fromStation?.station_type === "NO_STOCK_TURNAROUND" && (
                <p className="mt-1 text-xs text-(--color-warning)">
                  This is a no-stock turnaround station and likely holds no equipment to transfer out.
                </p>
              )}
            </div>
            <div>
              <label htmlFor="to-station" className={lbl}>To station{req}</label>
              <select id="to-station" required value={toStationId} onChange={(e) => setToStationId(e.target.value)} className={field}>
                <option value="">Select station</option>
                {stations.map((s) => (
                  <option key={s.id} value={s.id}>{s.code} — {s.name}</option>
                ))}
              </select>
            </div>
          </div>
        </section>

        <section className="panel space-y-4 p-4 sm:p-5">
          <h2 className="text-base font-semibold text-(--color-text)">Details</h2>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
            <div>
              <label htmlFor="priority" className={lbl}>Priority</label>
              <select id="priority" value={priority} onChange={(e) => setPriority(e.target.value)} className={field}>
                <option value="LOW">Low</option>
                <option value="NORMAL">Normal</option>
                <option value="HIGH">High</option>
                <option value="URGENT">Urgent</option>
              </select>
            </div>
            <div className="sm:col-span-2">
              <label htmlFor="reason" className={lbl}>Reason</label>
              <textarea
                id="reason"
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                rows={2}
                className="w-full px-3 py-2 text-sm"
                placeholder="e.g. ABJ running low on main course casseroles"
              />
            </div>
          </div>
        </section>

        <section className="panel p-4 sm:p-5">
          <div className="mb-4 flex items-center justify-between gap-3">
            <h2 className="text-base font-semibold text-(--color-text)">Equipment{req}</h2>
            <button type="button" onClick={addItem} className="btn-secondary min-h-11 px-4 text-sm">Add line</button>
          </div>
          <div className="space-y-3">
            {items.map((item, index) => (
              <div key={index} className="grid grid-cols-[1fr_6rem_auto] items-end gap-2 sm:gap-3">
                <div>
                  <label htmlFor={`eq-${index}`} className="mb-1 block text-xs text-(--color-text-subtle)">Item</label>
                  <select
                    id={`eq-${index}`}
                    required
                    value={item.equipment_type_id}
                    onChange={(e) => updateItem(index, { equipment_type_id: e.target.value })}
                    className={field}
                  >
                    <option value="">Select equipment</option>
                    {equipmentTypes.map((et) => (
                      <option key={et.id} value={et.id}>{et.source_code} — {et.name}</option>
                    ))}
                  </select>
                </div>
                <div>
                  <label htmlFor={`qty-${index}`} className="mb-1 block text-xs text-(--color-text-subtle)">Quantity</label>
                  <input
                    id={`qty-${index}`}
                    type="number"
                    min={1}
                    required
                    value={item.quantity}
                    onChange={(e) => updateItem(index, { quantity: parseInt(e.target.value, 10) || 0 })}
                    className={`${field} id-code`}
                  />
                </div>
                {items.length > 1 ? (
                  <button
                    type="button"
                    onClick={() => removeItem(index)}
                    aria-label={`Remove line ${index + 1}`}
                    className="btn-secondary min-h-11 min-w-11 px-3 text-sm"
                  >
                    Remove
                  </button>
                ) : (
                  <span aria-hidden="true" />
                )}
              </div>
            ))}
          </div>
        </section>

        {error && <div role="alert" className="alert alert-danger">{error}</div>}

        <div className="flex flex-wrap gap-3">
          <button type="submit" disabled={submitting} className="btn-primary min-h-11 px-5 text-sm">
            {submitting ? "Submitting" : "Submit request"}
          </button>
          <Link href="/transfers" className="btn-secondary inline-flex min-h-11 items-center px-5 text-sm">Cancel</Link>
        </div>
      </form>
    </div>
  );
}
