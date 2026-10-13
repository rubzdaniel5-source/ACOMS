import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { requireAnyPermission } from "@/features/admin/access";

const PAGE_SIZE = 50;
const TYPES = ["OPENING_BALANCE", "RECEIPT", "TRANSFER_OUT", "TRANSFER_IN", "RETURN", "DAMAGE", "LOSS", "ADJUSTMENT", "DISPOSAL", "RECOVERY"];

export default async function LedgerPage({
  searchParams,
}: {
  searchParams: Promise<{ station?: string; type?: string; q?: string; page?: string }>;
}) {
  await requireAnyPermission(["view_inventory"]);
  const sp = await searchParams;
  const page = Math.max(1, Number(sp.page) || 1);
  const supabase = await createClient();

  let query = supabase
    .from("v_inventory_ledger")
    .select("*", { count: "exact" })
    .order("created_at", { ascending: false })
    .range((page - 1) * PAGE_SIZE, page * PAGE_SIZE - 1);
  if (sp.station) query = query.eq("station_code", sp.station);
  if (sp.type) query = query.eq("transaction_type", sp.type);
  if (sp.q) {
    const term = sp.q.replace(/[%,()]/g, " ").trim();
    if (term) query = query.or(`equipment_name.ilike.%${term}%,source_code.ilike.%${term}%`);
  }

  const [{ data, count }, stations] = await Promise.all([
    query,
    supabase.from("stations").select("code").order("code"),
  ]);
  const rows = (data ?? []) as any[];
  const total = count ?? 0;
  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE));

  const qs = (p: number) => {
    const u = new URLSearchParams();
    if (sp.station) u.set("station", sp.station);
    if (sp.type) u.set("type", sp.type);
    if (sp.q) u.set("q", sp.q);
    u.set("page", String(p));
    return `/admin/ledger?${u.toString()}`;
  };

  return (
    <div>
      <h1 className="mb-1 text-xl font-semibold text-(--navy)">Inventory Ledger</h1>
      <p className="mb-4 text-sm text-(--steel)">Append-only record of every stock movement. Mistakes are corrected by adjustments, never edits.</p>

      <form className="panel mb-4 flex flex-wrap items-end gap-3 p-4" method="get">
        <div>
          <label className="mb-1 block text-xs text-(--steel)">Station</label>
          <select name="station" defaultValue={sp.station ?? ""} className="rounded-sm border border-(--border) px-2 py-1.5 text-sm">
            <option value="">All</option>
            {(stations.data ?? []).map((s: any) => (
              <option key={s.code} value={s.code}>{s.code}</option>
            ))}
          </select>
        </div>
        <div>
          <label className="mb-1 block text-xs text-(--steel)">Type</label>
          <select name="type" defaultValue={sp.type ?? ""} className="rounded-sm border border-(--border) px-2 py-1.5 text-sm">
            <option value="">All</option>
            {TYPES.map((t) => (
              <option key={t} value={t}>{t.replace("_", " ")}</option>
            ))}
          </select>
        </div>
        <div>
          <label className="mb-1 block text-xs text-(--steel)">Equipment</label>
          <input name="q" defaultValue={sp.q ?? ""} placeholder="Name or code" className="rounded-sm border border-(--border) px-2 py-1.5 text-sm" />
        </div>
        <button className="btn-primary px-4 py-1.5 text-sm" type="submit">Filter</button>
        <Link href="/admin/ledger" className="btn-secondary px-4 py-1.5 text-sm">Reset</Link>
      </form>

      <div className="panel overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="text-left text-xs uppercase text-(--steel)">
            <tr>
              <th className="p-3">When</th>
              <th className="p-3">Station</th>
              <th className="p-3">Equipment</th>
              <th className="p-3">Type</th>
              <th className="p-3 text-right">Qty</th>
              <th className="p-3">By</th>
              <th className="p-3">Reason</th>
            </tr>
          </thead>
          <tbody>
            {rows.length === 0 && (
              <tr><td colSpan={7} className="p-6 text-center text-(--steel)">No ledger entries match.</td></tr>
            )}
            {rows.map((r) => (
              <tr key={r.id} className="border-t border-(--border)">
                <td className="whitespace-nowrap p-3">{new Date(r.created_at).toLocaleString("en-GB", { dateStyle: "short", timeStyle: "short" })}</td>
                <td className="id-code p-3">{r.station_code}</td>
                <td className="p-3">{r.equipment_name}</td>
                <td className="p-3"><span className="tag tag-neutral">{r.transaction_type.replace("_", " ")}</span></td>
                <td className={`p-3 text-right font-medium ${r.quantity < 0 ? "text-(--brick)" : "text-(--teal)"}`}>
                  {r.quantity > 0 ? `+${r.quantity}` : r.quantity}
                </td>
                <td className="p-3">{r.performed_by_name ?? "—"}</td>
                <td className="p-3 text-(--steel)">{r.reason ?? ""}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="mt-4 flex items-center justify-between text-sm text-(--steel)">
        <span>{total} entr{total === 1 ? "y" : "ies"} · page {page} of {pages}</span>
        <div className="flex gap-2">
          {page > 1 && <Link href={qs(page - 1)} className="btn-secondary px-3 py-1.5">Previous</Link>}
          {page < pages && <Link href={qs(page + 1)} className="btn-secondary px-3 py-1.5">Next</Link>}
        </div>
      </div>
    </div>
  );
}
