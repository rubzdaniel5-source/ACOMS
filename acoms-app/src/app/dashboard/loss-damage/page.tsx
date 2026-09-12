import Link from "next/link";
import { createClient } from "@/lib/supabase/server";

export default async function LossDamagePage() {
  const supabase = await createClient();
  const [damage, loss] = await Promise.all([
    supabase
      .from("damage_reports")
      .select("id, status, quantity, reason, reported_at, station:station_id(code), equipment_type:equipment_type_id(source_code, name)")
      .not("status", "in", "(RETURNED_TO_SERVICE,DISPOSED)")
      .order("reported_at", { ascending: false }),
    supabase
      .from("loss_reports")
      .select("id, status, quantity, circumstances, reported_at, station:station_id(code), equipment_type:equipment_type_id(source_code, name)")
      .in("status", ["REPORTED", "INVESTIGATION"])
      .order("reported_at", { ascending: false }),
  ]);

  return (
    <div className="mx-auto max-w-6xl px-4 py-8">
      <Link href="/dashboard" className="mb-4 inline-block text-sm text-(--steel) hover:text-(--navy)">← Back to Dashboard</Link>
      <h1 className="mb-1 text-xl font-semibold text-(--navy)">Loss &amp; Damage Control</h1>
      <p className="mb-6 text-sm text-(--steel)">Open exceptions requiring investigation or resolution.</p>

      <section className="mb-8">
        <h2 className="mb-3 text-sm font-semibold text-(--brick)">Missing Equipment ({loss.data?.length ?? 0})</h2>
        <div className="panel overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-(--steel-light) text-left text-xs font-medium uppercase tracking-wide text-(--steel)">
              <tr><th className="px-3 py-2">Equipment</th><th className="px-3 py-2">Station</th><th className="px-3 py-2 text-right">Qty</th><th className="px-3 py-2">Status</th><th className="px-3 py-2">Action</th></tr>
            </thead>
            <tbody className="divide-y" style={{ borderColor: "var(--border)" }}>
              {(loss.data ?? []).map((l: any) => (
                <tr key={l.id}>
                  <td className="px-3 py-2"><span className="id-code">{l.equipment_type?.source_code}</span> {l.equipment_type?.name}</td>
                  <td className="id-code px-3 py-2">{l.station?.code}</td>
                  <td className="id-code px-3 py-2 text-right">{l.quantity}</td>
                  <td className="px-3 py-2">{l.status.replace(/_/g, " ")}</td>
                  <td className="px-3 py-2"><Link href={`/damage-loss/${l.id}?type=loss`} className="text-xs font-semibold text-(--navy) hover:underline">Open Investigation</Link></td>
                </tr>
              ))}
              {(!loss.data || loss.data.length === 0) && (<tr><td colSpan={5} className="px-3 py-6 text-center text-(--steel)">None open.</td></tr>)}
            </tbody>
          </table>
        </div>
      </section>

      <section>
        <h2 className="mb-3 text-sm font-semibold text-(--amber)">Damaged Equipment ({damage.data?.length ?? 0})</h2>
        <div className="panel overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-(--steel-light) text-left text-xs font-medium uppercase tracking-wide text-(--steel)">
              <tr><th className="px-3 py-2">Equipment</th><th className="px-3 py-2">Station</th><th className="px-3 py-2 text-right">Qty</th><th className="px-3 py-2">Status</th><th className="px-3 py-2">Action</th></tr>
            </thead>
            <tbody className="divide-y" style={{ borderColor: "var(--border)" }}>
              {(damage.data ?? []).map((d: any) => (
                <tr key={d.id}>
                  <td className="px-3 py-2"><span className="id-code">{d.equipment_type?.source_code}</span> {d.equipment_type?.name}</td>
                  <td className="id-code px-3 py-2">{d.station?.code}</td>
                  <td className="id-code px-3 py-2 text-right">{d.quantity}</td>
                  <td className="px-3 py-2">{d.status.replace(/_/g, " ")}</td>
                  <td className="px-3 py-2"><Link href={`/damage-loss/${d.id}?type=damage`} className="text-xs font-semibold text-(--navy) hover:underline">Review</Link></td>
                </tr>
              ))}
              {(!damage.data || damage.data.length === 0) && (<tr><td colSpan={5} className="px-3 py-6 text-center text-(--steel)">None open.</td></tr>)}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}
