import Link from "next/link";
import { createClient } from "@/lib/supabase/server";

function SummaryCard({ label, value, tone = "default" }: { label: string; value: number | string; tone?: "default" | "warning" | "danger" }) {
  const toneClass =
    tone === "danger" ? "text-(--brick)" : tone === "warning" ? "text-(--amber)" : "text-(--navy)";
  return (
    <div className="panel p-4">
      <div className="text-xs font-medium uppercase tracking-wide text-(--steel)">{label}</div>
      <div className={`id-code mt-1 text-2xl font-semibold ${toneClass}`}>{value}</div>
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
        <h1 className="text-xl font-semibold text-(--navy)">Equipment Control Dashboard</h1>
        <p className="text-sm text-(--steel)">What we have, where it is, and what needs attention.</p>
      </div>

      {/* What do we have? */}
      <section className="mb-8">
        <h2 className="mb-3 text-sm font-semibold text-(--navy)">Network Position</h2>
        <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
          <SummaryCard label="Available" value={totalAvailable} />
          <SummaryCard label="In Transit" value={totalInTransit} tone={totalInTransit > 0 ? "warning" : "default"} />
          <SummaryCard label="Damaged" value={totalDamaged} tone={totalDamaged > 0 ? "warning" : "default"} />
          <SummaryCard label="Missing" value={totalMissing} tone={totalMissing > 0 ? "danger" : "default"} />
        </div>
      </section>

      {/* What needs attention? */}
      <section className="mb-8">
        <h2 className="mb-3 text-sm font-semibold text-(--navy)">
          Needs Attention {overdueCount > 0 && <span className="id-code text-(--brick)">({overdueCount} overdue)</span>}
        </h2>

        {shortages.data && shortages.data.length > 0 && (
          <div className="panel mb-3 overflow-hidden" style={{ borderColor: "#EAD3AC" }}>
            <div className="border-b px-4 py-2 text-xs font-semibold uppercase tracking-wide text-(--amber)" style={{ borderColor: "#EAD3AC", background: "var(--amber-surface)" }}>
              Shortages ({shortages.data.length})
            </div>
            <table className="w-full text-sm">
              <tbody className="divide-y" style={{ borderColor: "#EAD3AC" }}>
                {shortages.data.map((s: any) => (
                  <tr key={`${s.station_id}-${s.equipment_type_id}`}>
                    <td className="id-code px-4 py-2 text-(--navy)">{s.station_code}</td>
                    <td className="px-4 py-2 text-(--foreground)"><span className="id-code">{s.source_code}</span> — {s.equipment_name}</td>
                    <td className="id-code px-4 py-2 text-right text-(--steel)">
                      {s.available_quantity ?? 0} / threshold {s.reorder_threshold}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {exceptions.data && exceptions.data.length > 0 && (
          <div className="panel mb-3 overflow-hidden" style={{ borderColor: "#E2BEBE" }}>
            <div className="border-b px-4 py-2 text-xs font-semibold uppercase tracking-wide text-(--brick)" style={{ borderColor: "#E2BEBE", background: "var(--brick-surface)" }}>
              Unresolved Exceptions ({exceptions.data.length})
            </div>
            <table className="w-full text-sm">
              <tbody className="divide-y" style={{ borderColor: "#E2BEBE" }}>
                {exceptions.data.map((e: any) => (
                  <tr key={e.id}>
                    <td className="px-4 py-2 text-(--foreground)">{e.exception_type.replace(/_/g, " ")}</td>
                    <td className="id-code px-4 py-2 text-(--foreground)">{e.reference}</td>
                    <td className="id-code px-4 py-2 text-right text-(--brick)">
                      {new Date(e.updated_at).toLocaleDateString()}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {(!shortages.data || shortages.data.length === 0) && (!exceptions.data || exceptions.data.length === 0) && (
          <p className="text-sm text-(--steel)">Nothing needs attention right now.</p>
        )}
      </section>

      {/* Pending transfers */}
      <section className="mb-8">
        <h2 className="mb-3 text-sm font-semibold text-(--navy)">Open Transfers</h2>
        {pendingTransfers.data && pendingTransfers.data.length > 0 ? (
          <div className="panel overflow-hidden">
            <table className="w-full text-sm">
              <thead className="bg-(--steel-light) text-left text-xs font-medium uppercase tracking-wide text-(--steel)">
                <tr>
                  <th className="px-4 py-2">Transfer</th>
                  <th className="px-4 py-2">Route</th>
                  <th className="px-4 py-2">Status</th>
                  <th className="px-4 py-2">Age</th>
                </tr>
              </thead>
              <tbody className="divide-y" style={{ borderColor: "var(--border)" }}>
                {pendingTransfers.data.map((t: any) => (
                  <tr key={t.id} className={t.is_overdue ? "bg-(--brick-surface)" : ""}>
                    <td className="px-4 py-2">
                      <Link href={`/transfers/${t.id}`} className="id-code font-medium text-(--navy) hover:underline">
                        {t.transfer_number}
                      </Link>
                    </td>
                    <td className="id-code px-4 py-2 text-(--steel)">{t.from_station_code} → {t.to_station_code}</td>
                    <td className="px-4 py-2 text-(--foreground)">{t.status}</td>
                    <td className="id-code px-4 py-2 text-(--steel)">
                      {Math.round(t.hours_since_requested)}h {t.is_overdue && <span className="text-(--brick)">(overdue)</span>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <p className="text-sm text-(--steel)">No open transfers.</p>
        )}
      </section>

      {/* Recent activity */}
      <section>
        <h2 className="mb-3 text-sm font-semibold text-(--navy)">Recent Activity</h2>
        {recentActivity.data && recentActivity.data.length > 0 ? (
          <div className="panel divide-y text-sm" style={{ borderColor: "var(--border)" }}>
            {recentActivity.data.map((a: any, i: number) => (
              <div key={i} className="flex justify-between px-4 py-2 text-(--foreground)">
                <span>
                  <span className="font-medium text-(--navy)">{a.actor_label ?? "System"}</span>{" "}
                  {a.action.replace(/[._]/g, " ")}
                </span>
                <span className="id-code text-(--steel)">{new Date(a.created_at).toLocaleString()}</span>
              </div>
            ))}
          </div>
        ) : (
          <p className="text-sm text-(--steel)">No recent activity.</p>
        )}
      </section>
    </div>
  );
}
