import { createClient } from "@/lib/supabase/server";
import { requireAnyPermission } from "@/features/admin/access";
import { OpeningBalanceForm } from "./OpeningBalanceForm";

export default async function OpeningBalancesPage() {
  await requireAnyPermission(["record_opening_balance"]);
  const supabase = await createClient();

  const [stations, equipment, existing] = await Promise.all([
    supabase.from("stations").select("id, code, name, station_type").eq("is_active", true).neq("station_type", "NO_STOCK_TURNAROUND").order("code"),
    supabase.from("equipment_types").select("id, source_code, name").eq("is_active", true).order("name"),
    supabase.from("inventory_transactions").select("station_id, equipment_type_id").eq("transaction_type", "OPENING_BALANCE"),
  ]);

  return (
    <div>
      <h1 className="mb-1 text-xl font-semibold text-(--navy)">Opening Balances</h1>
      <p className="mb-6 text-sm text-(--steel)">
        Record the starting stock once per station and equipment type. After that, changes must go through stock adjustments.
      </p>
      <OpeningBalanceForm
        stations={(stations.data ?? []) as any}
        equipment={(equipment.data ?? []) as any}
        recorded={((existing.data ?? []) as any[]).map((r) => `${r.station_id}:${r.equipment_type_id}`)}
      />
    </div>
  );
}
