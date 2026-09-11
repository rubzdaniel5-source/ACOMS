import Link from "next/link";
import { createClient } from "@/lib/supabase/server";

function SummaryCard({ label, value, tone = "default" }: { label: string; value: number | string; tone?: "default" | "warning" | "danger" }) {
  const toneClass =
    tone === "danger" ? "text-red-600" : tone === "warning" ? "text-amber-600" : "text-slate-900";
  return (
    <div className="rounded-lg border border-slate-200 p-4">
      <div className="text-xs font-medium uppercase tracking-wide text-slate-500">{label}</div>
      <div className={`mt-1 text-2xl font-semibold ${toneClass}`}>{value}</div>
    </div>
  );
}

export default async function DashboardPage() {
  const supabase = await createClient();

  const [networkSummary, shortages, pendingTransfers, exceptions, recentActivity] = await Promise.all([
    supabase.from("v_network_inventory_summary").select("*").order("source_code"),
    supabase.from("v_station_inventory_status").select("*").eq("stock_status", "SHORTAGE").order("station_code"),
    supabase.from("v_pending_transfers").select("*").order("requested_at", { ascending: false }),
    supabase.from("v_unresolved_exceptions").select("*").order("updated_at", { ascending: false }),
    supabase.from("v_recent_activity").select("*").limit(15),
  ]);

  const totalAvailable = (networkSummary.data ?? []).reduce((sum, r: any) => sum + (r.total_available ?? 0), 0);
  const totalInTransit = (networkSummary.data ?? []).reduce((sum, r: any) => sum + (r.total_in_transit ?? 0), 0);
  const totalDamaged = (networkSummary.data ?? []).reduce((sum, r: any) => sum + (r.total_damaged ?? 0), 0);
  const totalMissing = (networkSummary.data ?? []).reduce((sum, r: any) => sum + (r.total_missing ?? 0), 0);
  const overdueCount = (pendingTransfers.data ?? []).filter((t: any) => t.is_overdue).length;

  return (
    <div className="mx-auto max-w-6xl px-4 py-8">
      <div className="mb-6">
        <h1 className="text-xl font-semibold text-slate-900">Equipment Control Dashboard</h1>
        <p className="text-sm text-slate-500">What we have, where it is, and what needs attention.</p>
      </div>

      {/* What do we have? */}
      <section className="mb-8">
        <h2 className="mb-3 text-sm font-semibold text-slate-700">Network Position</h2>
        <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
          <SummaryCard label="Available" value={totalAvailable} />
          <SummaryCard label="In Transit" value={totalInTransit} tone={totalInTransit > 0 ? "warning" : "default"} />
          <SummaryCard label="Damaged" value={totalDamaged} tone={totalDamaged > 0 ? "warning" : "default"} />
          <SummaryCard label="Missing" value={totalMissing} tone={totalMissing > 0 ? "danger" : "default"} />
        </div>
      </section>

      {/* What needs attention? */}
      <section className="mb-8">
        <h2 className="mb-3 text-sm font-semibold text-slate-700">
          Needs Attention {overdueCount > 0 && <span className="text-red-600">({overdueCount} overdue)</span>}
        </h2>

        {shortages.data && shortages.data.length > 0 && (
          <div className="mb-3 overflow-hidden rounded-lg border border-amber-200 bg-amber-50">
            <div className="border-b border-amber-200 px-4 py-2 text-xs font-semibold uppercase tracking-wide text-amber-800">
              Shortages ({shortages.data.length})
            </div>
            <table className="w-full text-sm">
              <tbody className="divide-y divide-amber-100">
                {shortages.data.map((s: any) => (
                  <tr key={`${s.station_id}-${s.equipment_type_id}`}>
                    <td className="px-4 py-2 text-amber-900">{s.station_code}</td>
                    <td className="px-4 py-2 text-amber-900">{s.source_code} — {s.equipment_name}</td>
                    <td className="px-4 py-2 text-right text-amber-900">
                      {s.available_quantity ?? 0} / threshold {s.reorder_threshold}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {exceptions.data && exceptions.data.length > 0 && (
          <div className="mb-3 overflow-hidden rounded-lg border border-red-200 bg-red-50">
            <div className="border-b border-red-200 px-4 py-2 text-xs font-semibold uppercase tracking-wide text-red-800">
              Unresolved Exceptions ({exceptions.data.length})
            </div>
            <table className="w-full text-sm">
              <tbody className="divide-y divide-red-100">
                {exceptions.data.map((e: any) => (
                  <tr key={e.id}>
                    <td className="px-4 py-2 text-red-900">{e.exception_type.replace(/_/g, " ")}</td>
                    <td className="px-4 py-2 text-red-900">{e.reference}</td>
                    <td className="px-4 py-2 text-right text-red-700">
                      {new Date(e.updated_at).toLocaleDateString()}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {(!shortages.data || shortages.data.length === 0) && (!exceptions.data || exceptions.data.length === 0) && (
          <p className="text-sm text-slate-500">Nothing needs attention right now.</p>
        )}
      </section>

      {/* Pending transfers */}
      <section className="mb-8">
        <h2 className="mb-3 text-sm font-semibold text-slate-700">Open Transfers</h2>
        {pendingTransfers.data && pendingTransfers.data.length > 0 ? (
          <div className="overflow-hidden rounded-lg border border-slate-200">
            <table className="w-full text-sm">
              <thead className="bg-slate-50 text-left text-xs font-medium uppercase tracking-wide text-slate-500">
                <tr>
                  <th className="px-4 py-2">Transfer</th>
                  <th className="px-4 py-2">Route</th>
                  <th className="px-4 py-2">Status</th>
                  <th className="px-4 py-2">Age</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {pendingTransfers.data.map((t: any) => (
                  <tr key={t.id} className={t.is_overdue ? "bg-red-50" : ""}>
                    <td className="px-4 py-2">
                      <Link href={`/transfers/${t.id}`} className="font-medium text-slate-900 hover:underline">
                        {t.transfer_number}
                      </Link>
                    </td>
                    <td className="px-4 py-2 text-slate-600">{t.from_station_code} → {t.to_station_code}</td>
                    <td className="px-4 py-2 text-slate-600">{t.status}</td>
                    <td className="px-4 py-2 text-slate-500">
                      {Math.round(t.hours_since_requested)}h {t.is_overdue && <span className="text-red-600">(overdue)</span>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <p className="text-sm text-slate-500">No open transfers.</p>
        )}
      </section>

      {/* Recent activity */}
      <section>
        <h2 className="mb-3 text-sm font-semibold text-slate-700">Recent Activity</h2>
        {recentActivity.data && recentActivity.data.length > 0 ? (
          <div className="space-y-1 text-sm text-slate-600">
            {recentActivity.data.map((a: any, i: number) => (
              <div key={i} className="flex justify-between border-b border-slate-100 py-1.5">
                <span>
                  <span className="font-medium text-slate-800">{a.actor_label ?? "System"}</span>{" "}
                  {a.action.replace(/[._]/g, " ")}
                </span>
                <span className="text-slate-400">{new Date(a.created_at).toLocaleString()}</span>
              </div>
            ))}
          </div>
        ) : (
          <p className="text-sm text-slate-500">No recent activity.</p>
        )}
      </section>
    </div>
  );
}
