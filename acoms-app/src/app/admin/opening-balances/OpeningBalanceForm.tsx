"use client";

import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { submitOpeningBalances } from "./actions";

type Station = { id: string; code: string; name: string };
type Equipment = { id: string; source_code: string; name: string };

export function OpeningBalanceForm({
  stations,
  equipment,
  recorded,
}: {
  stations: Station[];
  equipment: Equipment[];
  recorded: string[];
}) {
  const router = useRouter();
  const [stationId, setStationId] = useState("");
  const [search, setSearch] = useState("");
  const [qty, setQty] = useState<Record<string, string>>({});
  const [reason, setReason] = useState("");
  const [reviewing, setReviewing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<number | null>(null);
  const [pending, startTransition] = useTransition();

  const recordedSet = useMemo(() => new Set(recorded), [recorded]);
  const station = stations.find((s) => s.id === stationId);

  const visible = equipment.filter((e) => {
    const q = search.trim().toLowerCase();
    return !q || e.name.toLowerCase().includes(q) || e.source_code.toLowerCase().includes(q);
  });

  const entries = equipment
    .map((e) => ({ e, n: Number(qty[e.id]) }))
    .filter((x) => qty[x.e.id] !== undefined && qty[x.e.id] !== "" && !recordedSet.has(`${stationId}:${x.e.id}`));
  const invalid = entries.some((x) => !Number.isInteger(x.n) || x.n <= 0);

  function pickStation(id: string) {
    setStationId(id);
    setQty({});
    setReviewing(false);
    setError(null);
    setDone(null);
  }

  function submit() {
    setError(null);
    startTransition(async () => {
      const res = await submitOpeningBalances(
        stationId,
        entries.map((x) => ({ equipment_type_id: x.e.id, quantity: x.n })),
        reason
      );
      if (!res.ok) {
        setError(res.error);
        return;
      }
      setDone(res.count);
      setQty({});
      setReviewing(false);
      router.refresh();
    });
  }

  return (
    <div className="space-y-4">
      <div className="panel p-4">
        <label className="mb-1 block text-sm font-medium">Station</label>
        <select
          value={stationId}
          onChange={(e) => pickStation(e.target.value)}
          className="w-full max-w-xs rounded-sm border border-(--border) px-3 py-2 text-sm"
        >
          <option value="">Select a station…</option>
          {stations.map((s) => (
            <option key={s.id} value={s.id}>
              {s.code} — {s.name}
            </option>
          ))}
        </select>
        <p className="mt-2 text-xs text-(--steel)">No-stock turnaround stations are not listed; they hold no equipment.</p>
      </div>

      {done !== null && (
        <p className="rounded-sm px-3 py-2 text-sm text-(--teal)" style={{ background: "var(--teal-surface)" }}>
          Recorded {done} opening balance{done === 1 ? "" : "s"} for {station?.code}.
        </p>
      )}
      {error && (
        <p className="rounded-sm px-3 py-2 text-sm text-(--brick)" style={{ background: "var(--brick-surface)" }}>
          {error}
        </p>
      )}

      {station && !reviewing && (
        <div className="panel p-4">
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search equipment by name or code"
            className="mb-3 w-full max-w-sm rounded-sm border border-(--border) px-3 py-2 text-sm"
          />
          <div className="max-h-[28rem] overflow-y-auto">
            <table className="w-full text-sm">
              <thead className="sticky top-0 bg-(--color-surface) text-left text-xs text-(--steel)">
                <tr>
                  <th className="py-2">Code</th>
                  <th className="py-2">Equipment</th>
                  <th className="py-2 text-right">Opening quantity</th>
                </tr>
              </thead>
              <tbody>
                {visible.map((e) => {
                  const isRecorded = recordedSet.has(`${stationId}:${e.id}`);
                  return (
                    <tr key={e.id} className="border-t border-(--border)">
                      <td className="id-code py-2">{e.source_code}</td>
                      <td className="py-2">{e.name}</td>
                      <td className="py-2 text-right">
                        {isRecorded ? (
                          <span className="tag tag-teal">Recorded</span>
                        ) : (
                          <input
                            type="number"
                            min={1}
                            step={1}
                            value={qty[e.id] ?? ""}
                            onChange={(ev) => setQty({ ...qty, [e.id]: ev.target.value })}
                            className="w-28 rounded-sm border border-(--border) px-2 py-1 text-right"
                          />
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
          <div className="mt-4 flex items-center justify-between">
            <span className="text-sm text-(--steel)">{entries.length} item(s) entered</span>
            <button
              className="btn-primary px-4 py-2 text-sm"
              disabled={entries.length === 0 || invalid}
              onClick={() => setReviewing(true)}
            >
              Review
            </button>
          </div>
          {invalid && <p className="mt-2 text-xs text-(--brick)">Quantities must be whole numbers greater than zero.</p>}
        </div>
      )}

      {station && reviewing && (
        <div className="panel p-4">
          <h2 className="mb-2 font-semibold text-(--navy)">
            Review — {station.code} {station.name}
          </h2>
          <p className="mb-3 text-sm text-(--amber)">These cannot be edited afterwards, only adjusted. Check carefully.</p>
          <table className="mb-4 w-full text-sm">
            <tbody>
              {entries.map((x) => (
                <tr key={x.e.id} className="border-t border-(--border)">
                  <td className="id-code py-1.5">{x.e.source_code}</td>
                  <td className="py-1.5">{x.e.name}</td>
                  <td className="py-1.5 text-right font-medium">{x.n}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <label className="mb-1 block text-sm font-medium">Note (optional)</label>
          <input
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            placeholder="e.g. Physical count 1 Nov"
            className="mb-4 w-full rounded-sm border border-(--border) px-3 py-2 text-sm"
          />
          <div className="flex gap-3">
            <button className="btn-secondary px-4 py-2 text-sm" onClick={() => setReviewing(false)} disabled={pending}>
              Back
            </button>
            <button className="btn-primary px-4 py-2 text-sm" onClick={submit} disabled={pending}>
              {pending ? "Recording…" : "Confirm and record"}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
