"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

type Result = { ok: true; id?: string } | { ok: false; error: string };

function refresh(id?: string) {
  revalidatePath("/admin/adjustments");
  if (id) revalidatePath(`/admin/adjustments/${id}`);
}

export async function requestAdjustment(input: {
  stationId: string; equipmentId: string; direction: string; quantity: number; reasonCode: string; notes: string;
}): Promise<Result> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("request_stock_adjustment", {
    p_station_id: input.stationId, p_equipment_type_id: input.equipmentId, p_direction: input.direction,
    p_quantity: input.quantity, p_reason_code: input.reasonCode, p_notes: input.notes,
  });
  if (error) return { ok: false, error: error.message };
  refresh();
  return { ok: true, id: data as string };
}

export async function approveAdjustment(id: string, note: string): Promise<Result> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("approve_stock_adjustment", { p_id: id, p_note: note || null });
  if (error) return { ok: false, error: error.message };
  refresh(id);
  revalidatePath("/dashboard");
  return { ok: true };
}

export async function rejectAdjustment(id: string, note: string): Promise<Result> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("reject_stock_adjustment", { p_id: id, p_note: note });
  if (error) return { ok: false, error: error.message };
  refresh(id);
  return { ok: true };
}

export async function cancelAdjustment(id: string): Promise<Result> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("cancel_stock_adjustment", { p_id: id });
  if (error) return { ok: false, error: error.message };
  refresh(id);
  return { ok: true };
}
