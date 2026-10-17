"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { ConfirmDialog } from "@/components/ui/ConfirmDialog";
import { investigateExcessAction, resolveExcessAction } from "./actions";

export interface ExcessHoldRow {
  id: string;
  status: "HELD" | "INVESTIGATING" | "RELEASED" | "REMOVED";
  quantity: number;
  source_code: string;
  equipment_name: string;
  held_by: string;
  investigated_by: string | null;
  findings: string | null;
  treatment: string | null;
  decision_reason: string | null;
}

interface Props {
  transferId: string;
  holds: ExcessHoldRow[];
  permissions: string[];
  currentUserId: string | null;
}

const STATUS_TEXT: Record<ExcessHoldRow["status"], string> = {
  HELD: "Held, not yet investigated",
  INVESTIGATING: "Investigated, awaiting authorisation",
  RELEASED: "Accepted as stock",
  REMOVED: "Removed from records",
};

/** Held excess is never available stock. The database enforces who may investigate and who may authorise. */
export function ExcessHoldPanel({ transferId, holds, permissions, currentUserId }: Props) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [dialog, setDialog] = useState<null | {
    title: string; description: string; confirmLabel: string; danger?: boolean; go: (reason: string) => Promise<{ success: boolean; error?: string }>;
  }>(null);

  if (holds.length === 0) return null;
  const has = (p: string) => permissions.includes(p);

  async function confirmed(reason: string) {
    if (!dialog) return;
    const r = await dialog.go(reason);
    if (!r.success) { setError(r.error ?? "Action failed."); return; }
    setError(null);
    setDialog(null);
    router.refresh();
  }

  return (
    <div className="panel mb-6 p-4 sm:p-5">
      <ConfirmDialog
        open={dialog !== null}
        title={dialog?.title ?? ""}
        description={dialog?.description}
        confirmLabel={dialog?.confirmLabel ?? "Confirm"}
        danger={dialog?.danger}
        reasonLabel="Reason"
        onConfirm={confirmed}
        onCancel={() => setDialog(null)}
      />
      <h2 className="mb-1 text-sm font-semibold text-(--color-text)">Excess units held</h2>
      <p className="mb-3 text-xs text-(--color-text-subtle)">
        These units were counted beyond what was dispatched. They are not available stock until the excess is investigated
        and a different person authorises what happens to it.
      </p>
      {error && <p className="alert alert-danger mb-3">{error}</p>}
      <ul className="space-y-3">
        {holds.map((h) => {
          const own = currentUserId === h.held_by || currentUserId === h.investigated_by;
          return (
            <li key={h.id} className="rounded border border-(--color-border) p-3 text-sm">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <span>{h.quantity} × {h.source_code} — {h.equipment_name}</span>
                <span className={`tag ${h.status === "HELD" || h.status === "INVESTIGATING" ? "tag-amber" : "tag-neutral"}`}>{STATUS_TEXT[h.status]}</span>
              </div>
              {h.findings && <p className="mt-2 text-xs text-(--color-text-subtle)">Findings: {h.findings}</p>}
              {h.decision_reason && <p className="mt-1 text-xs text-(--color-text-subtle)">Decision: {h.decision_reason}</p>}
              {h.status === "HELD" && has("reconcile_transfer") && (
                <button className="btn-secondary mt-3 min-h-11 px-4 text-sm"
                  onClick={() => setDialog({
                    title: "Record investigation findings",
                    description: "Describe what the check found (packing list, load sheet, other stations). At least 10 characters.",
                    confirmLabel: "Save findings",
                    go: (reason) => investigateExcessAction(h.id, transferId, reason),
                  })}>
                  Record investigation
                </button>
              )}
              {h.status === "INVESTIGATING" && has("approve_adjustment") && (
                own ? (
                  <p className="mt-3 text-xs text-(--color-text-subtle)">Someone other than the counter or investigator must authorise the treatment.</p>
                ) : (
                  <div className="mt-3 flex flex-wrap gap-2">
                    <button className="btn-primary min-h-11 px-4 text-sm"
                      onClick={() => setDialog({
                        title: "Accept excess as stock",
                        description: `${h.quantity} unit(s) will become available stock.`,
                        confirmLabel: "Accept as stock",
                        go: (reason) => resolveExcessAction(h.id, transferId, "ACCEPT_AS_STOCK", reason),
                      })}>
                      Accept as stock
                    </button>
                    <button className="btn-secondary min-h-11 px-4 text-sm"
                      onClick={() => setDialog({
                        title: "Remove excess from records",
                        description: `${h.quantity} unit(s) will leave the held bucket and will not become stock.`,
                        confirmLabel: "Remove from records",
                        danger: true,
                        go: (reason) => resolveExcessAction(h.id, transferId, "REMOVE_FROM_RECORDS", reason),
                      })}>
                      Remove from records
                    </button>
                  </div>
                )
              )}
            </li>
          );
        })}
      </ul>
    </div>
  );
}
