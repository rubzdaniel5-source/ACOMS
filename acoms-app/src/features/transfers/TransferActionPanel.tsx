"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import type { EquipmentTransfer, EquipmentTransferItem } from "@/types/transfers";
import {
  approveTransferAction,
  rejectTransferAction,
  cancelTransferAction,
  dispatchTransferAction,
  receiveTransferAction,
  reconcileTransferAction,
  closeTransferAction,
  resolveDiscrepancyAction,
  approveBelowMinimumAction,
} from "./actions";

interface Props {
  transfer: EquipmentTransfer;
  items: EquipmentTransferItem[];
  permissions: string[];
  currentUserId: string | null;
  /** Convenience only; the database still decides. Hides actions that belong to the other station. */
  atSource: boolean;
  atDestination: boolean;
  openExcess: boolean;
  belowMin: { item_id: string; equipment_name: string; available: number; dispatching: number; minimum_level: number }[];
  canApproveBelowMin: boolean;
}

/**
 * Shows only the actions that make sense for the current status + the
 * user's permissions. This is a UX convenience, NOT the authorization
 * boundary — every action still re-checks capability, station access, and
 * (for approval) the requester != approver rule inside the SQL function
 * itself. A user could bypass this panel entirely and the database would
 * still refuse an invalid action.
 */
