"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

type Result = { ok: true; id?: string } | { ok: false; error: string };

function refresh(id?: string) {
  revalidatePath("/admin/catalogue");
  revalidatePath("/admin/data-quality");
  if (id) revalidatePath(`/admin/catalogue/${id}`);
}

export async function saveEquipment(id: string | null, categoryId: string, payload: Record<string, unknown>): Promise<Result> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("save_equipment_type", { p_id: id, p_category_id: categoryId, p_payload: payload });
  if (error) return { ok: false, error: error.message };
  refresh(data as string);
  return { ok: true, id: data as string };
}

export async function setEquipmentActive(id: string, active: boolean, reason: string): Promise<Result> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("set_equipment_active", { p_id: id, p_active: active, p_reason: reason || null });
  if (error) return { ok: false, error: error.message };
  refresh(id);
  return { ok: true };
}

export async function setShortageAlert(id: string, value: boolean): Promise<Result> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("set_equipment_shortage_alert", { p_id: id, p_value: value });
  if (error) return { ok: false, error: error.message };
  refresh(id);
  return { ok: true };
}

export async function addAlias(id: string, alias: string): Promise<Result> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("add_equipment_alias", { p_equipment_id: id, p_alias: alias });
  if (error) return { ok: false, error: error.message };
  refresh(id);
  return { ok: true };
}

export async function removeAlias(id: string, aliasId: string): Promise<Result> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("remove_equipment_alias", { p_alias_id: aliasId });
  if (error) return { ok: false, error: error.message };
  refresh(id);
  return { ok: true };
}

export async function saveCategory(id: string | null, code: string, name: string, isActive: boolean): Promise<Result> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("save_equipment_category", { p_id: id, p_code: code, p_name: name, p_is_active: isActive });
  if (error) return { ok: false, error: error.message };
  revalidatePath("/admin/catalogue/categories");
  refresh();
  return { ok: true };
}

export async function resolveFlag(id: string, confirmedCode: string, note: string): Promise<Result> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("resolve_data_quality_flag", { p_id: id, p_confirmed_code: confirmedCode, p_note: note || null });
  if (error) return { ok: false, error: error.message };
  refresh(id);
  return { ok: true };
}

export async function previewImport(rows: Record<string, unknown>[]): Promise<
  { ok: true; rows: { row_number: number; source_code: string; action: string; error: string | null }[] } | { ok: false; error: string }
> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("preview_equipment_import", { p_rows: rows });
  if (error) return { ok: false, error: error.message };
  return { ok: true, rows: (data ?? []) as any };
}

export async function applyImport(rows: Record<string, unknown>[]): Promise<{ ok: true; count: number } | { ok: false; error: string }> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("apply_equipment_import", { p_rows: rows });
  if (error) return { ok: false, error: error.message };
  refresh();
  return { ok: true, count: data as number };
}
