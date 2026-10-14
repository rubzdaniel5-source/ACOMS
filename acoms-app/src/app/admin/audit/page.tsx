import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { requireAnyPermission } from "@/features/admin/access";
import { AuditRows } from "./AuditRows";

const PAGE_SIZE = 50;
const CATEGORIES = ["transfer", "damage", "loss", "inventory", "adjustment", "user", "role", "catalogue", "station", "setting", "integrity"];

type SP = { cat?: string; actor?: string; station?: string; q?: string; from?: string; to?: string; page?: string };

export default async function AuditPage({ searchParams }: { searchParams: Promise<SP> }) {
  await requireAnyPermission(["manage_configuration"]);
  const sp = await searchParams;
  const page = Math.max(1, Number(sp.page) || 1);
  const supabase = await createClient();

  const clean = (s: string) => s.replace(/[%,()*]/g, " ").trim();
  let query = supabase
    .from("audit_logs")
    .select("id, created_at, action, actor_label, entity_type, entity_id, station_id, reason, before_state, after_state, stations(code)", { count: "exact" })
    .order("created_at", { ascending: false })
    .range((page - 1) * PAGE_SIZE, page * PAGE_SIZE - 1);
  if (sp.cat) query = query.like("action", `${clean(sp.cat)}.%`);
  if (sp.actor && clean(sp.actor)) query = query.ilike("actor_label", `%${clean(sp.actor)}%`);
  if (sp.station) query = query.eq("station_id", sp.station);
  if (sp.q && clean(sp.q)) query = query.or(`reason.ilike.%${clean(sp.q)}%,action.ilike.%${clean(sp.q)}%`);
  if (sp.from) query = query.gte("created_at", `${sp.from}T00:00:00+03:00`);
  if (sp.to) query = query.lte("created_at", `${sp.to}T23:59:59+03:00`);

  const [{ data, count }, stations] = await Promise.all([query, supabase.from("stations").select("id, code").order("code")]);
  const total = count ?? 0;
  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE));
  const qs = (p: number) => {
    const u = new URLSearchParams();
    for (const [k, v] of Object.entries(sp)) if (v && k !== "page") u.set(k, v);
    u.set("page", String(p));
    return `/admin/audit?${u.toString()}`;
  };
  const input = "rounded-sm border border-(--border) px-2 py-1.5 text-sm";

  return (
    <div>
      <h1 className="mb-1 text-xl font-semibold text-(--navy)">Audit log</h1>
      <p className="mb-4 text-sm text-(--steel)">Who did what, where and when. Entries cannot be edited or deleted by anyone. Times shown in East Africa Time.</p>

      <form method="get" className="panel mb-4 flex flex-wrap items-end gap-3 p-4">
        <div><label className="mb-1 block text-xs text-(--steel)">Area</label>
          <select name="cat" defaultValue={sp.cat ?? ""} className={input}>
            <option value="">All</option>{CATEGORIES.map((c) => <option key={c} value={c}>{c}</option>)}
          </select></div>
        <div><label className="mb-1 block text-xs text-(--steel)">Person</label>
          <input name="actor" defaultValue={sp.actor ?? ""} placeholder="Name" className={input} /></div>
        <div><label className="mb-1 block text-xs text-(--steel)">Station</label>
          <select name="station" defaultValue={sp.station ?? ""} className={input}>
            <option value="">All</option>{(stations.data ?? []).map((s: any) => <option key={s.id} value={s.id}>{s.code}</option>)}
          </select></div>
        <div><label className="mb-1 block text-xs text-(--steel)">From</label><input type="date" name="from" defaultValue={sp.from ?? ""} className={input} /></div>
        <div><label className="mb-1 block text-xs text-(--steel)">To</label><input type="date" name="to" defaultValue={sp.to ?? ""} className={input} /></div>
        <div><label className="mb-1 block text-xs text-(--steel)">Text</label>
          <input name="q" defaultValue={sp.q ?? ""} placeholder="Action or reason" className={input} /></div>
        <button className="btn-primary px-4 py-1.5 text-sm">Filter</button>
        <Link href="/admin/audit" className="btn-secondary px-4 py-1.5 text-sm">Reset</Link>
      </form>

      <AuditRows rows={((data ?? []) as any[]).map((r) => ({ ...r, station_code: r.stations?.code ?? null, stations: undefined }))} />

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