export function TransferActionPanel({ transfer, items, permissions, currentUserId, atSource, atDestination, openExcess, belowMin, canApproveBelowMin }: Props) {
  const router = useRouter();
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [quantities, setQuantities] = useState<Record<string, number>>({});
  const [damaged, setDamaged] = useState<Record<string, number>>({});
  const [missing, setMissing] = useState<Record<string, number>>({});
  const [reasonText, setReasonText] = useState("");
  const [minReason, setMinReason] = useState("");
  const [counted, setCounted] = useState<Record<string, string>>({});
  const [damagedCount, setDamagedCount] = useState<Record<string, string>>({});
  const [finalReceipt, setFinalReceipt] = useState(true);
  const [receiptNotes, setReceiptNotes] = useState("");
  // One themed confirmation for every consequential action. `go` runs only after the user confirms.
  const [dialog, setDialog] = useState<null | {
    title: string; description?: string; confirmLabel: string; danger?: boolean; reasonLabel?: string;
    go: (reason: string) => Promise<unknown>;
  }>(null);

  const has = (p: string) => permissions.includes(p);
  const isOwnRequest = currentUserId === transfer.requested_by;
  // The database decides who may cancel; this only decides whether to show the button.
  const canCancel =
    (transfer.status === "REQUESTED" && (isOwnRequest || has("approve_transfer"))) ||
    (transfer.status === "APPROVED" && has("approve_transfer"));

  function qty(id: string, fallback: number) {
    return quantities[id] ?? fallback;
  }

  async function run<T extends { success: boolean; error?: string }>(fn: () => Promise<T>) {
    setPending(true);
    setError(null);
    const result = await fn();
    setPending(false);
    if (!result.success) {
      setError(result.error ?? "Action failed.");
      return false;
    }
    router.refresh();
    return true;
  }

  async function confirmed(reason: string) {
    const d = dialog;
    if (!d) return;
    await d.go(reason);
    setDialog(null);
  }

  return (
    <div className="panel p-4 sm:p-5">
      <ConfirmDialog
        open={dialog !== null}
        title={dialog?.title ?? ""}
        description={dialog?.description}
        confirmLabel={dialog?.confirmLabel ?? "Confirm"}
        danger={dialog?.danger}
        reasonLabel={dialog?.reasonLabel}
        pending={pending}
        onConfirm={confirmed}
        onCancel={() => setDialog(null)}
      />
      <h2 className="mb-3 text-base font-semibold text-(--color-text)">Actions</h2>

      {error && (
        <div className="mb-3 alert alert-danger">{error}</div>
      )}

      {canCancel && (
        <div className="mb-4 flex flex-wrap items-center gap-3 border-b border-(--color-border) pb-4">
          <button
            disabled={pending}
            onClick={() =>
              setDialog({
                title: "Cancel this transfer?",
                description: transfer.status === "APPROVED"
                  ? "Nothing has left the source station yet, so no stock changes. The transfer cannot be reopened."
                  : "No stock changes. The request cannot be reopened; raise a new one if it is needed later.",
                confirmLabel: "Cancel transfer",
                danger: true,
                reasonLabel: "Reason for cancelling",
                go: (reason) => run(() => cancelTransferAction(transfer.id, reason)),
              })
            }
            className="btn-secondary min-h-11 px-5 text-sm"
          >
            Cancel transfer
          </button>
          <span className="text-xs text-(--color-text-muted)">
            {transfer.status === "APPROVED" ? "Possible until it is dispatched." : "Possible until it is approved."}
          </span>
        </div>
      )}

      {transfer.status === "REQUESTED" && (
        <div className="space-y-3">
          {isOwnRequest && has("approve_transfer") && (
            <p className="text-xs text-(--color-warning)">
              You requested this transfer — per policy you cannot approve your own request (ADR-007).
              Another approver needs to action this.
            </p>
          )}
          {has("approve_transfer") && !isOwnRequest && (
            <div className="flex gap-2">
              <button
                disabled={pending}
                onClick={() =>
                  run(() =>
                    approveTransferAction(
                      transfer.id,
                      items.map((it) => ({
                        item_id: it.id,
                        quantity_approved: qty(it.id, it.quantity_requested),
                      }))
                    )
                  )
                }
                className="btn-primary min-h-11 px-5 text-sm"
              >
                Approve
              </button>
              <button
                disabled={pending}
                onClick={() =>
                  setDialog({
                    title: "Reject this transfer?",
                    description: "The requester will see the reason. A rejected transfer cannot be reopened.",
                    confirmLabel: "Reject transfer",
                    danger: true,
                    reasonLabel: "Reason for rejection",
                    go: (reason) => run(() => rejectTransferAction(transfer.id, reason)),
                  })
                }
                className="btn-secondary min-h-11 px-5 text-sm"
              >
                Reject
              </button>
            </div>
          )}
        </div>
      )}

      {transfer.status === "APPROVED" && has("dispatch_transfer") && atSource && (
        <div className="space-y-3">
          {belowMin.length > 0 && !transfer.below_min_approved_by && (
            <div className="alert alert-warning space-y-2 text-sm">
              <p className="font-medium">This dispatch leaves {transfer.from_station?.code ?? "the source"} below its minimum level.</p>
              <ul className="list-disc pl-5">
                {belowMin.map((b) => (
                  <li key={b.item_id}>{b.equipment_name}: {b.available} in stock, sending {b.dispatching}, minimum {b.minimum_level}</li>
                ))}
              </ul>
              {canApproveBelowMin ? (
                <div className="space-y-2">
                  <label className="block text-xs" htmlFor="min-reason">Reason for dispatching below the minimum (required)</label>
                  <textarea id="min-reason" value={minReason} onChange={(e) => setMinReason(e.target.value)} rows={2}
                    placeholder="Why is this dispatch needed even though stock will be low?" className="id-code w-full px-2 py-1" />
                  <button disabled={pending || minReason.trim().length < 10} className="btn-primary min-h-11 px-4 text-sm"
                    onClick={() => run(() => approveBelowMinimumAction(transfer.id, minReason.trim()))}>
                    Approve dispatch below minimum
                  </button>
                </div>
              ) : (
                <p>A catering supervisor or catering manager must approve it, with a reason, before you can dispatch. You can also lower the quantities.</p>
              )}
            </div>
          )}
          {transfer.below_min_approved_by && (
            <p className="alert alert-info text-sm">Dispatch below the minimum level was approved. Reason: {transfer.below_min_reason}</p>
          )}
          <p className="text-xs text-(--color-text-subtle)">Confirm actual dispatched quantities:</p>
          {items.map((it) => (
            <div key={it.id} className="flex items-center justify-between gap-3 text-sm">
              <span>{it.equipment_type?.source_code} — {it.equipment_type?.name}</span>
              <input
                type="number"
                min={0}
                defaultValue={it.quantity_approved ?? it.quantity_requested}
                onChange={(e) => setQuantities((q) => ({ ...q, [it.id]: parseInt(e.target.value, 10) || 0 }))}
                className="id-code min-h-11 w-24 px-2 py-1"
              />
            </div>
          ))}
          <button
            disabled={pending}
            onClick={() =>
              setDialog({
                title: "Dispatch this transfer?",
                description: "Stock leaves the source station and is shown as in transit. Check the quantities first.",
                confirmLabel: "Dispatch",
                go: () =>
              run(() =>
                dispatchTransferAction(
                  transfer.id,
                  items.map((it) => ({
                    item_id: it.id,
                    quantity_dispatched: qty(it.id, it.quantity_approved ?? it.quantity_requested),
                  }))
                )
              ),
              })
            }
            className="btn-primary min-h-11 px-5 text-sm"
          >
            Confirm Dispatch
          </button>
        </div>
      )}

      {(transfer.status === "IN_TRANSIT" || transfer.status === "PARTIALLY_RECEIVED") && has("receive_transfer") && atDestination && (
        <div className="space-y-3">
          <p className="text-xs text-(--color-text-subtle)">
            Count what is physically in front of you. Leave nothing pre-filled: enter the units you counted and,
            separately, how many of those are damaged. Units beyond what was sent are held for investigation, not added to stock.
          </p>
          {items.map((it) => {
            const done = (it.quantity_received ?? 0) + (it.quantity_damaged_on_receipt ?? 0);
            return (
              <div key={it.id} className="grid grid-cols-[1fr_6rem_6rem] items-end gap-2 text-sm">
                <div>
                  <div>{it.equipment_type?.source_code} — {it.equipment_type?.name}</div>
                  {done > 0 && <div className="text-xs text-(--color-text-subtle)">Already counted: {done}</div>}
                </div>
                <div>
                  <label className="text-xs text-(--color-text-subtle)">Counted</label>
                  <input type="number" min={0} inputMode="numeric" value={counted[it.id] ?? ""}
                    onChange={(e) => setCounted((c) => ({ ...c, [it.id]: e.target.value }))}
                    className="id-code min-h-11 w-full px-2 py-1" />
                </div>
                <div>
                  <label className="text-xs text-(--color-text-subtle)">Damaged</label>
                  <input type="number" min={0} inputMode="numeric" value={damagedCount[it.id] ?? ""}
                    onChange={(e) => setDamagedCount((c) => ({ ...c, [it.id]: e.target.value }))}
                    className="id-code min-h-11 w-full px-2 py-1" />
                </div>
              </div>
            );
          })}
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={finalReceipt} onChange={(e) => setFinalReceipt(e.target.checked)} />
            This is the final receipt (nothing more is still to arrive)
          </label>
          {!finalReceipt && (
            <p className="text-xs text-(--color-text-subtle)">
              Only items you have entered are recorded. The transfer stays open until a final receipt is made.
            </p>
          )}
          <textarea value={receiptNotes} onChange={(e) => setReceiptNotes(e.target.value)} rows={2}
            placeholder="Notes (optional)" className="id-code w-full px-2 py-1 text-sm" />
          <button
            disabled={pending}
            onClick={() => {
              const lines = items
                .filter((it) => (counted[it.id] ?? "") !== "")
                .map((it) => ({
                  item_id: it.id,
                  quantity_counted: parseInt(counted[it.id], 10) || 0,
                  quantity_damaged: parseInt(damagedCount[it.id] ?? "", 10) || 0,
                }));
              if (finalReceipt && lines.length < items.filter((it) => !((it.quantity_received ?? 0) + (it.quantity_damaged_on_receipt ?? 0) > 0)).length) {
                setError("Enter the counted quantity for every item, even if it is 0.");
                return;
              }
              if (lines.length === 0) { setError("Enter the counted quantity for at least one item."); return; }
              run(() => receiveTransferAction(transfer.id, lines, finalReceipt, receiptNotes)).then((ok) => {
                if (ok) { setCounted({}); setDamagedCount({}); setReceiptNotes(""); }
              });
            }}
            className="btn-primary min-h-11 px-5 text-sm"
          >
            {finalReceipt ? "Confirm final receipt" : "Save partial receipt"}
          </button>
        </div>
      )}

      {transfer.status === "RECEIVED" && has("reconcile_transfer") && (
        <div className="space-y-3">
          <p className="text-xs text-(--color-text-subtle)">
            Record any damaged or missing quantities. Differences beyond each item&apos;s tolerance
            will open a discrepancy that must be investigated before closing.
          </p>
          {items.map((it) => (
            <div key={it.id} className="grid grid-cols-3 gap-2 text-sm">
              <span className="col-span-1 self-center">
                {it.equipment_type?.source_code}
                <span className="block text-xs text-(--color-text-subtle)">
                  Short {it.quantity_short ?? 0}; damaged on receipt {it.quantity_damaged_on_receipt ?? 0} (already recorded)
                </span>
              </span>
              <div>
                <label className="text-xs text-(--color-text-subtle)">Damaged</label>
                <input
                  type="number"
                  min={0}
                  defaultValue={0}
                  onChange={(e) => setDamaged((d) => ({ ...d, [it.id]: parseInt(e.target.value, 10) || 0 }))}
                  className="id-code min-h-11 w-full px-2 py-1"
                />
              </div>
              <div>
                <label className="text-xs text-(--color-text-subtle)">Missing</label>
                <input
                  type="number"
                  min={0}
                  defaultValue={0}
                  onChange={(e) => setMissing((m) => ({ ...m, [it.id]: parseInt(e.target.value, 10) || 0 }))}
                  className="id-code min-h-11 w-full px-2 py-1"
                />
              </div>
            </div>
          ))}
          <button
            disabled={pending}
            onClick={() =>
              setDialog({
                title: "Reconcile this transfer?",
                description: "Damaged and missing quantities are recorded against the transfer. Differences beyond tolerance open a discrepancy.",
                confirmLabel: "Reconcile",
                go: () =>
              run(() =>
                reconcileTransferAction(
                  transfer.id,
                  items.map((it) => ({
                    item_id: it.id,
                    quantity_damaged: damaged[it.id] ?? 0,
                    quantity_missing: missing[it.id] ?? 0,
                  }))
                )
              ),
              })
            }
            className="btn-primary min-h-11 px-5 text-sm"
          >
            Reconcile
          </button>
        </div>
      )}

      {transfer.status === "RECONCILIATION" && has("reconcile_transfer") && (
        <button
          disabled={pending}
          onClick={() =>
            setDialog({
              title: "Close this transfer?",
              description: "A closed transfer is final. Make sure reconciliation is complete.",
              confirmLabel: "Close transfer",
              go: () => run(() => closeTransferAction(transfer.id)),
            })
          }
          className="btn-primary min-h-11 px-5 text-sm"
        >
          Close Transfer
        </button>
      )}

      {transfer.status === "DISCREPANCY" && has("reconcile_transfer") && (
        <div className="space-y-3">
          <p className="text-xs text-(--color-danger)">
            {openExcess
              ? "Excess units counted at receipt are still held. Investigate and authorise them (above) before this can be resolved."
              : "This transfer has an unexplained discrepancy beyond tolerance. It cannot be closed until resolved with a documented reason."}
          </p>
          <textarea
            value={reasonText}
            onChange={(e) => setReasonText(e.target.value)}
            rows={2}
            placeholder="Explain the investigation outcome..."
            className="min-h-11 w-full px-3 py-2 text-sm"
          />
          <button
            disabled={pending || openExcess || reasonText.trim().length === 0}
            onClick={() => run(() => resolveDiscrepancyAction(transfer.id, reasonText))}
            className="btn-primary min-h-11 px-5 text-sm"
          >
            Resolve Discrepancy
          </button>
        </div>
      )}

      {["CLOSED", "REJECTED", "CANCELLED"].includes(transfer.status) && (
        <p className="text-sm text-(--color-text-subtle)">This transfer is finalized. No further action available.</p>
      )}
    </div>
  );
}
