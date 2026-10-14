"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export async function saveStationStockLevels(
  stationId: string,
  items: { equipment_type_id: string; reorder_threshold: number | null; minimum_stock: number | null; target_stock: number | null; maximum_stock: number | null }[]
): Promise<{ ok: true; count: number } | { ok: false; error: string }> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("set_station_stock_levels", { p_station_id: stationId, p_items: items });
  if (error) return { ok: false, error: error.message };
  revalidatePath("/admin/stock-levels");
  revalidatePath("/dashboard", "layout");
  return { ok: true, count: data as number };
}
