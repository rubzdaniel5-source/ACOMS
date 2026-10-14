import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { fetchAll } from "@/lib/supabase/fetchAll";
import { getCurrentUserPermissions } from "@/features/auth/permissions";
import { StationInventoryTable, type InventoryRow } from "./StationInventoryTable";

const ATTENTION = ["CRITICAL_SHORTAGE", "SHORTAGE", "CRITICAL_SURPLUS"];

export default async function StationInventoryPage({
  searchParams,
}: {
  searchParams: Promise<{ station?: string; status?: string; q?: string }>;
}) {
  const sp = await searchParams;
  const supabase = await createClient();
  const [{ data, error }, perms] = await Promise.all([
    fetchAll<any>((from, to) =>
      supabase
        .from("v_inventory_health")
        .select("station_code, station_name, source_code, equipment_name, current_stock, minimum_level, variance, status")
        .order("station_code").order("source_code")
        .range(from, to)
    ),
    getCurrentUserPermissions(),
  ]);

  const statuses = sp.status === "attention" ? ATTENTION : sp.status ? sp.status.split(",") : undefined;

  return (
    <div className="mx-auto w-full max-w-7xl px-3 py-6 sm:px-6">
      <Link href="/dashboard" className="mb-4 inline-block text-sm text-(--color-primary) hover:underline">Back to dashboard</Link>
      <h1 className="mb-1 text-2xl font-semibold text-(--color-text)">Station Inventory</h1>
      <p className="mb-6 text-sm text-(--color-text-muted)">The full station and equipment position. Search and filter to find what needs attention.</p>

      {error ? (
        <div className="alert alert-danger" role="alert">
          Station inventory could not be loaded. Refresh the page to try again.
        </div>
      ) : (
        <StationInventoryTable
          key={JSON.stringify(sp)}
          rows={(data ?? []) as InventoryRow[]}
          canRequestTransfer={perms.has("create_transfer")}
          initial={{ station: sp.station, statuses, q: sp.q }}
          pageSize={25}
          detailsBase="/dashboard/station-inventory"
        />
      )}
    </div>
  );
}
