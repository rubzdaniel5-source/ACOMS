"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { approveAdjustment, cancelAdjustment, rejectAdjustment } from "../actions";

export function DecisionPanel({ id, canApprove, isMine }: { id: string; canApprove: boolean; isMine: boolean }) {
  const router = useRouter();
  const [note, setNote] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function run(fn: () => Promise<{ ok: boolean; error?: string }>) {
    setError(null);
    startTransition(async () => {
      const r = await fn();
      if (!r.ok) return setError(r.error ?? "Failed");
      router.refresh();
    });
  }

  if (!canApprove && !isMine) return <p className="mt-4 text-sm text-(--steel)">Waiting for an authorised approver.</p>;

  return (
    <div className="panel mt-4 space-y-3 p-5">
      {isMine && <p className="text-sm text-(--steel)">You requested this, so someone else must approve it. You can cancel it while it is pending.</p>}
      {canApprove && (
        <>
          <input value={note} onChange={(e) => setNote(e.target.value)} placeholder="Note (required to reject)" className="w-full rounded-sm border border-(--border) px-3 py-2 text-sm" />
          <div className="flex gap-3">
            <button className="btn-primary px-4 py-2 text-sm" disabled={pending} onClick={() => run(() => approveAdjustment(id, note))}>Approve and apply</button>
            <button className="rounded-sm border border-(--brick) px-4 py-2 text-sm text-(--brick) hover:bg-(--brick-surface)" disabled={pending || !note.trim()} onClick={() => run(() => rejectAdjustment(id, note))}>Reject</button>
          </div>
        </>
      )}
      {isMine && <button className="btn-secondary px-4 py-2 text-sm" disabled={pending} onClick={() => run(() => cancelAdjustment(id))}>Cancel request</button>}
      {error && <p className="text-sm text-(--brick)">{error}</p>}
    </div>
  );
}
