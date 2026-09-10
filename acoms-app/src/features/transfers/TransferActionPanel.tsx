"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import type { EquipmentTransfer, EquipmentTransferItem } from "@/types/transfers";
import {
  approveTransferAction,
  rejectTransferAction,
  dispatchTransferAction,
  receiveTransferAction,
  reconcileTransferAction,
  closeTransferAction,
  resolveDiscrepancyAction,
} from "./actions";

interface Props {
  transfer: EquipmentTransfer;
  items: EquipmentTransferItem[];
  permissions: string[];
  currentUserId: string | null;
}

/**
 * Shows only the actions that make sense for the current status + the
 * user's permissions. This is a UX convenience, NOT the authorization
 * boundary — every action still re-checks capability, station access, and
 * (for approval) the requester != approver rule inside the SQL function
 * itself. A user could bypass this panel entirely and the database would
 * still refuse an invalid action.
 */
export function TransferActionPanel({ transfer, items, permissions, currentUserId }: Props) {
  const router = useRouter();
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [quantities, setQuantities] = useState<Record<string, number>>({});
  const [damaged, setDamaged] = useState<Record<string, number>>({});
  const [missing, setMissing] = useState<Record<string, number>>({});
  const [reasonText, setReasonText] = useState("");

  const has = (p: string) => permissions.includes(p);
  const isOwnRequest = currentUserId === transfer.requested_by;

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
      return;
    }
    router.refresh();
  }

  return (
    <div className="rounded-lg border border-slate-200 p-5">
      <h2 className="mb-3 text-sm font-semibold text-slate-900">Actions</h2>

      {error && (
        <div className="mb-3 rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">{error}</div>
      )}

      {transfer.status === "REQUESTED" && (
        <div className="space-y-3">
          {isOwnRequest && has("approve_transfer") && (
            <p className="text-xs text-amber-600">
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
                className="rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-50"
              >
                Approve
              </button>
              <button
                disabled={pending}
                onClick={() => {
                  const reason = window.prompt("Reason for rejection:");
                  if (reason) run(() => rejectTransferAction(transfer.id, reason));
                }}
                className="rounded-md border border-slate-300 px-4 py-2 text-sm font-medium text-slate-700 hover:bg-slate-50 disabled:opacity-50"
              >
                Reject
              </button>
            </div>
          )}
        </div>
      )}

      {transfer.status === "APPROVED" && has("dispatch_transfer") && (
        <div className="space-y-3">
          <p className="text-xs text-slate-500">Confirm actual dispatched quantities:</p>
          {items.map((it) => (
            <div key={it.id} className="flex items-center justify-between gap-3 text-sm">
              <span>{it.equipment_type?.source_code} — {it.equipment_type?.name}</span>
              <input
                type="number"
                min={0}
                defaultValue={it.quantity_approved ?? it.quantity_requested}
                onChange={(e) => setQuantities((q) => ({ ...q, [it.id]: parseInt(e.target.value, 10) || 0 }))}
                className="w-24 rounded-md border border-slate-300 px-2 py-1"
              />
            </div>
          ))}
          <button
            disabled={pending}
            onClick={() =>
              run(() =>
                dispatchTransferAction(
                  transfer.id,
                  items.map((it) => ({
                    item_id: it.id,
                    quantity_dispatched: qty(it.id, it.quantity_approved ?? it.quantity_requested),
                  }))
                )
              )
            }
            className="rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-50"
          >
            Confirm Dispatch
          </button>
        </div>
      )}

      {transfer.status === "IN_TRANSIT" && has("receive_transfer") && (
        <div className="space-y-3">
          <p className="text-xs text-slate-500">Enter actual quantities received:</p>
          {items.map((it) => (
            <div key={it.id} className="flex items-center justify-between gap-3 text-sm">
              <span>{it.equipment_type?.source_code} — {it.equipment_type?.name}</span>
              <input
                type="number"
                min={0}
                defaultValue={it.quantity_dispatched ?? 0}
                onChange={(e) => setQuantities((q) => ({ ...q, [it.id]: parseInt(e.target.value, 10) || 0 }))}
                className="w-24 rounded-md border border-slate-300 px-2 py-1"
              />
            </div>
          ))}
          <button
            disabled={pending}
            onClick={() =>
              run(() =>
                receiveTransferAction(
                  transfer.id,
                  items.map((it) => ({
                    item_id: it.id,
                    quantity_received: qty(it.id, it.quantity_dispatched ?? 0),
                  }))
                )
              )
            }
            className="rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-50"
          >
            Confirm Receipt
          </button>
        </div>
      )}

      {transfer.status === "RECEIVED" && has("reconcile_transfer") && (
        <div className="space-y-3">
          <p className="text-xs text-slate-500">
            Record any damaged or missing quantities. Differences beyond each item&apos;s tolerance
            will open a discrepancy that must be investigated before closing.
          </p>
          {items.map((it) => (
            <div key={it.id} className="grid grid-cols-3 gap-2 text-sm">
              <span className="col-span-1 self-center">{it.equipment_type?.source_code}</span>
              <div>
                <label className="text-xs text-slate-500">Damaged</label>
                <input
                  type="number"
                  min={0}
                  defaultValue={0}
                  onChange={(e) => setDamaged((d) => ({ ...d, [it.id]: parseInt(e.target.value, 10) || 0 }))}
                  className="w-full rounded-md border border-slate-300 px-2 py-1"
                />
              </div>
              <div>
                <label className="text-xs text-slate-500">Missing</label>
                <input
                  type="number"
                  min={0}
                  defaultValue={0}
                  onChange={(e) => setMissing((m) => ({ ...m, [it.id]: parseInt(e.target.value, 10) || 0 }))}
                  className="w-full rounded-md border border-slate-300 px-2 py-1"
                />
              </div>
            </div>
          ))}
          <button
            disabled={pending}
            onClick={() =>
              run(() =>
                reconcileTransferAction(
                  transfer.id,
                  items.map((it) => ({
                    item_id: it.id,
                    quantity_damaged: damaged[it.id] ?? 0,
                    quantity_missing: missing[it.id] ?? 0,
                  }))
                )
              )
            }
            className="rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-50"
          >
            Reconcile
          </button>
        </div>
      )}

      {transfer.status === "RECONCILIATION" && has("reconcile_transfer") && (
        <button
          disabled={pending}
          onClick={() => run(() => closeTransferAction(transfer.id))}
          className="rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-50"
        >
          Close Transfer
        </button>
      )}

      {transfer.status === "DISCREPANCY" && has("reconcile_transfer") && (
        <div className="space-y-3">
          <p className="text-xs text-red-600">
            This transfer has an unexplained discrepancy beyond tolerance. It cannot be closed until
            resolved with a documented reason.
          </p>
          <textarea
            value={reasonText}
            onChange={(e) => setReasonText(e.target.value)}
            rows={2}
            placeholder="Explain the investigation outcome..."
            className="w-full rounded-md border border-slate-300 px-3 py-2 text-sm"
          />
          <button
            disabled={pending || reasonText.trim().length === 0}
            onClick={() => run(() => resolveDiscrepancyAction(transfer.id, reasonText))}
            className="rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white hover:bg-slate-800 disabled:opacity-50"
          >
            Resolve Discrepancy
          </button>
        </div>
      )}

      {["CLOSED", "REJECTED", "CANCELLED"].includes(transfer.status) && (
        <p className="text-sm text-slate-500">This transfer is finalized. No further action available.</p>
      )}
    </div>
  );
}
