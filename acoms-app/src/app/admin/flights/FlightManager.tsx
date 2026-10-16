"use client";

import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { createRoute, setRouteActive, createOneOffLeg, cancelLeg } from "./actions";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";

export type Route = { id: string; flight_number: string; origin_code: string; destination_code: string; operating_days: number[]; valid_from: string; valid_to: string | null; is_active: boolean };
export type Leg = { id: string; flight_number: string; operating_date: string; origin_code: string; destination_code: string; status: string; is_one_off: boolean; cancel_reason: string | null };
export type Station = { id: string; code: string; name: string };

const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const input = "w-full rounded-sm border border-(--border) px-2 py-1.5 text-sm";
const fmt = (d: string) => new Date(d + "T00:00:00").toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });

export function FlightManager({ routes, legs, stations, canManage, today }: { routes: Route[]; legs: Leg[]; stations: Station[]; canManage: boolean; today: string }) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState("");
  const [routeForm, setRouteForm] = useState<{ flightNumber: string; origin: string; destination: string; days: number[]; validFrom: string; validTo: string; notes: string } | null>(null);
  const [oneOff, setOneOff] = useState<{ flightNumber: string; date: string; originId: string; destinationId: string; reason: string } | null>(null);
  const [cancelling, setCancelling] = useState<Leg | null>(null);
  const [deactivating, setDeactivating] = useState<Route | null>(null);

  const shown = useMemo(() => {
    const q = filter.trim().toUpperCase();
    return q ? routes.filter((r) => r.flight_number.toUpperCase().includes(q) || r.origin_code === q || r.destination_code === q) : routes;
  }, [routes, filter]);

  function run(fn: () => Promise<{ ok: true } | { ok: false; error: string }>, done?: () => void) {
    setError(null);
    startTransition(async () => {
      const r = await fn();
      if (!r.ok) return setError(r.error);
      done?.();
      router.refresh();
    });
  }

  return (
    <div className="space-y-6">
      {error && <p className="rounded-sm px-3 py-2 text-sm text-(--brick)" style={{ background: "var(--brick-surface)" }}>{error}</p>}

      {canManage && (
        <div className="flex flex-wrap gap-3">
          {!routeForm && <button className="btn-primary px-4 py-2 text-sm" onClick={() => setRouteForm({ flightNumber: "", origin: "", destination: "", days: [], validFrom: today, validTo: "", notes: "" })}>Add scheduled flight</button>}
          {!oneOff && <button className="btn-secondary px-4 py-2 text-sm" onClick={() => setOneOff({ flightNumber: "", date: today, originId: "", destinationId: "", reason: "" })}>Add one-off flight</button>}
        </div>
      )}

      {routeForm && (
        <form className="panel space-y-3 p-4" onSubmit={(e) => { e.preventDefault(); run(() => createRoute(routeForm), () => setRouteForm(null)); }}>
          <h2 className="font-semibold text-(--navy)">New scheduled flight</h2>
          <div className="grid gap-3 sm:grid-cols-4">
            <div><label className="mb-1 block text-xs text-(--steel)">Flight number</label>
              <input required placeholder="UR110" value={routeForm.flightNumber} onChange={(e) => setRouteForm({ ...routeForm, flightNumber: e.target.value.toUpperCase() })} className={`${input} id-code`} /></div>
            <div><label className="mb-1 block text-xs text-(--steel)">From</label>
              <select required value={routeForm.origin} onChange={(e) => setRouteForm({ ...routeForm, origin: e.target.value })} className={input}>
                <option value="">Select</option>{stations.map((s) => <option key={s.id} value={s.code}>{s.code} — {s.name}</option>)}</select></div>
            <div><label className="mb-1 block text-xs text-(--steel)">To</label>
              <select required value={routeForm.destination} onChange={(e) => setRouteForm({ ...routeForm, destination: e.target.value })} className={input}>
                <option value="">Select</option>{stations.map((s) => <option key={s.id} value={s.code}>{s.code} — {s.name}</option>)}</select></div>
            <div><label className="mb-1 block text-xs text-(--steel)">Starts</label>
              <input required type="date" value={routeForm.validFrom} onChange={(e) => setRouteForm({ ...routeForm, validFrom: e.target.value })} className={input} /></div>
            <div><label className="mb-1 block text-xs text-(--steel)">Ends (optional)</label>
              <input type="date" value={routeForm.validTo} onChange={(e) => setRouteForm({ ...routeForm, validTo: e.target.value })} className={input} /></div>
            <div className="sm:col-span-3"><label className="mb-1 block text-xs text-(--steel)">Notes</label>
              <input value={routeForm.notes} onChange={(e) => setRouteForm({ ...routeForm, notes: e.target.value })} className={input} /></div>
          </div>
          <fieldset><legend className="mb-1 text-xs text-(--steel)">Operating days</legend>
            <div className="flex flex-wrap gap-3">
              {DAYS.map((d, i) => (
                <label key={d} className="flex items-center gap-1.5 text-sm">
                  <input type="checkbox" checked={routeForm.days.includes(i + 1)}
                    onChange={(e) => setRouteForm({ ...routeForm, days: e.target.checked ? [...routeForm.days, i + 1].sort() : routeForm.days.filter((x) => x !== i + 1) })} />{d}
                </label>
              ))}
            </div></fieldset>
          <div className="flex gap-3">
            <button className="btn-primary px-4 py-2 text-sm" disabled={pending || routeForm.days.length === 0}>{pending ? "Saving…" : "Save"}</button>
            <button type="button" className="btn-secondary px-4 py-2 text-sm" onClick={() => setRouteForm(null)}>Cancel</button>
          </div>
        </form>
      )}

      {oneOff && (
        <form className="panel space-y-3 p-4" onSubmit={(e) => { e.preventDefault(); run(() => createOneOffLeg(oneOff), () => setOneOff(null)); }}>
          <h2 className="font-semibold text-(--navy)">New one-off flight</h2>
          <div className="grid gap-3 sm:grid-cols-4">
            <div><label className="mb-1 block text-xs text-(--steel)">Flight number</label>
              <input required placeholder="UR110" value={oneOff.flightNumber} onChange={(e) => setOneOff({ ...oneOff, flightNumber: e.target.value.toUpperCase() })} className={`${input} id-code`} /></div>
            <div><label className="mb-1 block text-xs text-(--steel)">Date</label>
              <input required type="date" value={oneOff.date} onChange={(e) => setOneOff({ ...oneOff, date: e.target.value })} className={input} /></div>
            <div><label className="mb-1 block text-xs text-(--steel)">From</label>
              <select required value={oneOff.originId} onChange={(e) => setOneOff({ ...oneOff, originId: e.target.value })} className={input}>
                <option value="">Select</option>{stations.map((s) => <option key={s.id} value={s.id}>{s.code} — {s.name}</option>)}</select></div>
            <div><label className="mb-1 block text-xs text-(--steel)">To</label>
              <select required value={oneOff.destinationId} onChange={(e) => setOneOff({ ...oneOff, destinationId: e.target.value })} className={input}>
                <option value="">Select</option>{stations.map((s) => <option key={s.id} value={s.id}>{s.code} — {s.name}</option>)}</select></div>
            <div className="sm:col-span-4"><label className="mb-1 block text-xs text-(--steel)">Why is this flight not in the schedule?</label>
              <input required value={oneOff.reason} onChange={(e) => setOneOff({ ...oneOff, reason: e.target.value })} className={input} /></div>
          </div>
          <div className="flex gap-3">
            <button className="btn-primary px-4 py-2 text-sm" disabled={pending}>{pending ? "Saving…" : "Save"}</button>
            <button type="button" className="btn-secondary px-4 py-2 text-sm" onClick={() => setOneOff(null)}>Cancel</button>
          </div>
        </form>
      )}

      <section>
        <h2 className="mb-2 font-semibold text-(--navy)">Upcoming dated flights</h2>
        <div className="panel overflow-x-auto">
          {legs.length === 0 ? (
            <p className="p-4 text-sm text-(--steel)">No dated flights yet. They appear here when someone links a movement to a scheduled flight.</p>
          ) : (
            <table className="w-full min-w-[560px] text-sm">
              <thead className="text-left text-sm text-(--steel)"><tr><th className="p-3">Date</th><th className="p-3">Flight</th><th className="p-3">Route</th><th className="p-3">Status</th><th className="p-3" /></tr></thead>
              <tbody>
                {legs.map((l) => (
                  <tr key={l.id} className="border-t border-(--border)">
                    <td className="p-3">{fmt(l.operating_date)}</td>
                    <td className="id-code p-3">{l.flight_number}{l.is_one_off && <span className="tag tag-amber ml-2">One-off</span>}</td>
                    <td className="p-3">{l.origin_code} to {l.destination_code}</td>
                    <td className="p-3">{l.status === "CANCELLED" ? <span className="tag tag-brick" title={l.cancel_reason ?? ""}>Cancelled</span> : <span className="tag tag-teal">Scheduled</span>}</td>
                    <td className="p-3 text-right">{canManage && l.status === "SCHEDULED" && <button className="text-(--steel) hover:underline" disabled={pending} onClick={() => setCancelling(l)}>Cancel flight</button>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </section>

      <section>
        <div className="mb-2 flex flex-wrap items-center justify-between gap-3">
          <h2 className="font-semibold text-(--navy)">Flight schedule ({routes.length})</h2>
          <input aria-label="Filter the schedule" placeholder="Filter by flight or station" value={filter} onChange={(e) => setFilter(e.target.value)} className={`${input} max-w-60`} />
        </div>
        <div className="panel overflow-x-auto">
          <table className="w-full min-w-[640px] text-sm">
            <thead className="text-left text-sm text-(--steel)"><tr><th className="p-3">Flight</th><th className="p-3">Route</th><th className="p-3">Days</th><th className="p-3">Season</th><th className="p-3">Status</th><th className="p-3" /></tr></thead>
            <tbody>
              {shown.map((r) => (
                <tr key={r.id} className="border-t border-(--border)">
                  <td className="id-code p-3">{r.flight_number}</td>
                  <td className="p-3">{r.origin_code} to {r.destination_code}</td>
                  <td className="p-3 text-(--steel)">{r.operating_days.length === 7 ? "Daily" : r.operating_days.map((d) => DAYS[d - 1]).join(", ")}</td>
                  <td className="p-3 text-(--steel)">{fmt(r.valid_from)}{r.valid_to ? ` to ${fmt(r.valid_to)}` : " onwards"}</td>
                  <td className="p-3">{r.is_active ? <span className="tag tag-teal">Active</span> : <span className="tag tag-brick">Inactive</span>}</td>
                  <td className="whitespace-nowrap p-3 text-right">
                    {canManage && <button className="text-(--steel) hover:underline" disabled={pending}
                      onClick={() => (r.is_active ? setDeactivating(r) : run(() => setRouteActive(r.id, true, "Reactivated")))}>{r.is_active ? "Deactivate" : "Reactivate"}</button>}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <ConfirmDialog open={cancelling !== null} danger pending={pending}
        title={`Cancel flight ${cancelling?.flight_number ?? ""} on ${cancelling ? fmt(cancelling.operating_date) : ""}?`}
        description="Transfers linked to this flight cannot be dispatched until another flight is chosen. Movements already in transit are not affected."
        reasonLabel="Reason for cancelling" confirmLabel="Cancel flight"
        onCancel={() => setCancelling(null)}
        onConfirm={(reason) => { const l = cancelling; setCancelling(null); if (l) run(() => cancelLeg(l.id, reason)); }} />
      <ConfirmDialog open={deactivating !== null} danger pending={pending}
        title={`Deactivate flight ${deactivating?.flight_number ?? ""} (${deactivating?.origin_code ?? ""} to ${deactivating?.destination_code ?? ""})?`}
        description="No new dated flights can be created from it. Existing dated flights and past movements keep their details."
        reasonLabel="Reason for deactivating" confirmLabel="Deactivate"
        onCancel={() => setDeactivating(null)}
        onConfirm={(reason) => { const r = deactivating; setDeactivating(null); if (r) run(() => setRouteActive(r.id, false, reason)); }} />
    </div>
  );
}
