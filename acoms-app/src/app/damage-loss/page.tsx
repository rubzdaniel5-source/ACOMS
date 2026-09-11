import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { ReportForm } from "./ReportForm";

export default async function DamageLossPage() {
  const supabase = await createClient();

  const [damageReports, lossReports] = await Promise.all([
    supabase
      .from("damage_reports")
      .select("id, status, quantity, reason, reported_at, station:station_id(code), equipment_type:equipment_type_id(source_code, name)")
      .order("reported_at", { ascending: false })
      .limit(50),
    supabase
      .from("loss_reports")
      .select("id, status, quantity, circumstances, reported_at, station:station_id(code), equipment_type:equipment_type_id(source_code, name)")
      .order("reported_at", { ascending: false })
      .limit(50),
  ]);

  return (
    <div className="mx-auto max-w-4xl px-4 py-8">
      <h1 className="mb-1 text-xl font-semibold text-slate-900">Damage &amp; Loss</h1>
      <p className="mb-6 text-sm text-slate-500">
        Standalone reports — equipment damaged or lost outside a transfer.
      </p>

      <ReportForm />

      <section className="mt-10">
        <h2 className="mb-3 text-sm font-semibold text-slate-700">Damage Reports</h2>
        {damageReports.data && damageReports.data.length > 0 ? (
          <div className="overflow-hidden rounded-lg border border-slate-200">
            <table className="w-full text-sm">
              <thead className="bg-slate-50 text-left text-xs font-medium uppercase tracking-wide text-slate-500">
                <tr>
                  <th className="px-4 py-2">Equipment</th>
                  <th className="px-4 py-2">Station</th>
                  <th className="px-4 py-2">Qty</th>
                  <th className="px-4 py-2">Status</th>
                  <th className="px-4 py-2">Reported</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {(damageReports.data as any[]).map((d) => (
                  <tr key={d.id} className="hover:bg-slate-50">
                    <td className="px-4 py-2">
                      <Link href={`/damage-loss/${d.id}?type=damage`} className="font-medium text-slate-900 hover:underline">
                        {d.equipment_type?.source_code}
                      </Link>
                      <div className="text-xs text-slate-500">{d.equipment_type?.name}</div>
                    </td>
                    <td className="px-4 py-2 text-slate-600">{d.station?.code}</td>
                    <td className="px-4 py-2 text-slate-600">{d.quantity}</td>
                    <td className="px-4 py-2 text-slate-600">{d.status.replace(/_/g, " ")}</td>
                    <td className="px-4 py-2 text-slate-500">{new Date(d.reported_at).toLocaleDateString()}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <p className="text-sm text-slate-500">No damage reports yet.</p>
        )}
      </section>

      <section className="mt-8">
        <h2 className="mb-3 text-sm font-semibold text-slate-700">Loss Reports</h2>
        {lossReports.data && lossReports.data.length > 0 ? (
          <div className="overflow-hidden rounded-lg border border-slate-200">
            <table className="w-full text-sm">
              <thead className="bg-slate-50 text-left text-xs font-medium uppercase tracking-wide text-slate-500">
                <tr>
                  <th className="px-4 py-2">Equipment</th>
                  <th className="px-4 py-2">Station</th>
                  <th className="px-4 py-2">Qty</th>
                  <th className="px-4 py-2">Status</th>
                  <th className="px-4 py-2">Reported</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {(lossReports.data as any[]).map((l) => (
                  <tr key={l.id} className="hover:bg-slate-50">
                    <td className="px-4 py-2">
                      <Link href={`/damage-loss/${l.id}?type=loss`} className="font-medium text-slate-900 hover:underline">
                        {l.equipment_type?.source_code}
                      </Link>
                      <div className="text-xs text-slate-500">{l.equipment_type?.name}</div>
                    </td>
                    <td className="px-4 py-2 text-slate-600">{l.station?.code}</td>
                    <td className="px-4 py-2 text-slate-600">{l.quantity}</td>
                    <td className="px-4 py-2 text-slate-600">{l.status.replace(/_/g, " ")}</td>
                    <td className="px-4 py-2 text-slate-500">{new Date(l.reported_at).toLocaleDateString()}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <p className="text-sm text-slate-500">No loss reports yet.</p>
        )}
      </section>
    </div>
  );
}
