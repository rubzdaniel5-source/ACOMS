"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { addAlias, removeAlias, setEquipmentActive } from "../actions";

export function EquipmentSidePanel({ id, isActive, onHand, aliases }: { id: string; isActive: boolean; onHand: number; aliases: { id: string; alias: string }[] }) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [alias, setAlias] = useState("");
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);

  function run(fn: () => Promise<{ ok: boolean; error?: string }>, after?: () => void) {
    setError(null);
    startTransition(async () => {
      const r = await fn();
      if (!r.ok) return setError(r.error ?? "Failed");
      after?.();
      router.refresh();
    });
  }

  return (
    <aside className="space-y-4">
      {error && <p className="rounded-sm px-3 py-2 text-sm text-(--brick)" style={{ background: "var(--brick-surface)" }}>{error}</p>}
      <section className="panel p-4">
        <div className="text-xs text-(--steel)">Units on the books</div>
        <div className="text-2xl font-semibold text-(--navy)">{onHand}</div>
      </section>

      <section className="panel space-y-2 p-4">
        <h2 className="font-semibold text-(--navy)">Search aliases</h2>
        <div className="flex flex-wrap gap-1">
          {aliases.length === 0 && <span className="text-sm text-(--steel)">None</span>}
          {aliases.map((a) => (
            <span key={a.id} className="tag tag-neutral">{a.alias}
              <button className="ml-1 text-(--brick)" aria-label={`Remove ${a.alias}`} disabled={pending} onClick={() => run(() => removeAlias(id, a.id))}>×</button>
            </span>
          ))}
        </div>
        <div className="flex gap-2">
          <input value={alias} onChange={(e) => setAlias(e.target.value)} placeholder="Add alias" className="min-w-0 flex-1 rounded-sm border border-(--border) px-2 py-1.5 text-sm" />
          <button className="btn-secondary px-3 py-1.5 text-sm" disabled={pending || !alias.trim()} onClick={() => run(() => addAlias(id, alias), () => setAlias(""))}>Add</button>
        </div>
      </section>

      <section className="panel space-y-2 p-4">
        <h2 className="font-semibold text-(--navy)">{isActive ? "Deactivate" : "Reactivate"}</h2>
        {isActive ? (
          <>
            <p className="text-xs text-(--steel)">Hides the item from new transfers and reports. Not possible while stock is on the books.</p>
            <input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Reason (required)" className="w-full rounded-sm border border-(--border) px-2 py-1.5 text-sm" />
            <button className="w-full rounded-sm border border-(--brick) px-3 py-1.5 text-sm text-(--brick) hover:bg-(--brick-surface)" disabled={pending || !reason.trim()}
              onClick={() => run(() => setEquipmentActive(id, false, reason), () => setReason(""))}>Deactivate</button>
          </>
        ) : (
          <button className="btn-primary w-full px-3 py-1.5 text-sm" disabled={pending} onClick={() => run(() => setEquipmentActive(id, true, ""))}>Reactivate</button>
        )}
      </section>
    </aside>
  );
}
