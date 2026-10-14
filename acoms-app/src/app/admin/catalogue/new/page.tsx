import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { requireAnyPermission } from "@/features/admin/access";
import { EquipmentForm } from "../EquipmentForm";

export default async function NewEquipmentPage() {
  await requireAnyPermission(["manage_catalogue"]);
  const supabase = await createClient();
  const { data } = await supabase.from("equipment_categories").select("id, name").eq("is_active", true).order("name");
  return (
    <div>
      <Link href="/admin/catalogue" className="mb-4 inline-block text-sm text-(--steel) hover:text-(--navy)">← Back to catalogue</Link>
      <h1 className="mb-6 text-xl font-semibold text-(--navy)">New equipment</h1>
      <EquipmentForm categories={(data ?? []) as any} />
    </div>
  );
}
