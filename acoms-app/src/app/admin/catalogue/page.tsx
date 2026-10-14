import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { requireAnyPermission } from "@/features/admin/access";
import { CatalogueTable } from "./CatalogueTable";

export default async function CataloguePage() {
  await requireAnyPermission(["manage_catalogue"]);
  const supabase = await createClient();
  const { data } = await supabase
    .from("equipment_types")
    .select("id, source_code, name, is_active, has_data_quality_flag, tracking_method, reorder_threshold, minimum_stock, target_stock, maximum_stock, reconciliation_tolerance, unit_of_measure, equipment_categories(name)")
    .order("name");

  const rows = ((data ?? []) as any[]).map((r) => ({ ...r, category: r.equipment_categories?.name ?? "", equipment_categories: undefined }));

  return (
    <div>
      <div className="mb-4 flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="mb-1 text-xl font-semibold text-(--navy)">Equipment catalogue</h1>
          <p className="text-sm text-(--steel)">Every equipment type, its stock levels and reconciliation tolerance.</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Link href="/admin/catalogue/categories" className="btn-secondary px-3 py-2 text-sm">Categories</Link>
          <Link href="/admin/catalogue/import" className="btn-secondary px-3 py-2 text-sm">Import CSV</Link>
          <Link href="/admin/catalogue/new" className="btn-primary px-3 py-2 text-sm">New equipment</Link>
        </div>
      </div>
      <CatalogueTable rows={rows} />
    </div>
  );
}
