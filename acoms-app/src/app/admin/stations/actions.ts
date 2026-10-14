"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

type Result = { ok: true } | { ok: false; error: string };

export async function saveStation(input: {
  id: string | null; code: string; name: string; stationType: string;
  airportCode: string; country: string; timezone: string;
}): Promise<Result> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("save_station", {
    p_id: input.id, p_code: input.code, p_name: input.name, p_station_type: input.stationType,
    p_airport_code: input.airportCode, p_country: input.country, p_timezone: input.timezone,
  });
  if (error) return { ok: false, error: error.message };
  revalidatePath("/admin/stations");
  return { ok: true };
}

export async function setStationActive(id: string, active: boolean, reason: string): Promise<Result> {
  const supabase = await createClient();
  const { error } = await supabase.rpc("set_station_active", { p_id: id, p_active: active, p_reason: reason || null });
  if (error) return { ok: false, error: error.message };
  revalidatePath("/admin/stations");
  return { ok: true };
}
