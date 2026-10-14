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
    <div className="panel p-4 sm:p-5">
      <h2 className="mb-3 text-base font-semibold text-(--color-text)">Actions</h2>
      {error && <div className="mb-3 alert alert-danger">{error}</div>}

      {!isLoss && (
        <>
          {report.status === "REPORTED" && has("report_damage") && (
            <button disabled={pending} onClick={() => run(() => startDamageReviewAction(report.id))}
              className="btn-primary min-h-11 px-5 text-sm">
              Start Review
            </button>
          )}

          {report.status === "UNDER_REVIEW" && has("report_damage") && (
            <div className="space-y-3">
              <textarea value={notes} onChange={(e) => setNotes(e.target.value)} rows={2}
                placeholder="Assessment notes..."
                className="min-h-11 w-full px-3 py-2 text-sm" />
              <div className="flex gap-2">
                <button disabled={pending} onClick={() => run(() => assessDamageAction(report.id, "REPAIRABLE", notes))}
                  className="btn-primary min-h-11 px-5 text-sm">
                  Assess: Repairable
                </button>
                <button disabled={pending} onClick={() => run(() => assessDamageAction(report.id, "RETIRE", notes))}
                  className="btn-secondary min-h-11 px-5 text-sm">
                  Assess: Retire
                </button>
              </div>
            </div>
          )}

          {report.status === "ASSESSED" && report.assessment_outcome === "REPAIRABLE" && has("report_damage") && (
            <button disabled={pending} onClick={() => run(() => startRepairAction(report.id))}
              className="btn-primary min-h-11 px-5 text-sm">
              Start Repair
            </button>
          )}

          {report.status === "REPAIR" && has("report_damage") && (
            <button disabled={pending} onClick={() => run(() => returnToServiceAction(report.id))}
              className="btn-primary min-h-11 px-5 text-sm">
              Return to Service
            </button>
          )}

          {report.status === "ASSESSED" && report.assessment_outcome === "RETIRE" && has("report_damage") && (
            <button disabled={pending} onClick={() => run(() => retireEquipmentAction(report.id))}
              className="btn-primary min-h-11 px-5 text-sm">
              Retire Equipment
            </button>
          )}

          {report.status === "RETIRED" && has("manage_catalogue") && (
            <button disabled={pending} onClick={() => run(() => disposeEquipmentAction(report.id))}
              className="btn-danger min-h-11 px-5 text-sm">
              Dispose (Permanent Write-off)
            </button>
          )}

          {["RETURNED_TO_SERVICE", "DISPOSED"].includes(report.status) && (
            <p className="text-sm text-(--color-text-subtle)">This report is finalized.</p>
          )}
        </>
      )}

      {isLoss && (
        <>
          {report.status === "REPORTED" && has("confirm_loss") && (
            <button disabled={pending} onClick={() => run(() => startLossInvestigationAction(report.id))}
              className="btn-primary min-h-11 px-5 text-sm">
              Start Investigation
            </button>
          )}

          {report.status === "INVESTIGATION" && has("confirm_loss") && (
            <div className="space-y-3">
              <textarea value={notes} onChange={(e) => setNotes(e.target.value)} rows={2}
                placeholder="Investigation findings / resolution notes..."
                className="min-h-11 w-full px-3 py-2 text-sm" />
              <div className="flex gap-2">
                <button disabled={pending} onClick={() => run(() => recoverLossAction(report.id, notes))}
                  className="btn-primary min-h-11 px-5 text-sm">
                  Mark Recovered
                </button>
                <button disabled={pending || notes.trim().length === 0}
                  onClick={() => run(() => confirmLossAction(report.id, notes))}
                  className="btn-danger min-h-11 px-5 text-sm">
                  Confirm Loss (requires notes)
                </button>
              </div>
            </div>
          )}

          {report.status === "CONFIRMED_LOSS" && has("confirm_loss") && (
            <button disabled={pending} onClick={() => run(() => closeLossReportAction(report.id))}
              className="btn-primary min-h-11 px-5 text-sm">
              Close Report
            </button>
          )}

          {["RECOVERED", "CLOSED"].includes(report.status) && (
            <p className="text-sm text-(--color-text-subtle)">This report is finalized.</p>
          )}
        </>
      )}
    </div>
  );
}
