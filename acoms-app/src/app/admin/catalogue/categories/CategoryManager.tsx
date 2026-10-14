"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { saveCategory } from "../actions";

type Cat = { id: string; code: string; name: string; is_active: boolean; count: number };

export function CategoryManager({ categories }: { categories: Cat[] }) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [code, setCode] = useState("");
  const [name, setName] = useState("");
  const [edits, setEdits] = useState<Record<string, string>>({});

  function run(fn: () => ReturnType<typeof saveCategory>, after?: () => void) {
    setError(null);
    startTransition(async () => {
      const r = await fn();
      if (!r.ok) return setError(r.error);
      after?.();
      router.refresh();
    });
  }

  return (
    <div className="space-y-4">
      {error && <p className="rounded-sm px-3 py-2 text-sm text-(--brick)" style={{ background: "var(--brick-surface)" }}>{error}</p>}
      <div className="panel">
        {categories.map((c) => (
          <div key={c.id} className="flex flex-wrap items-center gap-3 border-t border-(--border) p-3 first:border-t-0">
            <span className="id-code w-32 text-sm">{c.code}</span>
            <input value={edits[c.id] ?? c.name} onChange={(e) => setEdits({ ...edits, [c.id]: e.target.value })}
              className="min-w-48 flex-1 rounded-sm border border-(--border) px-2 py-1.5 text-sm" />
            <span className="text-xs text-(--steel)">{c.count} item{c.count === 1 ? "" : "s"}</span>
            <button className="btn-secondary px-3 py-1.5 text-sm" disabled={pending || (edits[c.id] ?? c.name) === c.name}
              onClick={() => run(() => saveCategory(c.id, c.code, edits[c.id], c.is_active))}>Rename</button>
            <button className="btn-secondary px-3 py-1.5 text-sm" disabled={pending}
              onClick={() => run(() => saveCategory(c.id, c.code, c.name, !c.is_active))}>{c.is_active ? "Deactivate" : "Reactivate"}</button>
          </div>
        ))}
      </div>
      <form className="panel flex flex-wrap items-end gap-3 p-4" onSubmit={(e) => { e.preventDefault(); run(() => saveCategory(null, code, name, true), () => { setCode(""); setName(""); }); }}>
        <div><label className="mb-1 block text-xs text-(--steel)">Code</label>
          <input required value={code} onChange={(e) => setCode(e.target.value.toUpperCase())} placeholder="CUTLERY" className="id-code w-40 rounded-sm border border-(--border) px-2 py-1.5 text-sm" /></div>
        <div className="min-w-48 flex-1"><label className="mb-1 block text-xs text-(--steel)">Name</label>
          <input required value={name} onChange={(e) => setName(e.target.value)} className="w-full rounded-sm border border-(--border) px-2 py-1.5 text-sm" /></div>
        <button className="btn-primary px-4 py-1.5 text-sm" disabled={pending}>Add category</button>
      </form>
    </div>
  );
}
