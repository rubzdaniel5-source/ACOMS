import { createClient } from "@/lib/supabase/server";
import { fetchAll } from "@/lib/supabase/fetchAll";
import { ExportCsvButton } from "@/components/ui/ExportCsvButton";
import { TransferStatusBadge } from "@/components/ui/TransferStatusBadge";
import type { TransferStatus } from "@/types/transfers";

const STOCK_TAG: Record<string, string> = {
  CRITICAL_SHORTAGE: "tag-brick",
  SHORTAGE: "tag-amber",
  NORMAL: "tag-teal",
  SURPLUS: "tag-surplus",
  CRITICAL_SURPLUS: "tag-surplus",
};
const words = (v: string | null | undefined) => {
  const t = (v ?? "").replace(/_/g, " ").toLowerCase();
  return t.charAt(0).toUpperCase() + t.slice(1);
};
const day = (v: string) => new Date(v).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });

function Section({
  id, title, note, count, failed, children, exportRows, filename,
}: {
  id: string; title: string; note?: string; count: number; failed: boolean;
  children: React.ReactNode; exportRows: Record<string, unknown>[]; filename: string;
}) {
  return (
    <section id={id} aria-labelledby={`${id}-h`} className="mb-10 scroll-mt-4">
      <div className="mb-3 flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 id={`${id}-h`} className="text-lg font-semibold text-(--color-text)">{title}</h2>
          <p className="text-sm text-(--color-text-subtle)">{failed ? "Could not be loaded." : `${count} ${count === 1 ? "row" : "rows"}${note ? `. ${note}` : ""}`}</p>
        </div>
        <ExportCsvButton rows={exportRows} filename={filename} />
      </div>
      {failed ? (
        <div className="alert alert-danger" role="alert">This report could not be loaded. Refresh the page to try again.</div>
      ) : count === 0 ? (
        <div className="panel px-6 py-10 text-center text-sm text-(--color-text-muted)">Nothing to report yet.</div>
      ) : (
        <div className="panel max-h-[70vh] overflow-auto">{children}</div>
      )}
    </section>
  );
}

const TH = "sticky top-0 bg-(--color-surface-subtle) px-4 py-2.5 text-left text-sm font-semibold text-(--color-text-muted)";
const TD = "px-4 py-2.5";

