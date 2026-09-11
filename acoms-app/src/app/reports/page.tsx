import { createClient } from "@/lib/supabase/server";
import { ExportCsvButton } from "@/components/ui/ExportCsvButton";

export default async function ReportsPage() {
  const supabase = await createClient();

  const [inventory, transfers, damage, loss] = await Promise.all([
    supabase
      .from("v_station_inventory_status")
      .select("station_code, station_name, source_code, equipment_name, available_quantity, in_transit_quantity, damaged_quantity, missing_quantity, reorder_threshold, stock_status")
      .order("station_code"),
    supabase
      .from("equipment_transfers")
      .select("transfer_number, status, priority, requested_at, closed_at, from_station:from_station_id(code), to_station:to_station_id(code)")
      .order("requested_at", { ascending: false })
      .limit(200),
    supabase
      .from("damage_reports")
      .select("status, quantity, reason, reported_at, resolved_at, station:station_id(code), equipment_type:equipment_type_id(source_code, name)")
      .order("reported_at", { ascending: false })
      .limit(200),
    supabase
      .from("loss_reports")
      .select("status, quantity, circumstances, reported_at, resolved_at, station:station_id(code), equipment_type:equipment_type_id(source_code, name)")
      .order("reported_at", { ascending: false })
      .limit(200),
  ]);

  const transferRows = (transfers.data ?? []).map((t: any) => ({
    transfer_number: t.transfer_number,
    from_station: t.from_station?.code,
    to_station: t.to_station?.code,
    status: t.status,
    priority: t.priority,
    requested_at: t.requested_at,
    closed_at: t.closed_at ?? "",
  }));

  const damageRows = (damage.data ?? []).map((d: any) => ({
    equipment_code: d.equipment_type?.source_code,
    equipment_name: d.equipment_type?.name,
    station: d.station?.code,
    quantity: d.quantity,
    status: d.status,
    reason: d.reason,
    reported_at: d.reported_at,
    resolved_at: d.resolved_at ?? "",
  }));

  const lossRows = (loss.data ?? []).map((l: any) => ({
    equipment_code: l.equipment_type?.source_code,
    equipment_name: l.equipment_type?.name,
    station: l.station?.code,
    quantity: l.quantity,
    status: l.status,
    circumstances: l.circumstances,
    reported_at: l.reported_at,
    resolved_at: l.resolved_at ?? "",
  }));

  return (
    <div className="mx-auto max-w-6xl px-4 py-8">
      <h1 className="mb-1 text-xl font-semibold text-(--navy)">Reports</h1>
      <p className="mb-6 text-sm text-(--steel)">Exportable views of current position and history.</p>

      <section className="mb-10">
        <div className="mb-3 flex items-center justify-between">
          <h2 className="text-sm font-semibold text-(--navy)">Inventory by Station</h2>
          <ExportCsvButton rows={inventory.data ?? []} filename="inventory-by-station.csv" />
        </div>
        <div className="panel overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-(--steel-light) text-left text-xs font-medium uppercase tracking-wide text-(--steel)">
              <tr>
                <th className="px-3 py-2">Station</th>
                <th className="px-3 py-2">Equipment</th>
                <th className="px-3 py-2 text-right">Available</th>
                <th className="px-3 py-2 text-right">In Transit</th>
                <th className="px-3 py-2 text-right">Damaged</th>
                <th className="px-3 py-2 text-right">Missing</th>
                <th className="px-3 py-2">Status</th>
              </tr>
            </thead>
            <tbody className="divide-y" style={{ borderColor: "var(--border)" }}>
              {(inventory.data ?? []).map((r: any, i: number) => (
                <tr key={i}>
                  <td className="id-code px-3 py-1.5 text-(--navy)">{r.station_code}</td>
                  <td className="px-3 py-1.5"><span className="id-code">{r.source_code}</span> {r.equipment_name}</td>
                  <td className="id-code px-3 py-1.5 text-right">{r.available_quantity ?? "—"}</td>
                  <td className="id-code px-3 py-1.5 text-right">{r.in_transit_quantity ?? "—"}</td>
                  <td className="id-code px-3 py-1.5 text-right">{r.damaged_quantity ?? "—"}</td>
                  <td className="id-code px-3 py-1.5 text-right">{r.missing_quantity ?? "—"}</td>
                  <td className="px-3 py-1.5 text-xs">{r.stock_status.replace(/_/g, " ")}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section className="mb-10">
        <div className="mb-3 flex items-center justify-between">
          <h2 className="text-sm font-semibold text-(--navy)">Transfer History</h2>
          <ExportCsvButton rows={transferRows} filename="transfer-history.csv" />
        </div>
        <div className="panel overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-(--steel-light) text-left text-xs font-medium uppercase tracking-wide text-(--steel)">
              <tr>
                <th className="px-3 py-2">Transfer #</th>
                <th className="px-3 py-2">Route</th>
                <th className="px-3 py-2">Status</th>
                <th className="px-3 py-2">Requested</th>
                <th className="px-3 py-2">Closed</th>
              </tr>
            </thead>
            <tbody className="divide-y" style={{ borderColor: "var(--border)" }}>
              {transferRows.map((t, i) => (
                <tr key={i}>
                  <td className="id-code px-3 py-1.5 text-(--navy)">{t.transfer_number}</td>
                  <td className="id-code px-3 py-1.5 text-(--steel)">{t.from_station} → {t.to_station}</td>
                  <td className="px-3 py-1.5">{t.status}</td>
                  <td className="id-code px-3 py-1.5 text-(--steel)">{new Date(t.requested_at).toLocaleDateString()}</td>
                  <td className="id-code px-3 py-1.5 text-(--steel)">{t.closed_at ? new Date(t.closed_at).toLocaleDateString() : "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section className="mb-10">
        <div className="mb-3 flex items-center justify-between">
          <h2 className="text-sm font-semibold text-(--navy)">Damage Reports</h2>
          <ExportCsvButton rows={damageRows} filename="damage-reports.csv" />
        </div>
        <div className="panel overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-(--steel-light) text-left text-xs font-medium uppercase tracking-wide text-(--steel)">
              <tr>
                <th className="px-3 py-2">Equipment</th>
                <th className="px-3 py-2">Station</th>
                <th className="px-3 py-2 text-right">Qty</th>
                <th className="px-3 py-2">Status</th>
                <th className="px-3 py-2">Reported</th>
              </tr>
            </thead>
            <tbody className="divide-y" style={{ borderColor: "var(--border)" }}>
              {damageRows.map((d, i) => (
                <tr key={i}>
                  <td className="px-3 py-1.5"><span className="id-code">{d.equipment_code}</span> {d.equipment_name}</td>
                  <td className="id-code px-3 py-1.5">{d.station}</td>
                  <td className="id-code px-3 py-1.5 text-right">{d.quantity}</td>
                  <td className="px-3 py-1.5">{d.status.replace(/_/g, " ")}</td>
                  <td className="id-code px-3 py-1.5 text-(--steel)">{new Date(d.reported_at).toLocaleDateString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section>
        <div className="mb-3 flex items-center justify-between">
          <h2 className="text-sm font-semibold text-(--navy)">Loss Reports</h2>
          <ExportCsvButton rows={lossRows} filename="loss-reports.csv" />
        </div>
        <div className="panel overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-(--steel-light) text-left text-xs font-medium uppercase tracking-wide text-(--steel)">
              <tr>
                <th className="px-3 py-2">Equipment</th>
                <th className="px-3 py-2">Station</th>
                <th className="px-3 py-2 text-right">Qty</th>
                <th className="px-3 py-2">Status</th>
                <th className="px-3 py-2">Reported</th>
              </tr>
            </thead>
            <tbody className="divide-y" style={{ borderColor: "var(--border)" }}>
              {lossRows.map((l, i) => (
                <tr key={i}>
                  <td className="px-3 py-1.5"><span className="id-code">{l.equipment_code}</span> {l.equipment_name}</td>
                  <td className="id-code px-3 py-1.5">{l.station}</td>
                  <td className="id-code px-3 py-1.5 text-right">{l.quantity}</td>
                  <td className="px-3 py-1.5">{l.status.replace(/_/g, " ")}</td>
                  <td className="id-code px-3 py-1.5 text-(--steel)">{new Date(l.reported_at).toLocaleDateString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}
