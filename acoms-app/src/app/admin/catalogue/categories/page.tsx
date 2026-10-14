import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { requireAnyPermission } from "@/features/admin/access";
import { CategoryManager } from "./CategoryManager";

export default async function CategoriesPage() {
  await requireAnyPermission(["manage_catalogue"]);
  const supabase = await createClient();
  const [cats, types] = await Promise.all([
    supabase.from("equipment_categories").select("id, code, name, is_active").order("name"),
    supabase.from("equipment_types").select("category_id"),
  ]);
  const counts: Record<string, number> = {};
  for (const t of (types.data ?? []) as any[]) counts[t.category_id] = (counts[t.category_id] ?? 0) + 1;

  return (
    <div>
      <Link href="/admin/catalogue" className="mb-4 inline-block text-sm text-(--steel) hover:text-(--navy)">← Back to catalogue</Link>
      <h1 className="mb-1 text-xl font-semibold text-(--navy)">Categories</h1>
      <p className="mb-6 text-sm text-(--steel)">Groups used to organise equipment. Codes cannot be changed after creation.</p>
      <CategoryManager categories={((cats.data ?? []) as any[]).map((c) => ({ ...c, count: counts[c.id] ?? 0 }))} />
    </div>
  );
}
