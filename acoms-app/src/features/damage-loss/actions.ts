"use server";

import { createClient } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";

interface ActionResult {
  success: boolean;
  error?: string;
}

export async function reportDamageAction(input: {
  equipmentTypeId: string;
  stationId: string;
  quantity: number;
  reason: string;
}): Promise<ActionResult & { reportId?: string }> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("report_damage", {
    p_equipment_type_id: input.equipmentTypeId,
    p_station_id: input.stationId,
    p_quantity: input.quantity,
    p_reason: input.reason,
  });
  if (error) return { success: false, error: error.message };
  revalidatePath("/damage-loss");
  return { success: true, reportId: data as string };
}

export async function reportLossAction(input: {
  equipmentTypeId: string;
  stationId: string;
  quantity: number;
  circumstances: string;
}): Promise<ActionResult & { reportId?: string }> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("report_loss", {
    p_equipment_type_id: input.equipmentTypeId,
    p_station_id: input.stationId,
    p_quantity: input.quantity,
    p_circumstances: input.circumstances,
  });
  if (error) return { success: false, error: error.message };
  revalidatePath("/damage-loss");
  return { success: true, reportId: data as string };
}

async function callRpc(fn: string, args: Record<string, unknown>, path: string): Promise<ActionResult> {
  const supabase = await createClient();
  const { error } = await supabase.rpc(fn, args);
  if (error) return { success: false, error: error.message };
  revalidatePath(path);
  return { success: true };
}

// Damage lifecycle actions
export async function startDamageReviewAction(id: string) {
  return callRpc("start_damage_review", { p_report_id: id }, `/damage-loss/${id}`);
}
export async function assessDamageAction(id: string, outcome: "REPAIRABLE" | "RETIRE", notes: string) {
  return callRpc("assess_damage", { p_report_id: id, p_outcome: outcome, p_notes: notes }, `/damage-loss/${id}`);
}
export async function startRepairAction(id: string) {
  return callRpc("start_repair", { p_report_id: id }, `/damage-loss/${id}`);
}
export async function returnToServiceAction(id: string) {
  return callRpc("return_to_service", { p_report_id: id }, `/damage-loss/${id}`);
}
export async function retireEquipmentAction(id: string) {
  return callRpc("retire_equipment", { p_report_id: id }, `/damage-loss/${id}`);
}
export async function disposeEquipmentAction(id: string) {
  return callRpc("dispose_equipment", { p_report_id: id }, `/damage-loss/${id}`);
}

// Loss lifecycle actions
export async function startLossInvestigationAction(id: string) {
  return callRpc("start_loss_investigation", { p_report_id: id }, `/damage-loss/${id}`);
}
export async function recoverLossAction(id: string, notes: string) {
  return callRpc("recover_loss", { p_report_id: id, p_resolution_notes: notes }, `/damage-loss/${id}`);
}
export async function confirmLossAction(id: string, notes: string) {
  return callRpc("confirm_loss", { p_report_id: id, p_resolution_notes: notes }, `/damage-loss/${id}`);
}
export async function closeLossReportAction(id: string) {
  return callRpc("close_loss_report", { p_report_id: id }, `/damage-loss/${id}`);
}
