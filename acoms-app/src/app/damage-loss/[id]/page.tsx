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
        <p className="rounded-md bg-red-50 px-4 py-3 text-sm text-red-700">
          {error?.message ?? "Report not found."}
        </p>
      </div>
    );
  }

  const r = report as any;

  return (
    <div className="mx-auto max-w-2xl px-4 py-8">
      <div className="mb-6">
        <h1 className="text-xl font-semibold text-slate-900">
          {isLoss ? "Loss" : "Damage"} Report — {r.equipment_type?.source_code}
        </h1>
        <p className="text-sm text-slate-500">
          {r.equipment_type?.name} · {r.station?.code} ({r.station?.name}) · Qty {r.quantity}
        </p>
      </div>

      <div className="mb-4 rounded-md bg-slate-50 px-4 py-3 text-sm text-slate-700">
        <span className="font-medium">{isLoss ? "Circumstances" : "Reason"}: </span>
        {isLoss ? r.circumstances : r.reason}
      </div>

      <div className="mb-6 rounded-lg border border-slate-200 p-4 text-sm">
        <div className="flex justify-between border-b border-slate-100 py-2">
          <span className="text-slate-500">Status</span>
          <span className="font-medium text-slate-900">{r.status.replace(/_/g, " ")}</span>
        </div>
        {r.assessment_outcome && (
          <div className="flex justify-between border-b border-slate-100 py-2">
            <span className="text-slate-500">Assessment Outcome</span>
            <span className="font-medium text-slate-900">{r.assessment_outcome}</span>
          </div>
        )}
        {(r.resolution_notes || r.assessment_notes) && (
          <div className="py-2">
            <span className="text-slate-500">Notes</span>
            <p className="mt-1 text-slate-700">{r.resolution_notes || r.assessment_notes}</p>
          </div>
        )}
      </div>

      <DamageLossActionPanel report={r} isLoss={isLoss} permissions={Array.from(permissions)} />
    </div>
  );
}
