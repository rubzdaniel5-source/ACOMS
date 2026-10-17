"use server";

import { createClient } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";

/**
 * Thin wrappers around the SQL functions from migration 011. These do NOT
 * duplicate business logic — every rule (ADR-007, tolerance checks, state
 * validation) lives in the database function itself. This layer only
 * translates errors into a shape the UI can render, and revalidates the
 * page cache after a successful mutation.
 */

interface ActionResult {
  success: boolean;
  error?: string;
}

export async function requestTransferAction(input: {
  fromStationId: string;
  toStationId: string;
  items: { equipment_type_id: string; quantity: number }[];
  reason?: string;
  priority?: string;
  flightNumber?: string;
  flightDate?: string;
}): Promise<ActionResult & { transferId?: string }> {
  const supabase = await createClient();
  // Check the flight first, so an invalid flight creates nothing.
  let legId: string | null = null;
  if (input.flightNumber && input.flightDate) {
    const leg = await supabase.rpc("ensure_flight_leg", {
      p_flight_number: input.flightNumber, p_date: input.flightDate,
      p_origin_station_id: input.fromStationId, p_destination_station_id: input.toStationId,
    });
    if (leg.error) return { success: false, error: leg.error.message };
    legId = leg.data as string;
  }
  const { data, error } = await supabase.rpc("request_transfer", {
    p_from_station_id: input.fromStationId,
    p_to_station_id: input.toStationId,
    p_items: input.items,
    p_reason: input.reason ?? null,
    p_priority: input.priority ?? "NORMAL",
  });

  if (error) return { success: false, error: error.message };
  if (legId) {
    const link = await supabase.rpc("set_transfer_flight", { p_transfer_id: data as string, p_flight_leg_id: legId });
    if (link.error) return { success: false, error: `The request was created but the flight could not be linked: ${link.error.message}`, transferId: data as string };
  }
  revalidatePath("/transfers");
  return { success: true, transferId: data as string };
}

export async function approveTransferAction(
  transferId: string,
  approvedItems: { item_id: string; quantity_approved: number }[],
  notes?: string
): Promise<ActionResult> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("approve_transfer", {
    p_transfer_id: transferId,
    p_approved_items: approvedItems,
    p_notes: notes ?? null,
  });
  if (error) return { success: false, error: error.message };
  revalidatePath(`/transfers/${transferId}`);
  return { success: true };
}

export async function rejectTransferAction(
  transferId: string,
  reason: string
): Promise<ActionResult> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("reject_transfer", {
    p_transfer_id: transferId,
    p_reason: reason,
  });
  if (error) return { success: false, error: error.message };
  revalidatePath(`/transfers/${transferId}`);
  return { success: true };
}

export async function cancelTransferAction(
  transferId: string,
  reason: string
): Promise<ActionResult> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("cancel_transfer", { p_transfer_id: transferId, p_reason: reason });
  if (error) return { success: false, error: error.message };
  revalidatePath(`/transfers/${transferId}`);
  revalidatePath("/transfers");
  return { success: true };
}

export async function dispatchTransferAction(
  transferId: string,
  dispatchedItems: { item_id: string; quantity_dispatched: number }[]
): Promise<ActionResult> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("dispatch_transfer", {
    p_transfer_id: transferId,
    p_dispatched_items: dispatchedItems,
  });
  if (error) return { success: false, error: error.message };
  revalidatePath(`/transfers/${transferId}`);
  return { success: true };
}

export async function receiveTransferAction(
  transferId: string,
  receivedItems: { item_id: string; quantity_counted: number; quantity_damaged: number }[],
  isFinal: boolean,
  notes?: string
): Promise<ActionResult> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("receive_transfer", {
    p_transfer_id: transferId,
    p_received_items: receivedItems,
    p_final: isFinal,
    p_notes: notes?.trim() || null,
  });
  if (error) return { success: false, error: error.message };
  revalidatePath(`/transfers/${transferId}`);
  return { success: true };
}

export async function investigateExcessAction(holdId: string, transferId: string, findings: string): Promise<ActionResult> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("record_excess_investigation", { p_hold_id: holdId, p_findings: findings });
  if (error) return { success: false, error: error.message };
  revalidatePath(`/transfers/${transferId}`);
  return { success: true };
}

export async function resolveExcessAction(
  holdId: string,
  transferId: string,
  treatment: "ACCEPT_AS_STOCK" | "REMOVE_FROM_RECORDS",
  reason: string
): Promise<ActionResult> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("resolve_excess_hold", { p_hold_id: holdId, p_treatment: treatment, p_reason: reason });
  if (error) return { success: false, error: error.message };
  revalidatePath(`/transfers/${transferId}`);
  return { success: true };
}

export async function reconcileTransferAction(
  transferId: string,
  reconciliationItems: { item_id: string; quantity_damaged: number; quantity_missing: number }[],
  notes?: string
): Promise<ActionResult & { finalStatus?: string }> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("reconcile_transfer", {
    p_transfer_id: transferId,
    p_reconciliation_items: reconciliationItems,
    p_notes: notes ?? null,
  });
  if (error) return { success: false, error: error.message };
  revalidatePath(`/transfers/${transferId}`);
  return { success: true, finalStatus: data as string };
}

export async function closeTransferAction(transferId: string): Promise<ActionResult> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("close_transfer", { p_transfer_id: transferId });
  if (error) return { success: false, error: error.message };
  revalidatePath(`/transfers/${transferId}`);
  return { success: true };
}

export async function resolveDiscrepancyAction(
  transferId: string,
  resolutionReason: string
): Promise<ActionResult> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("resolve_discrepancy", {
    p_transfer_id: transferId,
    p_resolution_reason: resolutionReason,
  });
  if (error) return { success: false, error: error.message };
  revalidatePath(`/transfers/${transferId}`);
  return { success: true };
}

export async function approveBelowMinimumAction(transferId: string, reason: string): Promise<ActionResult> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("approve_below_minimum_dispatch", { p_transfer_id: transferId, p_reason: reason });
  if (error) return { success: false, error: error.message };
  revalidatePath(`/transfers/${transferId}`);
  return { success: true };
}
