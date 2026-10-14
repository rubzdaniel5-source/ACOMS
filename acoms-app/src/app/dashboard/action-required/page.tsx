import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { fetchAll } from "@/lib/supabase/fetchAll";
import { getCurrentUserPermissions, getCurrentUserId } from "@/features/auth/permissions";
import { buildAlerts, fetchAlertSources } from "@/features/dashboard/alerts";
import { AlertList } from "@/components/ui/AlertList";

export default async function ActionRequiredPage() {
  const supabase = await createClient();
  const [inv, perms, userId] = await Promise.all([
    fetchAll<any>((from, to) =>
      supabase
        .from("v_inventory_health")
        .select("station_id, station_code, source_code, equipment_name, current_stock, minimum_level, status")
        .in("status", ["CRITICAL_SHORTAGE", "CRITICAL_SURPLUS"])
        .order("station_code").order("source_code")
        .range(from, to)
    ),
    getCurrentUserPermissions(),
    getCurrentUserId(),
  ]);
  const sources = await fetchAlertSources(supabase, perms);
  const failed = [inv, sources.exceptions, sources.overdue, sources.adjustments].some((r) => r.error);
  const alerts = buildAlerts({ invRows: (inv.data ?? []) as any, sources, perms, userId });

  return (
    <div className="mx-auto w-full max-w-5xl px-3 py-6 sm:px-6">
      <Link href="/dashboard" className="mb-4 inline-block text-sm text-(--color-primary) hover:underline">Back to dashboard</Link>
      <h1 className="mb-1 text-2xl font-semibold text-(--color-text)">Action Required</h1>
      <p className="mb-6 text-sm text-(--color-text-muted)">
        Most serious first, then by age. Each condition appears once. You see only the stations and actions you are permitted to.
      </p>
      {failed && <div className="alert alert-warning mb-4" role="alert">Some alerts could not be loaded. Refresh the page to try again.</div>}
      <AlertList alerts={alerts} />
    </div>
  );
}
