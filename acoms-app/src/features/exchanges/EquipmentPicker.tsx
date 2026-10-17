"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type Equip = { id: string; source_code: string; name: string; category: { name: string } | null };
export type Selection = Record<string, number>;

/**
 * Every equipment item in one table: tick what is going, type the quantity, read the advice.
 * Outbound lists the whole catalogue; a return lists what the outstation holds (switch to show all).
 * Quantities above what the source holds are flagged here; dispatch still checks the real stock.
 */
export function EquipmentPicker({
  mode, fromStationId, fromCode, toStationId, toCode, outboundTransferId, value, onChange,
}: {
  mode: "outbound" | "return";
  fromStationId: string;
  fromCode: string;
  toStationId?: string;
  toCode?: string;
  outboundTransferId?: string | null;
  value: Selection;
  onChange: (v: Selection) => void;
}) {
  const [items, setItems] = useState<Equip[] | null>(null);
  const [fromStock, setFromStock] = useState<Record<string, number>>({});
  const [toStock, setToStock] = useState<Record<string, number>>({});
  const [fromHub, setFromHub] = useState<Record<string, number>>({});
  const [last, setLast] = useState<{ number: string; date: string; lines: Selection } | null>(null);
  const [q, setQ] = useState("");
  const [showAll, setShowAll] = useState(false);
  const [onlyTicked, setOnlyTicked] = useState(false);
  const inputs = useRef<Record<string, HTMLInputElement | null>>({});

  useEffect(() => {
    const sb = createClient();
    sb.from("equipment_types").select("id, source_code, name, category:category_id(name)").eq("is_active", true).order("name")
      .then(({ data }) => setItems((data as unknown as Equip[]) ?? []));
  }, []);

  useEffect(() => {
    if (!fromStationId) return;
    createClient().from("inventory_balances").select("equipment_type_id, available_quantity").eq("station_id", fromStationId)
      .then(({ data }) => setFromStock(Object.fromEntries(((data ?? []) as { equipment_type_id: string; available_quantity: number }[]).map((r) => [r.equipment_type_id, r.available_quantity]))));
  }, [fromStationId]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    if (!toStationId) { setToStock({}); return; }
    createClient().from("inventory_balances").select("equipment_type_id, available_quantity").eq("station_id", toStationId)
      .then(({ data }) => setToStock(Object.fromEntries(((data ?? []) as { equipment_type_id: string; available_quantity: number }[]).map((r) => [r.equipment_type_id, r.available_quantity]))));
  }, [toStationId]);

  // Return: what the hub sent out, as advice.
  useEffect(() => {
    if (mode !== "return" || !outboundTransferId) return;
    createClient().from("equipment_transfer_items").select("equipment_type_id, quantity_received").eq("transfer_id", outboundTransferId)
      .then(({ data }) => setFromHub(Object.fromEntries(((data ?? []) as { equipment_type_id: string; quantity_received: number | null }[]).map((r) => [r.equipment_type_id, r.quantity_received ?? 0]))));
  }, [mode, outboundTransferId]);

  // Outbound: the last exchange to this outstation, for the repeat button.
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    if (mode !== "outbound" || !toStationId) { setLast(null); return; }
    const sb = createClient();
    let stale = false;
    sb.from("v_equipment_exchanges").select("exchange_number, created_at, outbound_id").eq("outstation_id", toStationId)
      .neq("status", "CANCELLED").not("outbound_id", "is", null).order("created_at", { ascending: false }).limit(1)
      .then(async ({ data }) => {
        const ex = (data as { exchange_number: string; created_at: string; outbound_id: string }[] | null)?.[0];
        if (!ex || stale) { if (!stale) setLast(null); return; }
        const { data: lines } = await sb.from("equipment_transfer_items").select("equipment_type_id, quantity_requested, quantity_dispatched").eq("transfer_id", ex.outbound_id);
        if (stale) return;
        const sel: Selection = {};
        for (const l of (lines ?? []) as { equipment_type_id: string; quantity_requested: number; quantity_dispatched: number | null }[]) sel[l.equipment_type_id] = l.quantity_dispatched ?? l.quantity_requested;
        setLast({ number: ex.exchange_number, date: ex.created_at, lines: sel });
      });
    return () => { stale = true; };
  }, [mode, toStationId]);

  const visible = useMemo(() => {
    const term = q.trim().toLowerCase();
    return (items ?? []).filter((e) => {
      if (term && !`${e.source_code} ${e.name}`.toLowerCase().includes(term)) return false;
      if (onlyTicked && !(e.id in value)) return false;
      if (!showAll && !(e.id in value) && (fromStock[e.id] ?? 0) <= 0) return false;
      return true;
    });
  }, [items, q, onlyTicked, showAll, value, fromStock]);

  const groups = useMemo(() => {
    const m = new Map<string, Equip[]>();
    for (const e of visible) { const k = e.category?.name ?? "Other"; m.set(k, [...(m.get(k) ?? []), e]); }
    return [...m.entries()];
  }, [visible]);

  function toggle(id: string, on: boolean) {
    const next = { ...value };
    if (on) { next[id] = next[id] ?? 1; } else { delete next[id]; }
    onChange(next);
    if (on) setTimeout(() => { inputs.current[id]?.focus(); inputs.current[id]?.select(); }, 0);
  }
  const ticked = Object.keys(value).length;
  const total = Object.values(value).reduce((a, b) => a + (b || 0), 0);

  function advice(e: Equip) {
    const mine = fromStock[e.id] ?? 0;
    const qty = value[e.id] ?? 0;
    const bits: string[] = [`Available at ${fromCode}: ${mine.toLocaleString("en-GB")}`];
    if (mode === "outbound" && toCode && e.id in toStock) bits.push(`${toCode} holds ${toStock[e.id].toLocaleString("en-GB")}`);
    if (mode === "return" && fromHub[e.id]) bits.push(`Received from hub: ${fromHub[e.id].toLocaleString("en-GB")}`);
    return { text: bits.join(" · "), warn: qty > mine ? `Only ${mine.toLocaleString("en-GB")} available at ${fromCode}. Dispatch will need the stock to be there.` : null };
  }

  if (items === null) return <p className="text-sm text-(--color-text-subtle)">Loading equipment…</p>;

  return (
    <div>
      <div className="mb-3 flex flex-wrap items-center gap-3">
        <input type="search" aria-label="Search equipment" placeholder="Search by code or name" value={q} onChange={(e) => setQ(e.target.value)} className="min-h-11 w-full px-3 py-2 text-sm sm:w-72" />
        <label className="flex min-h-11 items-center gap-2 text-sm"><input type="checkbox" checked={onlyTicked} onChange={(e) => setOnlyTicked(e.target.checked)} /> Selected only</label>
        <label className="flex min-h-11 items-center gap-2 text-sm"><input type="checkbox" checked={showAll} onChange={(e) => setShowAll(e.target.checked)} /> Show all equipment, not just what {fromCode} holds</label>
        {mode === "outbound" && last && (
          <button type="button" className="btn-secondary min-h-11 px-4 text-sm" onClick={() => onChange({ ...last.lines })}>
            Repeat last exchange to {toCode} ({last.number}, {new Date(last.date).toLocaleDateString("en-GB", { day: "numeric", month: "short" })})
          </button>
        )}
        {ticked > 0 && <button type="button" className="text-sm font-semibold text-(--color-primary) hover:underline" onClick={() => onChange({})}>Clear all</button>}
      </div>

      <div className="panel overflow-x-auto">
        <table className="w-full min-w-[34rem] text-sm">
          <thead className="bg-(--steel-light) text-left font-medium text-(--steel)">
            <tr>
              <th className="px-3 py-2">Equipment</th>
              <th className="w-16 px-3 py-2 text-center">Send</th>
              <th className="w-28 px-3 py-2">Quantity</th>
              <th className="px-3 py-2">Advice</th>
            </tr>
          </thead>
          <tbody>
            {groups.length === 0 && (
              <tr><td colSpan={4} className="px-3 py-6 text-center text-(--color-text-subtle)">No equipment matches.{!showAll ? ` ${fromCode} holds nothing that matches. Switch on “Show all equipment” to see the rest.` : ""}</td></tr>
            )}
            {groups.map(([cat, list]) => (
              <GroupRows key={cat} cat={cat}>
                {list.map((e) => {
                  const on = e.id in value;
                  const a = advice(e);
                  return (
                    <tr key={e.id} className={`border-t border-(--border) ${on ? "bg-(--color-primary-soft)" : ""}`}>
                      <td className="px-3 py-2">
                        <label htmlFor={`eq-${e.id}`} className="block cursor-pointer">
                          <span className="font-medium text-(--color-text)">{e.source_code}</span> <span>{e.name}</span>
                        </label>
                      </td>
                      <td className="px-3 py-2 text-center">
                        <input id={`eq-${e.id}`} type="checkbox" className="h-5 w-5" checked={on} onChange={(ev) => toggle(e.id, ev.target.checked)} aria-label={`Include ${e.name}`} />
                      </td>
                      <td className="px-3 py-2">
                        <input
                          ref={(el) => { inputs.current[e.id] = el; }}
                          type="number" min={1} inputMode="numeric" disabled={!on} aria-label={`Quantity of ${e.name}`}
                          value={on ? (value[e.id] || "") : ""}
                          onChange={(ev) => onChange({ ...value, [e.id]: Math.max(0, Math.floor(Number(ev.target.value))) })}
                          className="min-h-11 w-24 px-2 py-1 disabled:opacity-40"
                        />
                      </td>
                      <td className="px-3 py-2 text-xs text-(--color-text-subtle)">
                        {a.text}
                        {on && a.warn && <span className="mt-1 block font-medium text-(--color-warning)">{a.warn}</span>}
                      </td>
                    </tr>
                  );
                })}
              </GroupRows>
            ))}
          </tbody>
        </table>
      </div>
      <p className="mt-3 text-sm text-(--color-text-muted)" aria-live="polite">{ticked === 0 ? "Nothing selected yet." : `${ticked} item${ticked === 1 ? "" : "s"} selected, ${total.toLocaleString("en-GB")} units in total.`}</p>
    </div>
  );
}

function GroupRows({ cat, children }: { cat: string; children: React.ReactNode }) {
  return (
    <>
      <tr className="bg-(--color-surface-subtle)"><th colSpan={4} className="px-3 py-1.5 text-left text-xs font-semibold text-(--color-text-muted)">{cat}</th></tr>
      {children}
    </>
  );
}
