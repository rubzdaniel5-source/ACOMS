"use client";

import { useEffect, useRef, useState } from "react";

interface Props {
  open: boolean;
  title: string;
  description?: string;
  confirmLabel: string;
  danger?: boolean;
  /** When set, a reason must be entered before confirming. */
  reasonLabel?: string;
  pending?: boolean;
  onConfirm: (reason: string) => void;
  onCancel: () => void;
}

// Themed confirmation built on the native <dialog>: focus is trapped, Escape
// cancels, and background content is inert while it is open.
export function ConfirmDialog({ open, title, description, confirmLabel, danger, reasonLabel, pending, onConfirm, onCancel }: Props) {
  const ref = useRef<HTMLDialogElement>(null);
  const [reason, setReason] = useState("");

  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (open && !d.open) d.showModal();
    if (!open && d.open) d.close();
    // Reset the reason for each new opening.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    if (open) setReason("");
  }, [open]);

  const needsReason = Boolean(reasonLabel);
  const blocked = pending || (needsReason && reason.trim().length === 0);

  return (
    <dialog
      ref={ref}
      onCancel={(e) => { e.preventDefault(); if (!pending) onCancel(); }}
      aria-labelledby="confirm-title"
      className="m-auto w-[calc(100%-2rem)] max-w-md rounded-xl border border-(--color-border-strong) bg-(--color-surface-raised) p-0 text-(--color-text) shadow-(--shadow-raised) backdrop:bg-black/50"
    >
      <form
        method="dialog"
        onSubmit={(e) => { e.preventDefault(); if (!blocked) onConfirm(reason.trim()); }}
        className="space-y-4 p-5"
      >
        <h2 id="confirm-title" className="text-lg font-semibold">{title}</h2>
        {description && <p className="text-sm text-(--color-text-muted)">{description}</p>}
        {needsReason && (
          <div>
            <label htmlFor="confirm-reason" className="mb-1 block text-sm font-medium text-(--color-text-muted)">{reasonLabel}</label>
            <textarea id="confirm-reason" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} className="w-full px-3 py-2 text-sm" />
          </div>
        )}
        <div className="flex flex-wrap justify-end gap-3">
          <button type="button" onClick={onCancel} disabled={pending} className="btn-secondary min-h-11 px-5 text-sm">Cancel</button>
          <button type="submit" disabled={blocked} className={`${danger ? "btn-danger" : "btn-primary"} min-h-11 px-5 text-sm`}>
            {pending ? "Working" : confirmLabel}
          </button>
        </div>
      </form>
    </dialog>
  );
}
