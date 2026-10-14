"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { saveStation, setStationActive } from "./actions";

type Station = { id: string; code: string; name: string; station_type: string; airport_code: string | null; country: string | null; timezone: string | null; is_active: boolean };
type Form = { id: string | null; code: string; name: string; stationType: string; airportCode: string; country: string; timezone: string };

const TYPE_LABEL: Record<string, string> = { HUB: "Hub", STOCK_HOLDING: "Stock-holding", NO_STOCK_TURNAROUND: "No-stock turnaround" };
const blank: Form = { id: null, code: "", name: "", stationType: "STOCK_HOLDING", airportCode: "", country: "", timezone: "" };
const input = "w-full rounded-sm border border-(--border) px-2 py-1.5 text-sm";

export function StationManager({ stations, canEdit }: { stations: Station[]; canEdit: boolean }) {
  const router = useRouter();
  const [form, setForm] = useState<Form | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function save(e: React.FormEvent) {
    e.preventDefault();
    if (!form) return;
    setError(null);
    startTransition(async () => {
      const r = await saveStation(form);
      if (!r.ok) return setError(r.error);
      setForm(null);
      router.refresh();
    });
  }

  function toggle(s: Station) {
    setError(null);
    const reason = s.is_active ? prompt(`Reason for deactivating ${s.code}?`) : "";
    if (s.is_active && !reason) return;
    startTransition(async () => {
      const r = await setStationActive(s.id, !s.is_active, reason ?? "");
      if (!r.ok) return setError(r.error);
      router.refresh();
    });
  }

  return (
    <div className="space-y-4">
      {error && <p className="rounded-sm px-3 py-2 text-sm text-(--brick)" style={{ background: "var(--brick-surface)" }}>{error}</p>}
      {canEdit && !form && <button className="btn-primary px-4 py-2 text-sm" onClick={() => setForm(blank)}>New station</button>}

      {form && (
        <form onSubmit={save} className="panel space-y-3 p-4">
          <h2 className="font-semibold text-(--navy)">{form.id ? `Edit ${form.code}` : "New station"}</h2>
          <div className="grid gap-3 sm:grid-cols-3">
            <div><label className="mb-1 block text-xs text-(--steel)">Code</label>
              <input required disabled={!!form.id} value={form.code} onChange={(e) => setForm({ ...form, code: e.target.value.toUpperCase() })} className={`${input} id-code`} /></div>
            <div className="sm:col-span-2"><label className="mb-1 block text-xs text-(--steel)">Name</label>
              <input required value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} className={input} /></div>
            <div><label className="mb-1 block text-xs text-(--steel)">Type</label>
              <select value={form.stationType} onChange={(e) => setForm({ ...form, stationType: e.target.value })} className={input}>
                <option value="HUB">Hub</option><option value="STOCK_HOLDING">Stock-holding</option><option value="NO_STOCK_TURNAROUND">No-stock turnaround</option>
              </select></div>
            <div><label className="mb-1 block text-xs text-(--steel)">Airport code</label>
              <input value={form.airportCode} onChange={(e) => setForm({ ...form, airportCode: e.target.value })} className={input} /></div>
            <div><label className="mb-1 block text-xs text-(--steel)">Country</label>
              <input value={form.country} onChange={(e) => setForm({ ...form, country: e.target.value })} className={input} /></div>
            <div className="sm:col-span-3"><label className="mb-1 block text-xs text-(--steel)">Timezone</label>
              <input value={form.timezone} onChange={(e) => setForm({ ...form, timezone: e.target.value })} placeholder="e.g. Africa/Kampala" className={input} /></div>
          </div>
          <div className="flex gap-3">
            <button className="btn-primary px-4 py-2 text-sm" disabled={pending}>{pending ? "Saving…" : "Save"}</button>
            <button type="button" className="btn-secondary px-4 py-2 text-sm" onClick={() => setForm(null)}>Cancel</button>
          </div>
        </form>
      )}

      <div className="panel overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="text-left text-xs uppercase text-(--steel)">
            <tr><th className="p-3">Code</th><th className="p-3">Name</th><th className="p-3">Type</th><th className="p-3">Country</th><th className="p-3">Status</th><th className="p-3" /></tr>
          </thead>
          <tbody>
            {stations.map((s) => (
              <tr key={s.id} className="border-t border-(--border)">
                <td className="id-code p-3">{s.code}</td>
                <td className="p-3">{s.name}</td>
                <td className="p-3"><span className={`tag ${s.station_type === "HUB" ? "tag-navy" : s.station_type === "NO_STOCK_TURNAROUND" ? "tag-amber" : "tag-neutral"}`}>{TYPE_LABEL[s.station_type]}</span></td>
                <td className="p-3 text-(--steel)">{s.country ?? "—"}</td>
                <td className="p-3">{s.is_active ? <span className="tag tag-teal">Active</span> : <span className="tag tag-brick">Inactive</span>}</td>
                <td className="whitespace-nowrap p-3 text-right">
                  {canEdit && (
                    <>
                      <button className="mr-3 text-(--navy) hover:underline" onClick={() => setForm({ id: s.id, code: s.code, name: s.name, stationType: s.station_type, airportCode: s.airport_code ?? "", country: s.country ?? "", timezone: s.timezone ?? "" })}>Edit</button>
                      {s.station_type !== "HUB" && <button className="text-(--steel) hover:underline" disabled={pending} onClick={() => toggle(s)}>{s.is_active ? "Deactivate" : "Reactivate"}</button>}
                    </>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
