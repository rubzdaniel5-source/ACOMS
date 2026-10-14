"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { reportDamageAction, reportLossAction } from "@/features/damage-loss/actions";
import type { Station, EquipmentType } from "@/types/transfers";

export function ReportForm() {
  const router = useRouter();
  const [mode, setMode] = useState<"damage" | "loss">("damage");
  const [stations, setStations] = useState<Station[]>([]);
  const [equipmentTypes, setEquipmentTypes] = useState<EquipmentType[]>([]);
  const [stationId, setStationId] = useState("");
  const [equipmentTypeId, setEquipmentTypeId] = useState("");
  const [quantity, setQuantity] = useState(1);
  const [detail, setDetail] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    const supabase = createClient();
    supabase.from("stations").select("id, code, name, station_type").eq("is_active", true).order("code")
      .then(({ data }) => setStations((data as Station[]) ?? []));
    supabase.from("equipment_types").select("id, source_code, name, reconciliation_tolerance").eq("is_active", true).order("name")
      .then(({ data }) => setEquipmentTypes((data as EquipmentType[]) ?? []));
  }, []);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    if (!stationId || !equipmentTypeId || quantity <= 0 || !detail.trim()) {
      setError("All fields are required.");
      return;
    }

    setSubmitting(true);
    const result =
      mode === "damage"
        ? await reportDamageAction({ equipmentTypeId, stationId, quantity, reason: detail })
        : await reportLossAction({ equipmentTypeId, stationId, quantity, circumstances: detail });
    setSubmitting(false);

    if (!result.success) {
      setError(result.error ?? "Failed to submit report.");
      return;
    }
    router.push(`/damage-loss/${result.reportId}?type=${mode}`);
  }

  return (
    <div className="panel p-4 sm:p-5">
      <div className="mb-4 flex gap-2">
        <button
          type="button"
          aria-pressed={mode === "damage"}
          onClick={() => setMode("damage")}
          className={`min-h-11 rounded-md px-4 py-1.5 text-sm font-medium ${mode === "damage" ? "bg-(--color-action) text-(--color-on-action)" : "bg-(--color-surface-subtle) text-(--color-text-muted)"}`}
        >
          Report Damage
        </button>
        <button
          type="button"
          aria-pressed={mode === "loss"}
          onClick={() => setMode("loss")}
          className={`min-h-11 rounded-md px-4 py-1.5 text-sm font-medium ${mode === "loss" ? "bg-(--color-action) text-(--color-on-action)" : "bg-(--color-surface-subtle) text-(--color-text-muted)"}`}
        >
          Report Loss
        </button>
      </div>

      <form onSubmit={handleSubmit} className="space-y-4">
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label htmlFor="report-station" className="mb-1 block text-sm font-medium text-(--color-text-muted)">Station</label>
            <select
              id="report-station"
              required
              value={stationId}
              onChange={(e) => setStationId(e.target.value)}
              className="min-h-11 w-full px-3 py-2 text-sm"
            >
              <option value="">Select...</option>
              {stations.map((s) => (
                <option key={s.id} value={s.id}>{s.code} — {s.name}</option>
              ))}
            </select>
          </div>
          <div>
            <label htmlFor="report-qty" className="mb-1 block text-sm font-medium text-(--color-text-muted)">Quantity</label>
            <input
              id="report-qty"
              type="number"
              min={1}
              required
              value={quantity}
              onChange={(e) => setQuantity(parseInt(e.target.value, 10) || 0)}
              className="min-h-11 w-full px-3 py-2 text-sm"
            />
          </div>
        </div>

        <div>
          <label htmlFor="report-equipment" className="mb-1 block text-sm font-medium text-(--color-text-muted)">Equipment</label>
          <select
            id="report-equipment"
            required
            value={equipmentTypeId}
            onChange={(e) => setEquipmentTypeId(e.target.value)}
            className="min-h-11 w-full px-3 py-2 text-sm"
          >
            <option value="">Select...</option>
            {equipmentTypes.map((et) => (
              <option key={et.id} value={et.id}>{et.source_code} — {et.name}</option>
            ))}
          </select>
        </div>

        <div>
          <label htmlFor="report-detail" className="mb-1 block text-sm font-medium text-(--color-text-muted)">
            {mode === "damage" ? "Reason" : "Circumstances"}
          </label>
          <textarea
            id="report-detail"
            required
            value={detail}
            onChange={(e) => setDetail(e.target.value)}
            rows={2}
            className="min-h-11 w-full px-3 py-2 text-sm"
            placeholder={mode === "damage" ? "e.g. Cracked during handling at receiving" : "e.g. Not found during morning count, last seen..."}
          />
        </div>

        {error && <p role="alert" className="alert alert-danger">{error}</p>}

        <button
          type="submit"
          disabled={submitting}
          className="btn-primary min-h-11 px-5 text-sm"
        >
          {submitting ? "Submitting..." : `Submit ${mode === "damage" ? "Damage" : "Loss"} Report`}
        </button>
      </form>
    </div>
  );
}
