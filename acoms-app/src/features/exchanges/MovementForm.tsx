"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type Station = { id: string; code: string; name: string };
type Equipment = { id: string; source_code: string; name: string };
type Line = { equipment_type_id: string; quantity: number };
export type MovementValues = { toStationId: string; items: Line[]; reason: string; priority: string; flightNumber: string; flightDate: string; requestKey: string };

const field = "min-h-11 w-full px-3 py-2 text-sm";
const lbl = "mb-1 block text-sm font-medium text-(--color-text-muted)";

// Shared by "New exchange" (hub to a chosen outstation) and "Record return" (outstation to hub).
export function MovementForm({
  fromStationId, fixedToStationId, destinations, submitLabel, onSubmit, onCancel,
}: {
  fromStationId: string;
  fixedToStationId?: string;
  destinations?: Station[];
  submitLabel: string;
  onSubmit: (v: MovementValues) => Promise<string | null>; // returns an error message, or null on success
  onCancel?: () => void;
}) {
  const [equipment, setEquipment] = useState<Equipment[]>([]);
  const [toStationId, setToStationId] = useState(fixedToStationId ?? "");
  const [flightDate, setFlightDate] = useState("");
  const [flightNumber, setFlightNumber] = useState("");
  const [flights, setFlights] = useState<string[]>([]);
  const [reason, setReason] = useState("");
  const [priority, setPriority] = useState("NORMAL");
  const [items, setItems] = useState<Line[]>([{ equipment_type_id: "", quantity: 1 }]);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  // One key per opened form, so a double click or retry cannot start two exchanges.
  const [requestKey] = useState(() => crypto.randomUUID());

  useEffect(() => {
    createClient().from("equipment_types").select("id, source_code, name").eq("is_active", true).order("name")
      .then(({ data }) => setEquipment((data as Equipment[]) ?? []));
  }, []);

  useEffect(() => {
    if (!toStationId || !flightDate) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setFlights([]);
      return;
    }
    let stale = false;
    createClient().rpc("available_flights", { p_from: fromStationId, p_to: toStationId, p_date: flightDate })
      .then(({ data }) => { if (!stale) setFlights(((data as { flight_number: string }[]) ?? []).map((r) => r.flight_number)); });
    return () => { stale = true; };
  }, [fromStationId, toStationId, flightDate]);

  function setItem(i: number, patch: Partial<Line>) {
    setItems((prev) => prev.map((it, idx) => (idx === i ? { ...it, ...patch } : it)));
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (submitting) return;
    setError(null);
    const valid = items.filter((it) => it.equipment_type_id && it.quantity > 0);
    if (!toStationId) return setError("Choose the destination station.");
    if (!flightNumber) return setError("Choose a flight. Pick the date first to see the flights that run on it.");
    if (valid.length === 0) return setError("Add at least one equipment line with a quantity.");
    if (new Set(valid.map((v) => v.equipment_type_id)).size !== valid.length) return setError("Each equipment item can appear only once.");
    setSubmitting(true);
    const message = await onSubmit({ toStationId, items: valid, reason, priority, flightNumber, flightDate, requestKey });
    setSubmitting(false);
    if (message) setError(message); // values stay in the form
  }

  return (
    <form onSubmit={submit} className="space-y-5">
      {error && <p role="alert" className="alert alert-danger">{error}</p>}
      <section className="panel space-y-4 p-4 sm:p-5">
        <h2 className="text-base font-semibold text-(--color-text)">Destination and flight</h2>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
          {destinations && (
            <div>
              <label htmlFor="mv-to" className={lbl}>Outstation</label>
              <select id="mv-to" required value={toStationId} onChange={(e) => { setToStationId(e.target.value); setFlightNumber(""); }} className={field}>
                <option value="">Select station</option>
                {destinations.map((s) => <option key={s.id} value={s.id}>{s.code} — {s.name}</option>)}
              </select>
            </div>
          )}
          <div>
            <label htmlFor="mv-date" className={lbl}>Flight date</label>
            <input id="mv-date" required type="date" value={flightDate} onChange={(e) => { setFlightDate(e.target.value); setFlightNumber(""); }} className={field} />
          </div>
          <div>
            <label htmlFor="mv-flight" className={lbl}>Flight</label>
            <select id="mv-flight" required value={flightNumber} onChange={(e) => setFlightNumber(e.target.value)} disabled={flights.length === 0} className={field}>
              <option value="">{flights.length === 0 ? "Pick the date first" : "Select flight"}</option>
              {flights.map((f) => <option key={f} value={f}>{f}</option>)}
            </select>
          </div>
        </div>
        {toStationId && flightDate && flights.length === 0 && (
          <p className="text-xs text-(--color-warning)">No scheduled flight serves this route on that date. A station manager can add a one-off flight under Admin, Flights.</p>
        )}
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
            <label htmlFor="mv-reason" className={lbl}>Reason</label>
            <textarea id="mv-reason" rows={2} value={reason} onChange={(e) => setReason(e.target.value)} className="w-full px-3 py-2 text-sm" />
          </div>
        </div>
      </section>

      <section className="panel p-4 sm:p-5">
        <div className="mb-4 flex items-center justify-between gap-3">
          <h2 className="text-base font-semibold text-(--color-text)">Equipment and planned quantities</h2>
          <button type="button" onClick={() => setItems((p) => [...p, { equipment_type_id: "", quantity: 1 }])} className="btn-secondary min-h-11 px-4 text-sm">Add line</button>
        </div>
        <div className="space-y-3">
          {items.map((it, i) => (
            <div key={i} className="grid grid-cols-[1fr_6rem_auto] items-end gap-2 sm:gap-3">
              <div>
                <label htmlFor={`mv-eq-${i}`} className="mb-1 block text-xs text-(--color-text-subtle)">Item</label>
                <select id={`mv-eq-${i}`} value={it.equipment_type_id} onChange={(e) => setItem(i, { equipment_type_id: e.target.value })} className={field}>
                  <option value="">Select equipment</option>
                  {equipment.map((q) => <option key={q.id} value={q.id}>{q.source_code} — {q.name}</option>)}
                </select>
              </div>
              <div>
                <label htmlFor={`mv-qty-${i}`} className="mb-1 block text-xs text-(--color-text-subtle)">Quantity</label>
                <input id={`mv-qty-${i}`} type="number" min={1} value={it.quantity} onChange={(e) => setItem(i, { quantity: Number(e.target.value) })} className={field} />
              </div>
              <button type="button" disabled={items.length === 1} onClick={() => setItems((p) => p.filter((_, idx) => idx !== i))} className="btn-secondary min-h-11 px-3 text-sm">Remove</button>
            </div>
          ))}
        </div>
      </section>

      <div className="flex gap-3">
        <button type="submit" disabled={submitting} className="btn-primary min-h-11 px-5 text-sm">{submitting ? "Saving…" : submitLabel}</button>
        {onCancel && <button type="button" onClick={onCancel} className="btn-secondary min-h-11 px-5 text-sm">Cancel</button>}
      </div>
    </form>
  );
}
