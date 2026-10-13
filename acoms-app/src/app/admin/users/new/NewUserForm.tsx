"use client";

import { useState, useTransition } from "react";
import Link from "next/link";
import { createUser } from "../actions";
import { generateTempPassword } from "../passwords";

type Role = { id: string; name: string; description: string | null };
type Station = { id: string; code: string; name: string };

export function NewUserForm({ roles, stations }: { roles: Role[]; stations: Station[] }) {
  const [fullName, setFullName] = useState("");
  const [email, setEmail] = useState("");
  const [affiliation, setAffiliation] = useState("internal");
  const [roleId, setRoleId] = useState("");
  const [stationId, setStationId] = useState("");
  const [password, setPassword] = useState(() => generateTempPassword());
  const [error, setError] = useState<string | null>(null);
  const [created, setCreated] = useState<{ id: string; email: string; password: string } | null>(null);
  const [copied, setCopied] = useState(false);
  const [pending, startTransition] = useTransition();

  function submit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    startTransition(async () => {
      const res = await createUser({ fullName, email, affiliation, roleId, stationId: stationId || null, password });
      if (!res.ok) return setError(res.error);
      setCreated({ id: res.message ?? "", email, password });
    });
  }

  if (created) {
    return (
      <div className="panel max-w-lg p-6">
        <h2 className="mb-2 font-semibold text-(--teal)">User created</h2>
        <p className="mb-4 text-sm text-(--steel)">Share these details securely. The password is shown only now and must be changed at first sign-in.</p>
        <dl className="mb-4 space-y-2 text-sm">
          <div><dt className="text-xs text-(--steel)">Email</dt><dd className="id-code">{created.email}</dd></div>
          <div><dt className="text-xs text-(--steel)">Temporary password</dt><dd className="id-code text-base">{created.password}</dd></div>
        </dl>
        <div className="flex gap-3">
          <button className="btn-secondary px-4 py-2 text-sm" onClick={async () => {
            try { await navigator.clipboard.writeText(`Email: ${created.email}\nTemporary password: ${created.password}`); setCopied(true); } catch {}
          }}>{copied ? "Copied" : "Copy details"}</button>
          <Link href={`/admin/users/${created.id}`} className="btn-primary px-4 py-2 text-sm">Open user</Link>
        </div>
      </div>
    );
  }

  const input = "w-full rounded-sm border border-(--border) px-3 py-2 text-sm";
  return (
    <form onSubmit={submit} className="panel max-w-lg space-y-4 p-6">
      <div><label className="mb-1 block text-sm font-medium">Full name</label>
        <input required value={fullName} onChange={(e) => setFullName(e.target.value)} className={input} /></div>
      <div><label className="mb-1 block text-sm font-medium">Email</label>
        <input required type="email" value={email} onChange={(e) => setEmail(e.target.value)} className={input} /></div>
      <div><label className="mb-1 block text-sm font-medium">Affiliation</label>
        <select value={affiliation} onChange={(e) => setAffiliation(e.target.value)} className={input}>
          <option value="internal">Airline employee</option>
          <option value="external_provider">Outstation catering provider</option>
        </select></div>
      <div><label className="mb-1 block text-sm font-medium">Role</label>
        <select required value={roleId} onChange={(e) => setRoleId(e.target.value)} className={input}>
          <option value="">Select a role…</option>
          {roles.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
        </select>
        <p className="mt-1 text-xs text-(--steel)">Only roles whose permissions you hold yourself are listed.</p></div>
      <div><label className="mb-1 block text-sm font-medium">Station scope</label>
        <select value={stationId} onChange={(e) => setStationId(e.target.value)} className={input}>
          <option value="">Network-wide (all stations)</option>
          {stations.map((s) => <option key={s.id} value={s.id}>{s.code} — {s.name}</option>)}
        </select></div>
      <div><label className="mb-1 block text-sm font-medium">Temporary password</label>
        <div className="flex gap-2">
          <input required minLength={10} value={password} onChange={(e) => setPassword(e.target.value)} className={`${input} id-code`} />
          <button type="button" className="btn-secondary whitespace-nowrap px-3 py-2 text-sm" onClick={() => setPassword(generateTempPassword())}>Generate</button>
        </div></div>
      {error && <p className="rounded-sm px-3 py-2 text-sm text-(--brick)" style={{ background: "var(--brick-surface)" }}>{error}</p>}
      <button type="submit" disabled={pending} className="btn-primary px-4 py-2 text-sm">{pending ? "Creating…" : "Create user"}</button>
    </form>
  );
}
