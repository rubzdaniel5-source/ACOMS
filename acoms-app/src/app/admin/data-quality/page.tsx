import { createClient } from "@/lib/supabase/server";
import { requireAnyPermission } from "@/features/admin/access";
import { FlagResolver } from "./FlagResolver";

export default async function DataQualityPage() {
  await requireAnyPermission(["manage_catalogue"]);
  const supabase = await createClient();
  const { data } = await supabase
    .from("equipment_types")
    .select("id, source_code, name, data_quality_note, equipment_categories(name)")
    .eq("has_data_quality_flag", true)
    .order("name");
  const items = ((data ?? []) as any[]).map((r) => ({ ...r, category: r.equipment_categories?.name ?? "" }));

  return (
    <div>
      <h1 className="mb-1 text-xl font-semibold text-(--navy)">Data quality</h1>
      <p className="mb-6 text-sm text-(--steel)">
        Items imported from the original workbook with placeholder or doubtful codes. Confirm the real code with operations, then enter it here to clear the flag.
      </p>
      {items.length === 0 ? (
        <p className="panel p-6 text-center text-sm text-(--teal)">Nothing needs review.</p>
      ) : (
        <div className="space-y-3">{items.map((i) => <FlagResolver key={i.id} item={i} />)}</div>
      )}
    </div>
  );
}
