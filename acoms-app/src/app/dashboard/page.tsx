import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { ControlCard } from "@/components/ui/ControlCard";

export default async function DashboardPage() {
  const supabase = await createClient();

  const [overview, health, movement, lossDamage, reconciliation, exceptions, criticalStock] = await Promise.all([
    supabase.from("v_equipment_overview").select("*").single(),
    supabase.from("v_inventory_health").select("status"),
    supabase.from("v_movement_funnel").select("*").single(),
    supabase.from("v_loss_damage_summary").select("*").single(),
    supabase.from("v_reconciliation_summary").select("*").single(),
    supabase.from("v_unresolved_exceptions").select("*").order("updated_at", { ascending: false }).limit(10),
    supabase
      .from("v_inventory_health")
      .select("station_id, station_code, source_code, equipment_name, current_stock, minimum_level, status")
      .in("status", ["CRITICAL_SHORTAGE", "CRITICAL_SURPLUS"]),
  ]);

  const healthCounts = (health.data ?? []).reduce<Record<string, number>>((acc, r: any) => {
    acc[r.status] = (acc[r.status] ?? 0) + 1;
    return acc;
  }, {});

  const o = overview.data as any;
  const m = movement.data as any;
  const ld = lossDamage.data as any;
  const rc = reconciliation.data as any;

  return (
    <div className="mx-auto w-full max-w-7xl px-3 py-6 sm:px-6">
      <div className="mb-6">
        <h1 className="text-2xl font-semibold text-(--color-text)">Equipment Control Dashboard</h1>
        <p className="text-sm text-(--color-text-muted)">Operational control centre — what needs your attention, and where.</p>
      </div>

      <div className="grid grid-cols-1 gap-3 min-[360px]:grid-cols-2 sm:gap-4 lg:grid-cols-3">
        <ControlCard
          title="Equipment Overview"
          icon="boxes"
          href="/dashboard/equipment-overview"
          headline={{ value: o?.grand_total ?? 0, label: "Total Equipment" }}
          stats={[
            { label: "Available", value: o?.total_available ?? 0 },
            { label: "In Transit", value: o?.total_in_transit ?? 0, tone: o?.total_in_transit > 0 ? "amber" : "default" },
            { label: "Damaged", value: o?.total_damaged ?? 0, tone: o?.total_damaged > 0 ? "amber" : "default" },
            { label: "Missing", value: o?.total_missing ?? 0, tone: o?.total_missing > 0 ? "brick" : "default" },
          ]}
        />

        <ControlCard
          title="Inventory Health"
          icon="gauge"
          href="/dashboard/inventory-health"
          headline={
            (healthCounts["CRITICAL_SHORTAGE"] ?? 0) > 0
              ? { value: healthCounts["CRITICAL_SHORTAGE"], label: "Critical Shortages" }
              : { value: healthCounts["NORMAL"] ?? 0, label: "Items at Normal Stock" }
          }
          stats={[
            { label: "Shortages", value: healthCounts["SHORTAGE"] ?? 0, tone: "amber" },
            { label: "Normal", value: healthCounts["NORMAL"] ?? 0, tone: "teal" },
            { label: "Surplus", value: healthCounts["SURPLUS"] ?? 0 },
            { label: "Critical Surplus", value: healthCounts["CRITICAL_SURPLUS"] ?? 0, tone: "brick" },
          ]}
        />

        <ControlCard
          title="Equipment Movement & Exchange"
          icon="swap"
          href="/dashboard/movement"
          headline={{ value: m?.total_requiring_action ?? 0, label: "Transfers Requiring Action" }}
          stats={[
            { label: "Awaiting Approval", value: m?.awaiting_approval ?? 0, tone: "amber" },
            { label: "Awaiting Dispatch", value: m?.awaiting_dispatch ?? 0 },
            { label: "In Transit", value: m?.in_transit ?? 0 },
            { label: "Disputed", value: m?.disputed ?? 0, tone: "brick" },
          ]}
        />

        <ControlCard
          title="Loss & Damage Control"
          icon="alert"
          href="/dashboard/loss-damage"
          headline={{ value: ld?.open_exceptions_total ?? 0, label: "Open Exceptions" }}
          stats={[
            { label: "Missing Equipment", value: ld?.missing_open_count ?? 0, tone: "brick" },
            { label: "Damaged Equipment", value: ld?.damaged_open_count ?? 0, tone: "amber" },
            { label: "Under Investigation", value: ld?.under_investigation ?? 0 },
            { label: "Confirmed Losses", value: ld?.confirmed_losses ?? 0 },
          ]}
        />

        <ControlCard
          title="Reconciliation Control"
          icon="check"
          href="/dashboard/reconciliation"
          headline={{ value: rc?.awaiting_reconciliation ?? 0, label: "Awaiting Reconciliation" }}
          stats={[
            { label: "Reconciled (Pending Close)", value: rc?.reconciled_pending_close ?? 0 },
            { label: "Discrepancies", value: rc?.discrepancies ?? 0, tone: "brick" },
            { label: "Closed (Total)", value: rc?.closed_total ?? 0, tone: "teal" },
          ]}
        />

        <ControlCard
          title="Station Inventory"
          icon="building"
          href="/dashboard/station-inventory"
          headline={{
            value: new Set((criticalStock.data ?? []).map((r: any) => r.station_id)).size,
            label: "Stations Requiring Attention",
          }}
          stats={[{ label: "Critical items", value: criticalStock.data?.length ?? 0, tone: "brick" }]}
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
                <Link href="/transfers/new" className="text-sm inline-flex min-h-11 items-center font-semibold text-(--color-primary) hover:underline">
                  {s.status === "CRITICAL_SHORTAGE" ? "Request Transfer →" : "Redistribute →"}
                </Link>
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
    </div>
  );
}
