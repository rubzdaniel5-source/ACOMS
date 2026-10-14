import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { ReportForm } from "./ReportForm";

const VIEWS: Record<string, string> = {
  missing: "Missing equipment (open loss reports)",
  damaged: "Damaged equipment (open damage reports)",
  investigation: "Under investigation",
  confirmed: "Confirmed losses",
};

export default async function DamageLossPage({ searchParams }: { searchParams: Promise<{ view?: string }> }) {
  const { view: rawView } = await searchParams;
  const view = rawView && VIEWS[rawView] ? rawView : undefined;
  const showDamage = !view || view === "damaged";
  const showLoss = !view || view !== "damaged";
  const supabase = await createClient();

  let damageQ = supabase
      .from("damage_reports")
      .select("id, status, quantity, reason, reported_at, station:station_id(code), equipment_type:equipment_type_id(source_code, name)")
      .order("reported_at", { ascending: false })
      .limit(50);
  if (view === "damaged") damageQ = damageQ.not("status", "in", "(RETURNED_TO_SERVICE,DISPOSED)");
  let lossQ = supabase
      .from("loss_reports")
      .select("id, status, quantity, circumstances, reported_at, station:station_id(code), equipment_type:equipment_type_id(source_code, name)")
      .order("reported_at", { ascending: false })
      .limit(50);
  if (view === "missing") lossQ = lossQ.in("status", ["REPORTED", "INVESTIGATION"]);
  if (view === "investigation") lossQ = lossQ.eq("status", "INVESTIGATION");
  if (view === "confirmed") lossQ = lossQ.in("status", ["CONFIRMED_LOSS", "CLOSED"]);
  const [damageReports, lossReports] = await Promise.all([damageQ, lossQ]);

  return (
    <div className="mx-auto w-full max-w-5xl px-3 py-6 sm:px-6">
      <h1 className="mb-1 text-2xl font-semibold text-(--color-text)">Damage &amp; Loss</h1>
      <p className="mb-6 text-sm text-(--color-text-subtle)">
        Standalone reports — equipment damaged or lost outside a transfer.
      </p>

      {view && (
        <p className="mb-4 flex flex-wrap items-center gap-3 text-sm text-(--color-text-muted)">
          Showing: <span className="tag tag-info">{VIEWS[view]}</span>
          <Link href="/damage-loss" className="font-semibold text-(--color-primary) hover:underline">Show all reports</Link>
        </p>
      )}

      <ReportForm />

      {showDamage && (<section className="mt-10">
        <h2 className="mb-3 text-sm font-semibold text-(--color-text-muted)">Damage Reports</h2>
        {damageReports.data && damageReports.data.length > 0 ? (
          <div className="panel overflow-x-auto">
            <table className="w-full min-w-[640px] text-sm">
              <thead className="bg-(--color-surface-subtle) text-left text-xs font-medium text-(--color-text-subtle)">
                <tr>
                  <th className="px-4 py-2">Equipment</th>
                  <th className="px-4 py-2">Station</th>
                  <th className="px-4 py-2">Qty</th>
                  <th className="px-4 py-2">Status</th>
                  <th className="px-4 py-2">Reported</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-(--color-border)">
                {(damageReports.data as any[]).map((d) => (
                  <tr key={d.id} className="hover:bg-(--color-surface-hover)">
                    <td className="px-4 py-2">
                      <Link href={`/damage-loss/${d.id}?type=damage`} className="font-medium text-(--color-text) hover:underline">
                        {d.equipment_type?.source_code}
                      </Link>
                      <div className="text-xs text-(--color-text-subtle)">{d.equipment_type?.name}</div>
                    </td>
                    <td className="px-4 py-2 text-(--color-text-muted)">{d.station?.code}</td>
                    <td className="px-4 py-2 text-(--color-text-muted)">{d.quantity}</td>
                    <td className="px-4 py-2 text-(--color-text-muted)">{d.status.replace(/_/g, " ")}</td>
                    <td className="px-4 py-2 text-(--color-text-subtle)">{new Date(d.reported_at).toLocaleDateString()}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <p className="text-sm text-(--color-text-subtle)">No damage reports yet.</p>
        )}
      </section>)}

      {showLoss && (<section className="mt-8">
        <h2 className="mb-3 text-sm font-semibold text-(--color-text-muted)">Loss Reports</h2>
        {lossReports.data && lossReports.data.length > 0 ? (
          <div className="panel overflow-x-auto">
            <table className="w-full min-w-[640px] text-sm">
              <thead className="bg-(--color-surface-subtle) text-left text-xs font-medium text-(--color-text-subtle)">
                <tr>
                  <th className="px-4 py-2">Equipment</th>
                  <th className="px-4 py-2">Station</th>
                  <th className="px-4 py-2">Qty</th>
                  <th className="px-4 py-2">Status</th>
                  <th className="px-4 py-2">Reported</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-(--color-border)">
                {(lossReports.data as any[]).map((l) => (
                  <tr key={l.id} className="hover:bg-(--color-surface-hover)">
                    <td className="px-4 py-2">
                      <Link href={`/damage-loss/${l.id}?type=loss`} className="font-medium text-(--color-text) hover:underline">
                        {l.equipment_type?.source_code}
                      </Link>
                      <div className="text-xs text-(--color-text-subtle)">{l.equipment_type?.name}</div>
                    </td>
                    <td className="px-4 py-2 text-(--color-text-muted)">{l.station?.code}</td>
                    <td className="px-4 py-2 text-(--color-text-muted)">{l.quantity}</td>
                    <td className="px-4 py-2 text-(--color-text-muted)">{l.status.replace(/_/g, " ")}</td>
                    <td className="px-4 py-2 text-(--color-text-subtle)">{new Date(l.reported_at).toLocaleDateString()}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <p className="text-sm text-(--color-text-subtle)">No loss reports yet.</p>
        )}
      </section>)}
    </div>
  );
}
