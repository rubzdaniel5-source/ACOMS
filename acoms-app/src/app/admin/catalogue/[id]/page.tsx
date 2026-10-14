import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { requireAnyPermission } from "@/features/admin/access";
import { EquipmentForm } from "../EquipmentForm";
import { EquipmentSidePanel } from "./EquipmentSidePanel";

export default async function EquipmentDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  await requireAnyPermission(["manage_catalogue"]);
  const supabase = await createClient();

  const [item, cats, aliases, balances] = await Promise.all([
    supabase.from("equipment_types").select("*").eq("id", id).maybeSingle(),
    supabase.from("equipment_categories").select("id, name").eq("is_active", true).order("name"),
    supabase.from("equipment_aliases").select("id, alias").eq("equipment_type_id", id).order("alias"),
    supabase.from("inventory_balances").select("available_quantity, reserved_quantity, in_transit_quantity, damaged_quantity, missing_quantity").eq("equipment_type_id", id),
  ]);
  const e = item.data as any;
  if (!e) notFound();
  const onHand = ((balances.data ?? []) as any[]).reduce(
    (s, b) => s + b.available_quantity + b.reserved_quantity + b.in_transit_quantity + b.damaged_quantity + b.missing_quantity, 0);

  return (
    <div>
      <Link href="/admin/catalogue" className="mb-4 inline-block text-sm text-(--steel) hover:text-(--navy)">← Back to catalogue</Link>
      <div className="mb-6 flex items-center gap-3">
        <h1 className="text-xl font-semibold text-(--navy)">{e.name}</h1>
        {!e.is_active && <span className="tag tag-brick">Inactive</span>}
        {e.has_data_quality_flag && <span className="tag tag-amber">Needs review</span>}
      </div>
      {e.has_data_quality_flag && (
        <p className="mb-4 rounded-sm px-3 py-2 text-sm text-(--amber)" style={{ background: "var(--amber-surface)" }}>
          {e.data_quality_note} <Link href="/admin/data-quality" className="underline">Resolve in Data Quality</Link>
        </p>
      )}
      <div className="grid gap-6 lg:grid-cols-[1fr_20rem]">
        <EquipmentForm categories={(cats.data ?? []) as any} initial={e} />
        <EquipmentSidePanel id={id} isActive={e.is_active} onHand={onHand} aliases={(aliases.data ?? []) as any} />
      </div>
    </div>
  );
}
