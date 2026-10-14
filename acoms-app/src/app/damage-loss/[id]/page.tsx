import { createClient } from "@/lib/supabase/server";
import { getCurrentUserPermissions } from "@/features/auth/permissions";
import { DamageLossActionPanel } from "./DamageLossActionPanel";

export default async function DamageLossDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ type?: string }>;
}) {
  const { id } = await params;
  const { type } = await searchParams;
  const isLoss = type === "loss";
  const supabase = await createClient();
  const permissions = await getCurrentUserPermissions();

  const table = isLoss ? "loss_reports" : "damage_reports";
  const { data: report, error } = await supabase
    .from(table)
    .select("*, station:station_id(code, name), equipment_type:equipment_type_id(source_code, name)")
    .eq("id", id)
    .single();

  if (error || !report) {
    return (
      <div className="mx-auto max-w-2xl px-4 py-8">
        <p className="alert alert-danger">
          {error?.message ?? "Report not found."}
        </p>
      </div>
    );
  }

  const r = report as any;

  return (
    <div className="mx-auto max-w-2xl px-4 py-8">
      <div className="mb-6">
        <h1 className="text-2xl font-semibold text-(--color-text)">
          {isLoss ? "Loss" : "Damage"} Report — {r.equipment_type?.source_code}
        </h1>
        <p className="text-sm text-(--color-text-subtle)">
          {r.equipment_type?.name} · {r.station?.code} ({r.station?.name}) · Qty {r.quantity}
        </p>
      </div>

      <div className="mb-4 rounded-lg bg-(--color-surface-subtle) px-4 py-3 text-sm text-(--color-text-muted)">
        <span className="font-medium">{isLoss ? "Circumstances" : "Reason"}: </span>
        {isLoss ? r.circumstances : r.reason}
      </div>

      <div className="mb-6 panel p-4 text-sm">
        <div className="flex justify-between border-b border-(--color-border) py-2">
          <span className="text-(--color-text-subtle)">Status</span>
          <span className="font-medium text-(--color-text)">{r.status.replace(/_/g, " ")}</span>
        </div>
        {r.assessment_outcome && (
          <div className="flex justify-between border-b border-(--color-border) py-2">
            <span className="text-(--color-text-subtle)">Assessment Outcome</span>
            <span className="font-medium text-(--color-text)">{r.assessment_outcome}</span>
          </div>
        )}
        {(r.resolution_notes || r.assessment_notes) && (
          <div className="py-2">
            <span className="text-(--color-text-subtle)">Notes</span>
            <p className="mt-1 text-(--color-text-muted)">{r.resolution_notes || r.assessment_notes}</p>
          </div>
        )}
      </div>

      <DamageLossActionPanel report={r} isLoss={isLoss} permissions={Array.from(permissions)} />
    </div>
  );
}
