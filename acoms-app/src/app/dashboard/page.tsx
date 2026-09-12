import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { ControlCard } from "@/components/ui/ControlCard";

export default async function DashboardPage() {
  const supabase = await createClient();

  const [overview, health, movement, lossDamage, reconciliation, exceptions] = await Promise.all([
    supabase.from("v_equipment_overview").select("*").single(),
    supabase.from("v_inventory_health").select("status"),
    supabase.from("v_movement_funnel").select("*").single(),
    supabase.from("v_loss_damage_summary").select("*").single(),
    supabase.from("v_reconciliation_summary").select("*").single(),
    supabase.from("v_unresolved_exceptions").select("*").order("updated_at", { ascending: false }).limit(10),
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
    <div className="mx-auto max-w-6xl px-4 py-8">
      <div className="mb-6">
        <h1 className="text-xl font-semibold text-(--navy)">Equipment Control Dashboard</h1>
        <p className="text-sm text-(--steel)">Operational control centre — what needs your attention, and where.</p>
      </div>

      <div className="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-3">
        <ControlCard
          title="Equipment Overview"
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
          href="/dashboard/inventory-health"
          headline={{ value: healthCounts["CRITICAL_SHORTAGE"] ?? 0, label: "Critical Shortages" }}
          stats={[
            { label: "Shortages", value: healthCounts["SHORTAGE"] ?? 0, tone: "amber" },
            { label: "Normal", value: healthCounts["NORMAL"] ?? 0, tone: "teal" },
            { label: "Surplus", value: healthCounts["SURPLUS"] ?? 0 },
            { label: "Critical Surplus", value: healthCounts["CRITICAL_SURPLUS"] ?? 0, tone: "brick" },
          ]}
        />

        <ControlCard
          title="Equipment Movement & Exchange"
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
          href="/dashboard/station-inventory"
          headline={{
            value: Object.entries(healthCounts).filter(([k]) => k === "CRITICAL_SHORTAGE" || k === "CRITICAL_SURPLUS").reduce((s, [, v]) => s + v, 0),
            label: "Stations Requiring Attention",
          }}
          stats={[{ label: "Search & filter all stations", value: "→" }]}
        />
      </div>

      {/* Action Required — persistent, immediately beneath the six cards */}
      <section className="mt-8">
        <h2 className="mb-3 flex items-center gap-2 text-sm font-semibold text-(--brick)">
          ⚠ Action Required
        </h2>
        {exceptions.data && exceptions.data.length > 0 ? (
          <div className="panel divide-y" style={{ borderColor: "var(--border)" }}>
            {exceptions.data.map((e: any) => {
              const href =
                e.exception_type === "TRANSFER_DISCREPANCY" ? `/transfers/${e.id}` : `/damage-loss/${e.id}?type=${e.exception_type === "LOSS_PENDING" ? "loss" : "damage"}`;
              return (
                <div key={e.id} className="flex items-center justify-between px-4 py-3 text-sm">
                  <span>
                    <span className="text-(--brick)">🔴</span>{" "}
                    <span className="font-medium text-(--foreground)">{e.exception_type.replace(/_/g, " ")}</span>
                    {" — "}
                    <span className="id-code text-(--steel)">{e.reference}</span>
                  </span>
                  <Link href={href} className="text-sm font-semibold text-(--navy) hover:underline">
                    View →
                  </Link>
                </div>
              );
            })}
          </div>
        ) : (
          <p className="text-sm text-(--steel)">No items currently require action.</p>
        )}
      </section>
    </div>
  );
}
