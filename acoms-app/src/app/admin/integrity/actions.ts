"use server";

import { createClient } from "@/lib/supabase/server";

export type IntegritySummary = { check_code: string; label: string; description: string; examined: number; failures: number };
export type IntegrityDetail = { check_code: string; station_code: string; source_code: string; equipment_name: string; expected: number; actual: number; detail: string };

export async function runIntegrityCheck(): Promise<
  { ok: true; ranAt: string; summary: IntegritySummary[]; details: IntegrityDetail[] } | { ok: false; error: string }
> {
  const supabase = await createClient();
  const summary = await supabase.rpc("integrity_summary");
  if (summary.error) return { ok: false, error: summary.error.message };
  const details = await supabase.rpc("integrity_details", { p_check: null });
  if (details.error) return { ok: false, error: details.error.message };
  return {
    ok: true,
    ranAt: new Date().toISOString(),
    summary: (summary.data ?? []).map((s: any) => ({ ...s, examined: Number(s.examined), failures: Number(s.failures) })),
    details: (details.data ?? []).map((d: any) => ({ ...d, expected: Number(d.expected), actual: Number(d.actual) })),
  };
}
