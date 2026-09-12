import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { StationInventoryTable } from "./StationInventoryTable";

export default async function StationInventoryPage() {
  const supabase = await createClient();
  const { data } = await supabase
    .from("v_inventory_health")
    .select("station_code, station_name, source_code, equipment_name, current_stock, minimum_level, variance, status")
    .order("station_code");

  return (
    <div className="mx-auto max-w-6xl px-4 py-8">
      <Link href="/dashboard" className="mb-4 inline-block text-sm text-(--steel) hover:text-(--navy)">← Back to Dashboard</Link>
      <h1 className="mb-1 text-xl font-semibold text-(--navy)">Station Inventory</h1>
      <p className="mb-6 text-sm text-(--steel)">The full station × equipment position — search and filter to find what needs attention.</p>

      <StationInventoryTable rows={(data ?? []) as any} />
    </div>
  );
}
