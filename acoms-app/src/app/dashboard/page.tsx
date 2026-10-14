import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { ControlCard } from "@/components/ui/ControlCard";
import { getCurrentUserPermissions } from "@/features/auth/permissions";
import { StationInventoryTable, type InventoryRow } from "./station-inventory/StationInventoryTable";

export default async function DashboardPage() {
  const supabase = await createClient();

  const [overview, inventory, movement, lossDamage, reconciliation, exceptions, perms] = await Promise.all([
    supabase.from("v_equipment_overview").select("*").single(),
    supabase
      .from("v_inventory_health")
      .select("station_id, station_code, station_name, source_code, equipment_name, current_stock, minimum_level, variance, status"),
    supabase.from("v_movement_funnel").select("*").single(),
    supabase.from("v_loss_damage_summary").select("*").single(),
    supabase.from("v_reconciliation_summary").select("*").single(),
    supabase.from("v_unresolved_exceptions").select("*").order("updated_at", { ascending: false }).limit(10),
    getCurrentUserPermissions(),
  ]);

  const invRows = (inventory.data ?? []) as (InventoryRow & { station_id: string })[];
  const health = { data: invRows };
  const criticalStock = {
    data: invRows.filter((r) => r.status === "CRITICAL_SHORTAGE" || r.status === "CRITICAL_SURPLUS"),
  };

  const healthCounts = (health.data ?? []).reduce<Record<string, number>>((acc, r: any) => {
    acc[r.status] = (acc[r.status] ?? 0) + 1;
    return acc;
  }, {});

  // A missing result means the query failed, not that the count is zero (ACOMS-DESIGN-001 s21).
  const val = (row: any, key: string): number | string => (row ? (row[key] ?? 0) : "—");
  const failed = [overview, inventory, movement, lossDamage, reconciliation, exceptions].some((r) => r.error);
  const updatedAt = new Intl.DateTimeFormat("en-GB", {
    day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Kampala",
  }).format(new Date());

  const hc = (k: string): number | string => (inventory.error ? "—" : healthCounts[k] ?? 0);

  const o = overview.data as any;
  const m = movement.data as any;
  const ld = lossDamage.data as any;
  const rc = reconciliation.data as any;

  return (
    <div className="mx-auto w-full max-w-7xl px-3 py-6 sm:px-6">
      <div className="mb-6">
        <h1 className="text-2xl font-semibold text-(--color-text)">Equipment Control Dashboard</h1>
        <p className="text-sm text-(--color-text-muted)">Operational control centre: what needs your attention, and where.</p>
        <p className="mt-1 text-xs text-(--color-text-subtle)">Data loaded {updatedAt} EAT. Refresh the page for the latest figures.</p>
      </div>

      {failed && (
        <div className="alert alert-warning mb-4" role="alert">
          Some figures could not be loaded and show a dash instead of a count. Refresh the page to try again.
        </div>
      )}

      <div className="grid grid-cols-1 gap-3 min-[360px]:grid-cols-2 sm:gap-4 lg:grid-cols-3">
        <ControlCard
          title="Equipment Overview"
          icon="boxes"
          href="/dashboard/equipment-overview"
          headline={{ value: val(o, "grand_total"), label: "Total Equipment" }}
          stats={[
            { label: "Available", value: val(o, "total_available"), href: "/dashboard/equipment-overview?bucket=available" },
            { label: "In Transit", value: val(o, "total_in_transit"), tone: o?.total_in_transit > 0 ? "amber" : "default", href: "/dashboard/equipment-overview?bucket=in_transit" },
            { label: "Damaged", value: val(o, "total_damaged"), tone: o?.total_damaged > 0 ? "amber" : "default", href: "/dashboard/equipment-overview?bucket=damaged" },
            { label: "Missing", value: val(o, "total_missing"), tone: o?.total_missing > 0 ? "brick" : "default", href: "/dashboard/equipment-overview?bucket=missing" },
          ]}
        />

        <ControlCard
          title="Inventory Health"
          icon="gauge"
          href="/dashboard/inventory-health"
          headline={
            Number(hc("CRITICAL_SHORTAGE")) > 0
              ? { value: hc("CRITICAL_SHORTAGE"), label: "Critical Shortages", href: "/dashboard/station-inventory?status=CRITICAL_SHORTAGE" }
              : { value: hc("NORMAL"), label: "Items at Normal Stock" }
          }
          stats={[
            { label: "Shortages", value: hc("SHORTAGE"), tone: "amber", href: "/dashboard/station-inventory?status=SHORTAGE" },
            { label: "Normal", value: hc("NORMAL"), tone: "teal", href: "/dashboard/station-inventory?status=NORMAL" },
            { label: "Surplus", value: hc("SURPLUS"), href: "/dashboard/station-inventory?status=SURPLUS" },
            { label: "Critical Surplus", value: hc("CRITICAL_SURPLUS"), tone: "brick", href: "/dashboard/station-inventory?status=CRITICAL_SURPLUS" },
          ]}
        />

        <ControlCard
          title="Equipment Movement & Exchange"
          icon="swap"
          href="/dashboard/movement"
          headline={{ value: val(m, "total_requiring_action"), label: "Transfers Requiring Action", href: "/transfers?status=open" }}
          stats={[
            { label: "Awaiting Approval", value: val(m, "awaiting_approval"), tone: "amber", href: "/transfers?status=REQUESTED" },
            { label: "Awaiting Dispatch", value: val(m, "awaiting_dispatch"), href: "/transfers?status=APPROVED" },
            { label: "In Transit", value: val(m, "in_transit"), href: "/transfers?status=IN_TRANSIT" },
            { label: "Disputed", value: val(m, "disputed"), tone: "brick", href: "/transfers?status=DISCREPANCY" },
          ]}
        />

        <ControlCard
          title="Loss & Damage Control"
          icon="alert"
          href="/dashboard/loss-damage"
          headline={{ value: val(ld, "open_exceptions_total"), label: "Open Exceptions" }}
          stats={[
            { label: "Missing Equipment", value: val(ld, "missing_open_count"), tone: "brick", href: "/damage-loss?view=missing" },
            { label: "Damaged Equipment", value: val(ld, "damaged_open_count"), tone: "amber", href: "/damage-loss?view=damaged" },
            { label: "Under Investigation", value: val(ld, "under_investigation"), href: "/damage-loss?view=investigation" },
            { label: "Confirmed Losses", value: val(ld, "confirmed_losses"), href: "/damage-loss?view=confirmed" },
          ]}
        />

        <ControlCard
          title="Reconciliation Control"
          icon="check"
          href="/dashboard/reconciliation"
          headline={{ value: val(rc, "awaiting_reconciliation"), label: "Awaiting Reconciliation", href: "/transfers?status=RECEIVED" }}
          stats={[
            { label: "Reconciled (Pending Close)", value: val(rc, "reconciled_pending_close"), href: "/transfers?status=RECONCILIATION" },
            { label: "Discrepancies", value: val(rc, "discrepancies"), tone: "brick", href: "/transfers?status=DISCREPANCY" },
            { label: "Closed (Total)", value: val(rc, "closed_total"), tone: "teal", href: "/transfers?status=CLOSED" },
          ]}
        />

        <ControlCard
          title="Station Inventory"
          icon="building"
          href="/dashboard/station-inventory"
          headline={{
            value: inventory.error ? "—" : new Set(criticalStock.data.map((r) => r.station_id)).size,
            label: "Stations Requiring Attention",
            href: "/dashboard/station-inventory?status=CRITICAL_SHORTAGE,CRITICAL_SURPLUS",
          }}
          stats={[{ label: "Critical items", value: inventory.error ? "—" : criticalStock.data.length, tone: "brick", href: "/dashboard/station-inventory?status=CRITICAL_SHORTAGE,CRITICAL_SURPLUS" }]}
        />
      </div>

      {/* Action Required — persistent, immediately beneath the six cards.
          Combines transfer/damage/loss exceptions AND critical stock levels —
          the Inventory Health card's numbers must never disagree with what
          shows up here as something to act on. */}
      <section className="mt-8">
        <h2 className="mb-3 text-lg font-semibold text-(--color-text)">
          Action Required
        </h2>
        {(exceptions.data && exceptions.data.length > 0) || (criticalStock.data && criticalStock.data.length > 0) ? (
          <div className="panel divide-y divide-(--color-border)">
            {(criticalStock.data ?? []).map((s: any) => (
              <div key={`stock-${s.station_id}-${s.source_code}`} className="flex flex-wrap items-center justify-between gap-2 px-4 py-3 text-sm">
                <span>
                  <span className={`tag mr-2 ${s.status === "CRITICAL_SHORTAGE" ? "tag-brick" : "tag-surplus"}`}>
                    {s.status === "CRITICAL_SHORTAGE" ? "Critical shortage" : "Critical surplus"}
                  </span>
                  {" — "}
                  <span className="id-code text-(--color-text-muted)">{s.station_code}</span>{" "}
                  has {s.current_stock} of <span className="id-code">{s.source_code}</span> {s.equipment_name}
                  {s.minimum_level != null && ` (min ${s.minimum_level})`}
                </span>
                {perms.has("create_transfer") && (
                  <Link href="/transfers/new" className="inline-flex min-h-11 items-center text-sm font-semibold text-(--color-primary) hover:underline">
                    {s.status === "CRITICAL_SHORTAGE" ? "Request transfer" : "Redistribute"}
                  </Link>
                )}
              </div>
            ))}
            {exceptions.data?.map((e: any) => {
              const href =
                e.exception_type === "TRANSFER_DISCREPANCY" ? `/transfers/${e.id}` : `/damage-loss/${e.id}?type=${e.exception_type === "LOSS_PENDING" ? "loss" : "damage"}`;
              return (
                <div key={e.id} className="flex flex-wrap items-center justify-between gap-2 px-4 py-3 text-sm">
                  <span>
                    <span className="tag tag-brick mr-2">{e.exception_type.replace(/_/g, " ").toLowerCase().replace(/^./, (c: string) => c.toUpperCase())}</span>
                    {" — "}
                    <span className="id-code text-(--color-text-muted)">{e.reference}</span>
                  </span>
                  <Link href={href} className="text-sm inline-flex min-h-11 items-center font-semibold text-(--color-primary) hover:underline">
                    View →
                  </Link>
                </div>
              );
            })}
          </div>
        ) : (
          <p className="text-sm text-(--color-text-muted)">No items currently require action.</p>
        )}
      </section>

      <section className="mt-8" aria-labelledby="station-inventory-heading">
        <h2 id="station-inventory-heading" className="mb-1 text-lg font-semibold text-(--color-text)">Station Inventory</h2>
        <p className="mb-3 text-sm text-(--color-text-muted)">
          Worst positions first. <Link href="/dashboard/station-inventory" className="font-semibold text-(--color-primary) hover:underline">Open the full view</Link>
        </p>
        {inventory.error ? (
          <div className="alert alert-danger" role="alert">
            Station inventory could not be loaded. Refresh the page to try again.
          </div>
        ) : (
          <StationInventoryTable
            rows={invRows}
            canRequestTransfer={perms.has("create_transfer")}
            pageSize={10}
            detailsBase="/dashboard/station-inventory"
          />
        )}
      </section>
    </div>
  );
}
