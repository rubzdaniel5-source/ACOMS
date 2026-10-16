"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

type Result = { ok: true } | { ok: false; error: string };

export async function createRoute(input: {
  flightNumber: string; origin: string; destination: string; days: number[]; validFrom: string; validTo: string; notes: string;
}): Promise<Result> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("create_flight_route", {
    p_flight_number: input.flightNumber, p_origin_code: input.origin, p_destination_code: input.destination,
    p_days: input.days, p_valid_from: input.validFrom, p_valid_to: input.validTo || null, p_notes: input.notes || null,
  });
  if (error) return { ok: false, error: error.message };
  revalidatePath("/admin/flights");
  return { ok: true };
}

export async function setRouteActive(id: string, active: boolean, reason: string): Promise<Result> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("set_flight_route_active", { p_route_id: id, p_active: active, p_reason: reason });
  if (error) return { ok: false, error: error.message };
  revalidatePath("/admin/flights");
  return { ok: true };
}

export async function createOneOffLeg(input: {
  flightNumber: string; date: string; originId: string; destinationId: string; reason: string;
}): Promise<Result> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("create_one_off_flight_leg", {
    p_flight_number: input.flightNumber, p_date: input.date, p_origin_station_id: input.originId,
    p_destination_station_id: input.destinationId, p_reason: input.reason,
  });
  if (error) return { ok: false, error: error.message };
  revalidatePath("/admin/flights");
  return { ok: true };
}

export async function cancelLeg(id: string, reason: string): Promise<Result> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("cancel_flight_leg", { p_leg_id: id, p_reason: reason });
  if (error) return { ok: false, error: error.message };
  revalidatePath("/admin/flights");
  return { ok: true };
}
