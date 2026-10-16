import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { getCurrentUserPermissions } from "@/features/auth/permissions";
import { EXCHANGE_STATUS_LABEL, EXCHANGE_STATUS_TAG, type ExchangeRow } from "@/features/exchanges/status";

export default async function ExchangesPage({ searchParams }: { searchParams: Promise<{ view?: string }> }) {
  const { view } = await searchParams;
  const supabase = await createClient();
  const perms = await getCurrentUserPermissions();
  let q = supabase.from("v_equipment_exchanges").select("*").order("created_at", { ascending: false }).limit(100);
  if (view !== "all") q = q.not("status", "in", "(CLOSED,CLOSED_NO_RETURN,CANCELLED)");
  const { data, error } = await q;
  const rows = (data ?? []) as ExchangeRow[];

  return (
    <div className="mx-auto w-full max-w-7xl px-3 py-6 sm:px-6">
      <div className="mb-6 flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold text-(--navy)">Equipment Exchanges</h1>
          <p className="text-sm text-(--steel)">Each exchange follows the equipment out to an outstation and back to the hub.</p>
        </div>
        <div className="flex gap-3">
          <Link href="/transfers" className="btn-secondary px-4 py-2 text-sm">All transfers</Link>
          {perms.has("create_transfer") && <Link href="/exchanges/new" className="btn-primary px-4 py-2 text-sm">New exchange</Link>}
        </div>
      </div>

      <p className="mb-4 flex flex-wrap items-center gap-3 text-sm text-(--color-text-muted)">
        {view === "all" ? "Showing all exchanges." : "Showing open exchanges."}
        <Link href={view === "all" ? "/exchanges" : "/exchanges?view=all"} className="font-semibold text-(--color-primary) hover:underline">
          {view === "all" ? "Show open only" : "Show all"}
        </Link>
      </p>

      {error && <div className="panel px-4 py-3 text-sm text-(--brick)">{error.message}</div>}
      {!error && rows.length === 0 && (
        <div className="panel border-dashed px-6 py-12 text-center text-sm text-(--steel)">No exchanges to show.</div>
      )}
      {rows.length > 0 && (
        <div className="panel overflow-x-auto">
          <table className="w-full min-w-[720px] text-sm">
            <thead className="bg-(--steel-light) text-left text-sm font-medium text-(--steel)">
              <tr><th className="px-4 py-3">Exchange</th><th className="px-4 py-3">Route</th><th className="px-4 py-3">Status</th><th className="px-4 py-3">Next action</th><th className="px-4 py-3">Started</th></tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id} className="border-t border-(--border)">
                  <td className="px-4 py-3"><Link href={`/exchanges/${r.id}`} className="id-code font-medium text-(--color-primary) hover:underline">{r.exchange_number}</Link></td>
                  <td className="px-4 py-3">{r.hub_code} and {r.outstation_code}</td>
                  <td className="px-4 py-3">
                    <span className={`tag ${EXCHANGE_STATUS_TAG[r.status] ?? "tag-neutral"}`}>{EXCHANGE_STATUS_LABEL[r.status] ?? r.status}</span>
                    {r.has_open_discrepancy && <span className="tag tag-brick ml-2">Discrepancy</span>}
                  </td>
                  <td className="px-4 py-3 text-(--steel)">{r.next_action ? `${r.next_action}${r.next_station_code ? ` (${r.next_station_code})` : ""}` : "None"}</td>
                  <td className="px-4 py-3 text-(--steel)">{new Date(r.created_at).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" })}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
