"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

type Result<T = object> = ({ success: true } & T) | { success: false; error: string };
type Line = { equipment_type_id: string; quantity: number };

function done() {
  revalidatePath("/exchanges");
  revalidatePath("/transfers");
}

export async function createExchangeAction(input: {
  outstationId: string; items: Line[]; reason: string; priority: string;
  flightNumber: string; flightDate: string; requestKey: string;
}): Promise<Result<{ exchangeId: string }>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("create_exchange", {
    p_outstation_id: input.outstationId, p_items: input.items, p_reason: input.reason || null, p_priority: input.priority,
    p_flight_number: input.flightNumber, p_flight_date: input.flightDate || null, p_request_key: input.requestKey,
  });
  if (error) return { success: false, error: error.message };
  done();
  return { success: true, exchangeId: data as string };
}

export async function startReturnAction(input: {
  exchangeId: string; items: Line[]; reason: string; priority: string; flightNumber: string; flightDate: string;
}): Promise<Result<{ transferId: string }>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("start_exchange_return", {
    p_exchange_id: input.exchangeId, p_items: input.items, p_reason: input.reason || null, p_priority: input.priority,
    p_flight_number: input.flightNumber, p_flight_date: input.flightDate || null,
  });
  if (error) return { success: false, error: error.message };
  done();
  revalidatePath(`/exchanges/${input.exchangeId}`);
  return { success: true, transferId: data as string };
}

export async function closeExchangeAction(exchangeId: string, note: string): Promise<Result> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("close_exchange", { p_exchange_id: exchangeId, p_note: note || null });
  if (error) return { success: false, error: error.message };
  done();
  revalidatePath(`/exchanges/${exchangeId}`);
  return { success: true };
}

export async function requestNoReturnAction(exchangeId: string, reason: string): Promise<Result> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("request_exchange_no_return", { p_exchange_id: exchangeId, p_reason: reason });
  if (error) return { success: false, error: error.message };
  done();
  revalidatePath(`/exchanges/${exchangeId}`);
  return { success: true };
}

export async function decideNoReturnAction(exchangeId: string, approve: boolean, note: string): Promise<Result> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("decide_exchange_no_return", { p_exchange_id: exchangeId, p_approve: approve, p_note: note });
  if (error) return { success: false, error: error.message };
  done();
  revalidatePath(`/exchanges/${exchangeId}`);
  return { success: true };
}
