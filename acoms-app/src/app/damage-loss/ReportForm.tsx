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
    <div className="rounded-lg border border-slate-200 p-5">
      <div className="mb-4 flex gap-2">
        <button
          onClick={() => setMode("damage")}
          className={`rounded-md px-3 py-1.5 text-sm font-medium ${mode === "damage" ? "bg-slate-900 text-white" : "bg-slate-100 text-slate-600"}`}
        >
          Report Damage
        </button>
        <button
          onClick={() => setMode("loss")}
          className={`rounded-md px-3 py-1.5 text-sm font-medium ${mode === "loss" ? "bg-slate-900 text-white" : "bg-slate-100 text-slate-600"}`}
        >
          Report Loss
        </button>
      </div>

      <form onSubmit={handleSubmit} className="space-y-4">
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">Station</label>
            <select
              required
              value={stationId}
              onChange={(e) => setStationId(e.target.value)}
              className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
            >
              <option value="">Select...</option>
              {stations.map((s) => (
                <option key={s.id} value={s.id}>{s.code} — {s.name}</option>
              ))}
            </select>
          </div>
          <div>
            <label className="mb-1 block text-sm font-medium text-slate-700">Quantity</label>
            <input
              type="number"
              min={1}
              required
              value={quantity}
              onChange={(e) => setQuantity(parseInt(e.target.value, 10) || 0)}
              className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
            />
          </div>
        </div>

        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">Equipment</label>
          <select
            required
            value={equipmentTypeId}
            onChange={(e) => setEquipmentTypeId(e.target.value)}
            className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
          >
            <option value="">Select...</option>
            {equipmentTypes.map((et) => (
              <option key={et.id} value={et.id}>{et.source_code} — {et.name}</option>
            ))}
          </select>
        </div>

        <div>
          <label className="mb-1 block text-sm font-medium text-slate-700">
            {mode === "damage" ? "Reason" : "Circumstances"}
          </label>
          <textarea
            required
            value={detail}
            onChange={(e) => setDetail(e.target.value)}
            rows={2}
            className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
            placeholder={mode === "damage" ? "e.g. Cracked during handling at receiving" : "e.g. Not found during morning count, last seen..."}
          />
        </div>

        {error && <p className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>}

        <button
          type="submit"
          disabled={submitting}
          className="rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-50"
        >
          {submitting ? "Submitting..." : `Submit ${mode === "damage" ? "Damage" : "Loss"} Report`}
        </button>
      </form>
    </div>
  );
}
