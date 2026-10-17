"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { MovementForm } from "./MovementForm";
import { closeExchangeAction, decideNoReturnAction, requestNoReturnAction, startReturnAction } from "./actions";
import type { ExchangeRow } from "./status";

type Dialog = null | "close" | "request" | "approve" | "reject";

export function ExchangePanel({ ex, perms, userId }: { ex: ExchangeRow; perms: string[]; userId: string | null }) {
  const router = useRouter();
  const has = (p: string) => perms.includes(p);
  const [dialog, setDialog] = useState<Dialog>(null);
  const [showReturn, setShowReturn] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const open = ex.status !== "CLOSED" && ex.status !== "CLOSED_NO_RETURN" && ex.status !== "CANCELLED";
  const outboundReceived = ["RECEIVED", "DISCREPANCY", "RECONCILIATION", "CLOSED"].includes(ex.outbound_status ?? "");
  const canStartReturn = open && has("create_transfer") && outboundReceived && !ex.return_id && !ex.no_return_pending && ex.return_required;
  const canClose = open && has("reconcile_transfer") && ex.status === "READY_TO_CLOSE";
  const canRequestNoReturn = open && has("create_transfer") && ex.status === "AWAITING_RETURN" && !ex.no_return_pending;
  const canDecide = open && has("approve_transfer") && ex.no_return_pending;
  const iRequested = ex.no_return_requested_by !== null && ex.no_return_requested_by === userId;

  function run(fn: () => Promise<{ success: boolean; error?: string }>) {
    setError(null);
    startTransition(async () => {
      const r = await fn();
      if (!r.success) return setError(r.error ?? "That did not work.");
      setDialog(null);
      router.refresh();
    });
  }

  if (!open && !showReturn) return null;

  return (
    <div className="space-y-4">
      {error && <p role="alert" className="alert alert-danger">{error}</p>}

      {ex.no_return_pending && (
        <div className="alert alert-warning">
          <span className="font-medium">Request to close without a return: </span>{ex.no_return_reason}
          {iRequested && <span className="block text-xs">You made this request, so someone else must decide it.</span>}
        </div>
      )}
      {ex.no_return_decision === "REJECTED" && !ex.no_return_pending && (
        <div className="alert alert-warning"><span className="font-medium">Closure without a return was declined: </span>{ex.no_return_decision_note}</div>
      )}

      <div className="flex flex-wrap gap-3">
        {canStartReturn && !showReturn && <button className="btn-primary min-h-11 px-4 text-sm" onClick={() => setShowReturn(true)}>Record return movement</button>}
        {canClose && <button className="btn-primary min-h-11 px-4 text-sm" onClick={() => setDialog("close")}>Close exchange</button>}
        {canRequestNoReturn && <button className="btn-secondary min-h-11 px-4 text-sm" onClick={() => setDialog("request")}>Request closure without a return</button>}
        {canDecide && !iRequested && (
          <>
            <button className="btn-primary min-h-11 px-4 text-sm" onClick={() => setDialog("approve")}>Approve closure without a return</button>
            <button className="btn-secondary min-h-11 px-4 text-sm" onClick={() => setDialog("reject")}>Decline</button>
          </>
        )}
      </div>

      {showReturn && canStartReturn && (
        <div>
          <h2 className="mb-3 text-lg font-semibold text-(--color-text)">Return movement to {ex.hub_code}</h2>
          <p className="mb-3 text-sm text-(--color-text-muted)">Record what the outstation is actually sending back. It does not have to match what was received.</p>
          <MovementForm
            mode="return"
            fromStationId={ex.outstation_id}
            fromCode={ex.outstation_code}
            fixedToStationId={ex.hub_station_id}
            fixedToCode={ex.hub_code}
            outboundTransferId={ex.outbound_id}
            submitLabel="Record return"
            onCancel={() => setShowReturn(false)}
            onSubmit={async (v) => {
              const r = await startReturnAction({ exchangeId: ex.id, items: v.items, reason: v.reason, priority: v.priority, flightNumber: v.flightNumber, flightDate: v.flightDate });
              if (!r.success) return r.error;
              setShowReturn(false);
              router.refresh();
              return null;
            }}
          />
        </div>
      )}

      <ConfirmDialog open={dialog === "close"} pending={pending} title="Close this exchange?"
        description="Both movements are closed and reconciled. Closing the exchange completes the case."
        reasonLabel="Closing note (optional)" optionalReason confirmLabel="Close exchange"
        onCancel={() => setDialog(null)} onConfirm={(note) => run(() => closeExchangeAction(ex.id, note))} />
      <ConfirmDialog open={dialog === "request"} pending={pending} danger title="Request closure without a return?"
        description="Use this only when no equipment is coming back. A different authorised person must approve it before the exchange closes."
        reasonLabel="Why is no return needed?" confirmLabel="Send request"
        onCancel={() => setDialog(null)} onConfirm={(reason) => run(() => requestNoReturnAction(ex.id, reason))} />
      <ConfirmDialog open={dialog === "approve"} pending={pending} danger title="Approve closure without a return?"
        description="The exchange will close with no return movement. This is recorded in the audit log."
        reasonLabel="Decision note" confirmLabel="Approve and close"
        onCancel={() => setDialog(null)} onConfirm={(note) => run(() => decideNoReturnAction(ex.id, true, note))} />
      <ConfirmDialog open={dialog === "reject"} pending={pending} title="Decline this request?"
        description="The exchange stays open and a return can be recorded."
        reasonLabel="Decision note" confirmLabel="Decline request"
        onCancel={() => setDialog(null)} onConfirm={(note) => run(() => decideNoReturnAction(ex.id, false, note))} />
    </div>
  );
}