export default async function ReportsPage() {
  const supabase = await createClient();

  const [inventory, transfers, damage, loss] = await Promise.all([
    fetchAll<any>((from, to) =>
      supabase
        .from("v_station_inventory_status")
        .select("station_code, station_name, source_code, equipment_name, available_quantity, in_transit_quantity, damaged_quantity, missing_quantity, reorder_threshold, stock_status")
        .order("station_code").order("source_code")
        .range(from, to)
    ),
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

  const inv = (inventory.data ?? []) as any[];

  return (
    <div className="mx-auto w-full max-w-7xl px-3 py-6 sm:px-6">
      <h1 className="mb-1 text-2xl font-semibold text-(--color-text)">Reports</h1>
      <p className="mb-4 text-sm text-(--color-text-muted)">
        Exportable views of current position and history. Exports contain exactly the rows you can see.
      </p>
      <nav aria-label="Reports" className="mb-8 flex flex-wrap gap-2">
        {[["inventory", "Inventory by station"], ["transfers", "Transfer history"], ["damage", "Damage reports"], ["loss", "Loss reports"]].map(([id, label]) => (
          <a key={id} href={`#${id}`} className="btn-secondary inline-flex min-h-11 items-center px-4 text-sm">{label}</a>
        ))}
      </nav>

      <Section id="inventory" title="Inventory by station" count={inv.length} failed={!!inventory.error} exportRows={inventory.data ?? []} filename="inventory-by-station.csv">
        <table className="w-full min-w-[760px] text-sm">
          <caption className="sr-only">Inventory by station</caption>
          <thead>
            <tr>
              <th scope="col" className={TH}>Station</th>
              <th scope="col" className={TH}>Equipment</th>
              <th scope="col" className={`${TH} text-right`}>Available</th>
              <th scope="col" className={`${TH} text-right`}>In transit</th>
              <th scope="col" className={`${TH} text-right`}>Damaged</th>
              <th scope="col" className={`${TH} text-right`}>Missing</th>
              <th scope="col" className={TH}>Status</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-(--color-border)">
            {inv.map((r, i) => (
              <tr key={i} className="hover:bg-(--color-surface-hover)">
                <td className={`${TD} id-code`}>{r.station_code}</td>
                <td className={TD}><span className="id-code">{r.source_code}</span> {r.equipment_name}</td>
                <td className={`${TD} id-code text-right`}>{r.available_quantity ?? "—"}</td>
                <td className={`${TD} id-code text-right`}>{r.in_transit_quantity ?? "—"}</td>
                <td className={`${TD} id-code text-right`}>{r.damaged_quantity ?? "—"}</td>
                <td className={`${TD} id-code text-right`}>{r.missing_quantity ?? "—"}</td>
                <td className={TD}><span className={`tag ${STOCK_TAG[r.stock_status] ?? "tag-neutral"}`}>{words(r.stock_status)}</span></td>
              </tr>
            ))}
          </tbody>
        </table>
      </Section>

      <Section id="transfers" title="Transfer history" note="Latest 200" count={transferRows.length} failed={!!transfers.error} exportRows={transferRows} filename="transfer-history.csv">
        <table className="w-full min-w-[640px] text-sm">
          <caption className="sr-only">Transfer history</caption>
          <thead>
            <tr>
              <th scope="col" className={TH}>Transfer</th>
              <th scope="col" className={TH}>Route</th>
              <th scope="col" className={TH}>Status</th>
              <th scope="col" className={TH}>Requested</th>
              <th scope="col" className={TH}>Closed</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-(--color-border)">
            {transferRows.map((t, i) => (
              <tr key={i} className="hover:bg-(--color-surface-hover)">
                <td className={`${TD} id-code`}>{t.transfer_number}</td>
                <td className={`${TD} id-code text-(--color-text-muted)`}>{t.from_station} → {t.to_station}</td>
                <td className={TD}><TransferStatusBadge status={t.status as TransferStatus} /></td>
                <td className={`${TD} text-(--color-text-muted)`}>{day(t.requested_at)}</td>
                <td className={`${TD} text-(--color-text-muted)`}>{t.closed_at ? day(t.closed_at) : "—"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </Section>

      <Section id="damage" title="Damage reports" note="Latest 200" count={damageRows.length} failed={!!damage.error} exportRows={damageRows} filename="damage-reports.csv">
        <table className="w-full min-w-[640px] text-sm">
          <caption className="sr-only">Damage reports</caption>
          <thead>
            <tr>
              <th scope="col" className={TH}>Equipment</th>
              <th scope="col" className={TH}>Station</th>
              <th scope="col" className={`${TH} text-right`}>Quantity</th>
              <th scope="col" className={TH}>Status</th>
              <th scope="col" className={TH}>Reported</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-(--color-border)">
            {damageRows.map((d, i) => (
              <tr key={i} className="hover:bg-(--color-surface-hover)">
                <td className={TD}><span className="id-code">{d.equipment_code}</span> {d.equipment_name}</td>
                <td className={`${TD} id-code`}>{d.station}</td>
                <td className={`${TD} id-code text-right`}>{d.quantity}</td>
                <td className={TD}>{words(d.status)}</td>
                <td className={`${TD} text-(--color-text-muted)`}>{day(d.reported_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </Section>

      <Section id="loss" title="Loss reports" note="Latest 200" count={lossRows.length} failed={!!loss.error} exportRows={lossRows} filename="loss-reports.csv">
        <table className="w-full min-w-[640px] text-sm">
          <caption className="sr-only">Loss reports</caption>
          <thead>
            <tr>
              <th scope="col" className={TH}>Equipment</th>
              <th scope="col" className={TH}>Station</th>
              <th scope="col" className={`${TH} text-right`}>Quantity</th>
              <th scope="col" className={TH}>Status</th>
              <th scope="col" className={TH}>Reported</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-(--color-border)">
            {lossRows.map((l, i) => (
              <tr key={i} className="hover:bg-(--color-surface-hover)">
                <td className={TD}><span className="id-code">{l.equipment_code}</span> {l.equipment_name}</td>
                <td className={`${TD} id-code`}>{l.station}</td>
                <td className={`${TD} id-code text-right`}>{l.quantity}</td>
                <td className={TD}>{words(l.status)}</td>
                <td className={`${TD} text-(--color-text-muted)`}>{day(l.reported_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </Section>
    </div>
  );
}
