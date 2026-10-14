"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { createRole, setRolePermission } from "./actions";

type Role = { id: string; code: string; name: string; description: string | null; permissions: string[] };
type Perm = { code: string; description: string | null };

export function RoleMatrix({ roles, permissions, myPerms, canEdit }: { roles: Role[]; permissions: Perm[]; myPerms: string[]; canEdit: boolean }) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [code, setCode] = useState("");
  const [name, setName] = useState("");
  const [desc, setDesc] = useState("");
  const mine = new Set(myPerms);

  function toggle(role: Role, perm: string, granted: boolean) {
    setError(null);
    startTransition(async () => {
      const res = await setRolePermission(role.id, perm, granted);
      if (!res.ok) setError(res.error);
      router.refresh();
    });
  }

  function add(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    startTransition(async () => {
      const res = await createRole(code, name, desc);
      if (!res.ok) return setError(res.error);
      setCode(""); setName(""); setDesc("");
      router.refresh();
    });
  }

  return (
    <div className="space-y-6">
      {error && <p className="rounded-sm px-3 py-2 text-sm text-(--brick)" style={{ background: "var(--brick-surface)" }}>{error}</p>}
      <div className="panel overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="text-left text-xs text-(--steel)">
              <th className="sticky left-0 bg-(--color-surface) p-3">Permission</th>
              {roles.map((r) => <th key={r.id} className="p-3 text-center align-bottom" title={r.description ?? ""}>{r.name}</th>)}
            </tr>
          </thead>
          <tbody>
            {permissions.map((p) => (
              <tr key={p.code} className="border-t border-(--border)">
                <td className="sticky left-0 bg-(--color-surface) p-3">
                  <div className="id-code">{p.code}</div>
                  <div className="text-xs text-(--steel)">{p.description}</div>
                </td>
                {roles.map((r) => {
                  const on = r.permissions.includes(p.code);
                  const locked = r.code === "system_admin" || !canEdit || !mine.has(p.code);
                  return (
                    <td key={r.id} className="p-3 text-center">
                      <input type="checkbox" checked={on} disabled={locked || pending}
                        title={r.code === "system_admin" ? "Locked" : !mine.has(p.code) ? "You do not hold this permission" : ""}
                        onChange={(e) => toggle(r, p.code, e.target.checked)} />
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {canEdit && (
        <form onSubmit={add} className="panel max-w-xl space-y-3 p-4">
          <h2 className="font-semibold text-(--navy)">New role</h2>
          <p className="text-xs text-(--steel)">Create the role, then tick its permissions in the table above.</p>
          <div className="flex flex-wrap gap-3">
            <input required value={name} onChange={(e) => setName(e.target.value)} placeholder="Name, e.g. Quality Auditor" className="min-w-52 flex-1 rounded-sm border border-(--border) px-3 py-2 text-sm" />
            <input required value={code} onChange={(e) => setCode(e.target.value)} placeholder="code_like_this" className="id-code w-48 rounded-sm border border-(--border) px-3 py-2 text-sm" />
          </div>
          <input value={desc} onChange={(e) => setDesc(e.target.value)} placeholder="Description (optional)" className="w-full rounded-sm border border-(--border) px-3 py-2 text-sm" />
          <button className="btn-primary px-4 py-2 text-sm" disabled={pending}>Create role</button>
        </form>
      )}
    </div>
  );
}
