import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { requireAnyPermission } from "@/features/admin/access";
import { StockLevelsGrid } from "./StockLevelsGrid";

export default async function StockLevelsPage({ searchParams }: { searchParams: Promise<{ station?: string }> }) {
  await requireAnyPermission(["manage_catalogue"]);
  const { station } = await searchParams;
  const supabase = await createClient();
  const { data: stations } = await supabase.from("stations").select("id, code, name").eq("is_active", true).neq("station_type", "NO_STOCK_TURNAROUND").order("code");

  let equipment: any[] = [];
  let overrides: any[] = [];
  if (station) {
    const [eq, ov] = await Promise.all([
      supabase.from("equipment_types").select("id, source_code, name, reorder_threshold, minimum_stock, target_stock, maximum_stock").eq("is_active", true).order("name"),
      supabase.from("station_stock_levels").select("equipment_type_id, reorder_threshold, minimum_stock, target_stock, maximum_stock").eq("station_id", station),
    ]);
    equipment = eq.data ?? [];
    overrides = ov.data ?? [];
  }

  return (
    <div>
      <h1 className="mb-1 text-xl font-semibold text-(--navy)">Station stock levels</h1>
      <p className="mb-4 text-sm text-(--steel)">
        Set reorder thresholds and stock levels per station. Blank cells follow the network default from the equipment catalogue.
      </p>
      <form className="mb-4 flex gap-3" method="get">
        <select name="station" defaultValue={station ?? ""} className="rounded-sm border border-(--border) px-3 py-2 text-sm">
          <option value="">Choose a station…</option>
          {(stations ?? []).map((s: any) => <option key={s.id} value={s.id}>{s.code} — {s.name}</option>)}
        </select>
        <button className="btn-primary px-4 py-2 text-sm">Open</button>
        <Link href="/admin/catalogue" className="btn-secondary px-4 py-2 text-sm">Network defaults</Link>
      </form>
      {station && <StockLevelsGrid key={station} stationId={station} equipment={equipment} overrides={overrides} />}
    </div>
  );
}
