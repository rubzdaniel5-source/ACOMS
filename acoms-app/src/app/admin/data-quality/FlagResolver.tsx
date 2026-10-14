"use client";

import Link from "next/link";
import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { resolveFlag } from "../catalogue/actions";

export function FlagResolver({ item }: { item: { id: string; source_code: string; name: string; category: string; data_quality_note: string | null } }) {
  const router = useRouter();
  const [code, setCode] = useState("");
  const [note, setNote] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function submit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    startTransition(async () => {
      const r = await resolveFlag(item.id, code, note);
      if (!r.ok) return setError(r.error);
      router.refresh();
    });
  }

  return (
    <form onSubmit={submit} className="panel space-y-3 p-4">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <div>
          <Link href={`/admin/catalogue/${item.id}`} className="font-medium text-(--navy) hover:underline">{item.name}</Link>
          <span className="ml-2 text-xs text-(--steel)">{item.category}</span>
        </div>
        <span className="id-code tag tag-amber">{item.source_code}</span>
      </div>
      <p className="text-sm text-(--steel)">{item.data_quality_note}</p>
      <div className="flex flex-wrap gap-3">
        <input required value={code} onChange={(e) => setCode(e.target.value)} placeholder="Confirmed code" className="id-code w-48 rounded-sm border border-(--border) px-3 py-2 text-sm" />
        <input value={note} onChange={(e) => setNote(e.target.value)} placeholder="Note (e.g. confirmed by Stores, 12 Oct)" className="min-w-52 flex-1 rounded-sm border border-(--border) px-3 py-2 text-sm" />
        <button className="btn-primary px-4 py-2 text-sm" disabled={pending}>{pending ? "Saving…" : "Confirm code"}</button>
      </div>
      {error && <p className="text-sm text-(--brick)">{error}</p>}
    </form>
  );
}
