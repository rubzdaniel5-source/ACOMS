"use client";

import { useState } from "react";
import { FlightPicker, type FlightChoice } from "@/components/flights/FlightPicker";
import { EquipmentPicker, type Selection } from "./EquipmentPicker";

type Station = { id: string; code: string; name: string };
type Line = { equipment_type_id: string; quantity: number };
export type MovementValues = { toStationId: string; items: Line[]; reason: string; priority: string; flightNumber: string; flightDate: string; requestKey: string };

const field = "min-h-11 w-full px-3 py-2 text-sm";
const lbl = "mb-1 block text-sm font-medium text-(--color-text-muted)";

// Shared by "New exchange" (hub to a chosen outstation) and "Record return" (outstation to hub).
export function MovementForm({
  mode, fromStationId, fromCode, fixedToStationId, fixedToCode, outboundTransferId, destinations, submitLabel, onSubmit, onCancel,
}: {
  mode: "outbound" | "return";
  fromStationId: string;
  fromCode: string;
  fixedToStationId?: string;
  fixedToCode?: string;
  outboundTransferId?: string | null;
  destinations?: Station[];
  submitLabel: string;
  onSubmit: (v: MovementValues) => Promise<string | null>; // returns an error message, or null on success
  onCancel?: () => void;
}) {
  const [toStationId, setToStationId] = useState(fixedToStationId ?? "");
  const [flight, setFlight] = useState<FlightChoice | null>(null);
  const [reason, setReason] = useState("");
  const [priority, setPriority] = useState("NORMAL");
  const [selection, setSelection] = useState<Selection>({});
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  // One key per opened form, so a double click or retry cannot start two exchanges.
  const [requestKey] = useState(() => crypto.randomUUID());
  const toCode = fixedToCode ?? destinations?.find((d) => d.id === toStationId)?.code;

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (submitting) return;
    setError(null);
    const valid = Object.entries(selection).filter(([, q]) => q > 0).map(([equipment_type_id, quantity]) => ({ equipment_type_id, quantity }));
    if (!toStationId) return setError("Choose the destination station.");
    if (!flight) return setError("Choose a flight.");
    if (valid.length === 0) return setError("Tick at least one item and enter its quantity.");
    if (Object.values(selection).some((q) => !(q > 0))) return setError("Every ticked item needs a quantity above zero.");
    setSubmitting(true);
    const message = await onSubmit({ toStationId, items: valid, reason, priority, flightNumber: flight.flightNumber, flightDate: flight.flightDate, requestKey });
    setSubmitting(false);
    if (message) setError(message); // values stay in the form
  }

  return (
    <form onSubmit={submit} className="space-y-5">
      {error && <p role="alert" className="alert alert-danger">{error}</p>}
      <section className="panel space-y-4 p-4 sm:p-5">
        <h2 className="text-base font-semibold text-(--color-text)">Destination and flight</h2>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          {destinations && (
            <div>
              <label htmlFor="mv-to" className={lbl}>Outstation</label>
              <select id="mv-to" required value={toStationId} onChange={(e) => { setToStationId(e.target.value); setFlight(null); setSelection({}); }} className={field}>
                <option value="">Select station</option>
                {destinations.map((s) => <option key={s.id} value={s.id}>{s.code} — {s.name}</option>)}
              </select>
            </div>
          )}
          <FlightPicker fromStationId={fromStationId} toStationId={toStationId} value={flight} onChange={setFlight} />
        </div>
      </section>

      <section className="panel p-4 sm:p-5">
        <h2 className="mb-1 text-base font-semibold text-(--color-text)">Equipment</h2>
        <p className="mb-4 text-sm text-(--color-text-muted)">
          {mode === "outbound" ? "Tick each item being sent and enter how many." : "Tick each item being sent back to the hub and enter how many. It does not have to match what was received."}
        </p>
        <EquipmentPicker
          mode={mode} fromStationId={fromStationId} fromCode={fromCode} toStationId={toStationId || undefined} toCode={toCode}
          outboundTransferId={outboundTransferId} value={selection} onChange={setSelection}
        />
      </section>

      <section className="panel space-y-4 p-4 sm:p-5">
        <h2 className="text-base font-semibold text-(--color-text)">Details</h2>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <div>
            <label htmlFor="mv-priority" className={lbl}>Priority</label>
            <select id="mv-priority" value={priority} onChange={(e) => setPriority(e.target.value)} className={field}>
              <option value="LOW">Low</option><option value="NORMAL">Normal</option><option value="HIGH">High</option><option value="URGENT">Urgent</option>
            </select>
          </div>
          <div className="sm:col-span-2">
            <label htmlFor="mv-reason" className={lbl}>Reason (optional)</label>
            <textarea id="mv-reason" rows={2} value={reason} onChange={(e) => setReason(e.target.value)} className="w-full px-3 py-2 text-sm" />
          </div>
        </div>
      </section>

      <div className="flex gap-3">
        <button type="submit" disabled={submitting} className="btn-primary min-h-11 px-5 text-sm">{submitting ? "Saving…" : submitLabel}</button>
        {onCancel && <button type="button" onClick={onCancel} className="btn-secondary min-h-11 px-5 text-sm">Cancel</button>}
      </div>
    </form>
  );
}
