"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";

export type FlightChoice = { flightNumber: string; flightDate: string; unverified: boolean };
type Upcoming = { flight_date: string; flight_number: string };

const field = "min-h-11 w-full px-3 py-2 text-sm";
const lbl = "mb-1 block text-sm font-medium text-(--color-text-muted)";

function label(d: string, f: string) {
  const date = new Date(d + "T00:00:00");
  return `${date.toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short" })} · ${f}`;
}

/**
 * One list of the next flights between two stations (date and flight in a single pick).
 * A flight that is not in the schedule can be entered by hand; it is saved as unverified and a
 * station manager confirms it later. It never blocks the movement.
 */
export function FlightPicker({
  fromStationId, toStationId, value, onChange, optional = false,
}: {
  fromStationId: string;
  toStationId: string;
  value: FlightChoice | null;
  onChange: (v: FlightChoice | null) => void;
  optional?: boolean;
}) {
  const [flights, setFlights] = useState<Upcoming[] | null>(null);
  const [manual, setManual] = useState(false);
  const [mDate, setMDate] = useState("");
  const [mNumber, setMNumber] = useState("");
  const [mNote, setMNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const ready = Boolean(fromStationId && toStationId && fromStationId !== toStationId);

  useEffect(() => {
    if (!ready) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setFlights(null);
      return;
    }
    let stale = false;
    setFlights(null);
    createClient().rpc("upcoming_flights", { p_from: fromStationId, p_to: toStationId, p_days: 14 })
      .then(({ data }) => {
        if (stale) return;
        const list = (data as Upcoming[]) ?? [];
        setFlights(list);
        if (list.length === 0) setManual(true);
      });
    return () => { stale = true; };
  }, [ready, fromStationId, toStationId]);

  async function useManual() {
    setError(null);
    if (!mDate || !mNumber.trim()) return setError("Enter the flight number and the date.");
    setBusy(true);
    const { error: e } = await createClient().rpc("create_unverified_flight_leg", {
      p_flight_number: mNumber, p_date: mDate, p_origin_station_id: fromStationId, p_destination_station_id: toStationId, p_note: mNote || "Not in the schedule",
    });
    setBusy(false);
    if (e) return setError(e.message);
    const flightNumber = /^UR/i.test(mNumber.trim()) ? mNumber.trim().toUpperCase() : "UR" + mNumber.trim().toUpperCase();
    onChange({ flightNumber, flightDate: mDate, unverified: true });
    setManual(false);
  }

  const selected = value && !value.unverified ? `${value.flightDate}|${value.flightNumber}` : "";

  return (
    <div className="space-y-3">
      <div>
        <label htmlFor="fp-flight" className={lbl}>Flight{optional ? " (optional)" : ""}</label>
        <select
          id="fp-flight"
          required={!optional && !value}
          disabled={!ready || flights === null}
          value={selected}
          onChange={(e) => {
            if (!e.target.value) return onChange(null);
            const [flightDate, flightNumber] = e.target.value.split("|");
            onChange({ flightNumber, flightDate, unverified: false });
          }}
          className={field}
        >
          <option value="">
            {!ready ? "Choose the destination first" : flights === null ? "Loading flights…" : flights.length === 0 ? "No scheduled flights in the next 14 days" : value?.unverified ? `${label(value.flightDate, value.flightNumber)} (entered by hand)` : "Select a flight"}
          </option>
          {(flights ?? []).map((f) => (
            <option key={`${f.flight_date}|${f.flight_number}`} value={`${f.flight_date}|${f.flight_number}`}>{label(f.flight_date, f.flight_number)}</option>
          ))}
        </select>
      </div>

      {value?.unverified && (
        <p className="alert alert-warning text-sm">
          {label(value.flightDate, value.flightNumber)} is not in the schedule. It is saved as unverified until a station manager confirms it.
          {" "}<button type="button" className="font-semibold underline" onClick={() => onChange(null)}>Choose another</button>
        </p>
      )}

      {ready && !manual && !value?.unverified && (
        <button type="button" onClick={() => setManual(true)} className="text-sm font-semibold text-(--color-primary) hover:underline">
          Flight not in the list?
        </button>
      )}

      {manual && ready && (
        <div className="rounded border border-(--color-border) p-3 text-sm">
          <p className="mb-3 text-xs text-(--color-text-subtle)">
            Enter the flight yourself. {flights && flights.length === 0 ? "No scheduled flight was found for this route. " : ""}A station manager will confirm it.
          </p>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
            <div>
              <label htmlFor="fp-m-date" className={lbl}>Flight date</label>
              <input id="fp-m-date" type="date" value={mDate} onChange={(e) => setMDate(e.target.value)} className={field} />
            </div>
            <div>
              <label htmlFor="fp-m-number" className={lbl}>Flight number</label>
              <input id="fp-m-number" value={mNumber} onChange={(e) => setMNumber(e.target.value)} placeholder="e.g. UR812" className={field} />
            </div>
            <div>
              <label htmlFor="fp-m-note" className={lbl}>Why is it not listed?</label>
              <input id="fp-m-note" value={mNote} onChange={(e) => setMNote(e.target.value)} placeholder="e.g. extra flight" className={field} />
            </div>
          </div>
          {error && <p role="alert" className="alert alert-danger mt-3">{error}</p>}
          <div className="mt-3 flex gap-3">
            <button type="button" disabled={busy} onClick={useManual} className="btn-primary min-h-11 px-4 text-sm">{busy ? "Saving…" : "Use this flight"}</button>
            {flights && flights.length > 0 && <button type="button" onClick={() => setManual(false)} className="btn-secondary min-h-11 px-4 text-sm">Cancel</button>}
          </div>
        </div>
      )}
    </div>
  );
}
