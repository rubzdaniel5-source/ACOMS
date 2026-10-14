import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { requireAnyPermission } from "@/features/admin/access";
import { AdjustmentForm } from "./AdjustmentForm";

export default async function NewAdjustmentPage() {
  await requireAnyPermission(["request_adjustment"]);
  const supabase = await createClient();
  const [stations, equipment, balances] = await Promise.all([
    supabase.from("stations").select("id, code, name").eq("is_active", true).neq("station_type", "NO_STOCK_TURNAROUND").order("code"),
    supabase.from("equipment_types").select("id, source_code, name").eq("is_active", true).order("name"),
    supabase.from("inventory_balances").select("station_id, equipment_type_id, available_quantity"),
  ]);
  const available: Record<string, number> = {};
  for (const b of (balances.data ?? []) as any[]) available[`${b.station_id}:${b.equipment_type_id}`] = b.available_quantity;

  return (
    <div>
      <Link href="/admin/adjustments" className="mb-4 inline-block text-sm text-(--steel) hover:text-(--navy)">← Back to adjustments</Link>
      <h1 className="mb-1 text-xl font-semibold text-(--navy)">New stock adjustment</h1>
      <p className="mb-6 text-sm text-(--steel)">This does not change stock yet. A different authorised person must approve it first.</p>
      <AdjustmentForm stations={(stations.data ?? []) as any} equipment={(equipment.data ?? []) as any} available={available} />
    </div>
  );
}
