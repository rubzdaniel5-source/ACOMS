"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import {
  startDamageReviewAction, assessDamageAction, startRepairAction, returnToServiceAction,
  retireEquipmentAction, disposeEquipmentAction,
  startLossInvestigationAction, recoverLossAction, confirmLossAction, closeLossReportAction,
} from "@/features/damage-loss/actions";

interface Props {
  report: any;
  isLoss: boolean;
  permissions: string[];
}

export function DamageLossActionPanel({ report, isLoss, permissions }: Props) {
  const router = useRouter();
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notes, setNotes] = useState("");

  const has = (p: string) => permissions.includes(p);

  async function run(fn: () => Promise<{ success: boolean; error?: string }>) {
    setPending(true);
    setError(null);
    const result = await fn();
    setPending(false);
    if (!result.success) {
      setError(result.error ?? "Action failed.");
      return;
    }
    router.refresh();
  }

  return (
    <div className="rounded-lg border border-slate-200 p-5">
      <h2 className="mb-3 text-sm font-semibold text-slate-900">Actions</h2>
      {error && <div className="mb-3 rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">{error}</div>}

      {!isLoss && (
        <>
          {report.status === "REPORTED" && has("report_damage") && (
            <button disabled={pending} onClick={() => run(() => startDamageReviewAction(report.id))}
              className="rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-50">
              Start Review
            </button>
          )}

          {report.status === "UNDER_REVIEW" && has("report_damage") && (
            <div className="space-y-3">
              <textarea value={notes} onChange={(e) => setNotes(e.target.value)} rows={2}
                placeholder="Assessment notes..."
                className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm" />
              <div className="flex gap-2">
                <button disabled={pending} onClick={() => run(() => assessDamageAction(report.id, "REPAIRABLE", notes))}
                  className="rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-50">
                  Assess: Repairable
                </button>
                <button disabled={pending} onClick={() => run(() => assessDamageAction(report.id, "RETIRE", notes))}
                  className="rounded-md border border-slate-300 px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50 disabled:opacity-50">
                  Assess: Retire
                </button>
              </div>
            </div>
          )}

          {report.status === "ASSESSED" && report.assessment_outcome === "REPAIRABLE" && has("report_damage") && (
            <button disabled={pending} onClick={() => run(() => startRepairAction(report.id))}
              className="rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-50">
              Start Repair
            </button>
          )}

          {report.status === "REPAIR" && has("report_damage") && (
            <button disabled={pending} onClick={() => run(() => returnToServiceAction(report.id))}
              className="rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-50">
              Return to Service
            </button>
          )}

          {report.status === "ASSESSED" && report.assessment_outcome === "RETIRE" && has("report_damage") && (
            <button disabled={pending} onClick={() => run(() => retireEquipmentAction(report.id))}
              className="rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-50">
              Retire Equipment
            </button>
          )}

          {report.status === "RETIRED" && has("manage_catalogue") && (
            <button disabled={pending} onClick={() => run(() => disposeEquipmentAction(report.id))}
              className="rounded-md bg-red-600 px-4 py-2 text-sm font-medium text-white hover:bg-red-700 disabled:opacity-50">
              Dispose (Permanent Write-off)
            </button>
          )}

          {["RETURNED_TO_SERVICE", "DISPOSED"].includes(report.status) && (
            <p className="text-sm text-slate-500">This report is finalized.</p>
          )}
        </>
      )}

      {isLoss && (
        <>
          {report.status === "REPORTED" && has("confirm_loss") && (
            <button disabled={pending} onClick={() => run(() => startLossInvestigationAction(report.id))}
              className="rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-50">
              Start Investigation
            </button>
          )}

          {report.status === "INVESTIGATION" && has("confirm_loss") && (
            <div className="space-y-3">
              <textarea value={notes} onChange={(e) => setNotes(e.target.value)} rows={2}
                placeholder="Investigation findings / resolution notes..."
                className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm" />
              <div className="flex gap-2">
                <button disabled={pending} onClick={() => run(() => recoverLossAction(report.id, notes))}
                  className="rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-50">
                  Mark Recovered
                </button>
                <button disabled={pending || notes.trim().length === 0}
                  onClick={() => run(() => confirmLossAction(report.id, notes))}
                  className="rounded-md bg-red-600 px-4 py-2 text-sm font-medium text-white hover:bg-red-700 disabled:opacity-50">
                  Confirm Loss (requires notes)
                </button>
              </div>
            </div>
          )}

          {report.status === "CONFIRMED_LOSS" && has("confirm_loss") && (
            <button disabled={pending} onClick={() => run(() => closeLossReportAction(report.id))}
              className="rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-50">
              Close Report
            </button>
          )}

          {["RECOVERED", "CLOSED"].includes(report.status) && (
            <p className="text-sm text-slate-500">This report is finalized.</p>
          )}
        </>
      )}
    </div>
  );
}
