"use server";

import { createClient } from "@/lib/supabase/server";

export type OpeningBalanceResult = { ok: true; count: number } | { ok: false; error: string };

export async function submitOpeningBalances(
  stationId: string,
  items: { equipment_type_id: string; quantity: number }[],
  reason: string
): Promise<OpeningBalanceResult> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("record_opening_balances", {
    p_station_id: stationId,
    p_items: items,
    p_reason: reason.trim() || null,
  });
  if (error) return { ok: false, error: error.message };
  return { ok: true, count: data as number };
}
