import type { SupabaseClient } from "@supabase/supabase-js";

// Action Required rules (ACOMS-DESIGN-001 s9). One alert per unresolved condition,
// sorted by severity, then by kind (order below), then by urgency within the kind.
//   critical : critical shortage, transfer discrepancy
//   warning  : overdue transfer, open loss report, open damage report, critical surplus
//   attention: stock adjustment waiting for your approval
// Plain shortages are not alerts; they are on the Inventory Health card and station table.

export type Severity = "critical" | "warning" | "attention";

export interface Alert {
  key: string;
  severity: Severity;
  label: string;
  station: string | null;
  reference: string | null;
  detail: string;
  href: string;
  actions: { label: string; href: string }[];
  kindOrder: number;
  urgency: number;
}

const SEV_ORDER: Record<Severity, number> = { critical: 0, warning: 1, attention: 2 };

interface InvRow {
  station_id: string;
  station_code: string;
  source_code: string;
  equipment_name: string;
  current_stock: number;
  minimum_level: number | null;
  status: string;
}

const days = (hours: number) => {
  const d = Math.floor(hours / 24);
  return d >= 1 ? `${d} ${d === 1 ? "day" : "days"}` : `${Math.max(1, Math.floor(hours))} h`;
};
const n = (v: number) => v.toLocaleString("en-GB");

export async function fetchAlertSources(supabase: SupabaseClient, perms: Set<string>) {
  const canApprove = perms.has("approve_adjustment");
  const [overdue, adjustments, stations, exceptions] = await Promise.all([
    supabase.from("v_pending_transfers").select("id, transfer_number, status, from_station_code, to_station_code, hours_since_requested").eq("is_overdue", true),
    canApprove
      ? supabase.from("v_stock_adjustments").select("id, adjustment_number, station_code, source_code, direction, quantity, requested_at, requested_by").eq("status", "REQUESTED")
      : Promise.resolve({ data: [], error: null }),
    supabase.from("stations").select("id, code"),
    supabase.from("v_unresolved_exceptions").select("*").order("updated_at", { ascending: true }),
  ]);
  return { overdue, adjustments, stations, exceptions };
}

export function buildAlerts(opts: {
  invRows: InvRow[];
  sources: Awaited<ReturnType<typeof fetchAlertSources>>;
  perms: Set<string>;
  userId: string | null;
}): Alert[] {
  const { invRows, sources, perms, userId } = opts;
  const canTransfer = perms.has("create_transfer");
  const stationCode = new Map<string, string>((sources.stations.data ?? []).map((s: any) => [s.id, s.code]));
  const out: Alert[] = [];

  for (const r of invRows) {
    if (r.status !== "CRITICAL_SHORTAGE" && r.status !== "CRITICAL_SURPLUS") continue;
    const short = r.status === "CRITICAL_SHORTAGE";
    const min = r.minimum_level;
    out.push({
      key: `stock-${r.station_id}-${r.source_code}`,
      severity: short ? "critical" : "warning",
      label: short ? "Critical shortage" : "Critical surplus",
      station: r.station_code,
      reference: r.source_code,
      detail: `${r.equipment_name}: ${n(r.current_stock)} available${min != null ? `, minimum ${n(min)}` : ""}`,
      href: `/dashboard/station-inventory?station=${encodeURIComponent(r.station_code)}&q=${encodeURIComponent(r.source_code)}`,
      actions: canTransfer ? [{ label: short ? "Request transfer" : "Redistribute", href: "/transfers/new" }] : [],
      kindOrder: short ? 0 : 3,
      urgency: short && min ? min - r.current_stock : r.current_stock - (min ?? 0),
    });
  }

  for (const e of (sources.exceptions.data ?? []) as any[]) {
    const station = stationCode.get(e.station_id) ?? null;
    if (e.exception_type === "TRANSFER_DISCREPANCY") {
      out.push({
        key: `disc-${e.id}`, severity: "critical", label: "Transfer discrepancy", station, reference: e.reference,
        detail: "Received quantities differ beyond tolerance. It cannot close until resolved with a documented reason.",
        href: `/transfers/${e.id}`, actions: [{ label: "Review", href: `/transfers/${e.id}` }], kindOrder: 1, urgency: ageHours(e.updated_at),
      });
    } else {
      const loss = e.exception_type === "LOSS_PENDING";
      const href = `/damage-loss/${e.id}?type=${loss ? "loss" : "damage"}`;
      out.push({
        key: `${loss ? "loss" : "dmg"}-${e.id}`, severity: "warning", label: loss ? "Open loss report" : "Open damage report", station, reference: e.reference,
        detail: loss ? "Reported missing. Not a confirmed loss until investigated." : "Damaged equipment awaiting a decision.",
        href, actions: [{ label: "Review", href }], kindOrder: loss ? 2 : 4, urgency: ageHours(e.updated_at),
      });
    }
  }

  for (const t of (sources.overdue.data ?? []) as any[]) {
    const waiting = t.status === "REQUESTED";
    out.push({
      key: `overdue-${t.id}`, severity: "warning", label: "Overdue transfer", station: t.from_station_code,
      reference: t.transfer_number,
      detail: `${t.from_station_code} to ${t.to_station_code}. ${waiting ? "Waiting for approval" : "Open"} for ${days(t.hours_since_requested)}.`,
      href: `/transfers/${t.id}`, actions: [{ label: "Open transfer", href: `/transfers/${t.id}` }],
      kindOrder: 1.5, urgency: t.hours_since_requested,
    });
  }

  for (const a of (sources.adjustments.data ?? []) as any[]) {
    if (a.requested_by === userId) continue; // you cannot approve your own request
    out.push({
      key: `adj-${a.id}`, severity: "attention", label: "Adjustment awaiting your approval", station: a.station_code,
      reference: a.adjustment_number,
      detail: `${a.source_code}: ${a.direction === "INCREASE" ? "increase" : "decrease"} of ${n(a.quantity)}. Requested ${days(ageHours(a.requested_at))} ago.`,
      href: `/admin/adjustments/${a.id}`, actions: [{ label: "Review", href: `/admin/adjustments/${a.id}` }],
      kindOrder: 5, urgency: ageHours(a.requested_at),
    });
  }

  return out.sort(
    (x, y) => SEV_ORDER[x.severity] - SEV_ORDER[y.severity] || x.kindOrder - y.kindOrder || y.urgency - x.urgency
  );
}

function ageHours(iso: string) {
  return Math.max(0, (Date.now() - new Date(iso).getTime()) / 36e5);
}
