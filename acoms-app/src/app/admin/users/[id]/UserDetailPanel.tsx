"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { assignRole, removeRole, resetPassword, setUserActive, updateProfile } from "../actions";
import { generateTempPassword } from "../passwords";

type Role = { id: string; name: string };
type Station = { id: string; code: string; name: string };
type User = {
  id: string; full_name: string; email: string; affiliation: string; is_active: boolean;
  last_sign_in_at: string | null; must_change_password: boolean;
  roles: { user_role_id: string; role_name: string; station_code: string | null }[];
};

const input = "rounded-sm border border-(--border) px-3 py-2 text-sm";

export function UserDetailPanel({ user, isSelf, roles, stations }: { user: User; isSelf: boolean; roles: Role[]; stations: Station[] }) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [msg, setMsg] = useState<{ kind: "ok" | "err"; text: string } | null>(null);
  const [fullName, setFullName] = useState(user.full_name);
  const [affiliation, setAffiliation] = useState(user.affiliation);
  const [roleId, setRoleId] = useState("");
  const [stationId, setStationId] = useState("");
  const [tempPw, setTempPw] = useState<string | null>(null);
  const [reason, setReason] = useState("");

  function run(fn: () => Promise<{ ok: boolean; error?: string }>, okText: string, after?: () => void) {
    setMsg(null);
    startTransition(async () => {
      const res = await fn();
      if (!res.ok) return setMsg({ kind: "err", text: res.error ?? "Failed" });
      setMsg({ kind: "ok", text: okText });
      after?.();
      router.refresh();
    });
  }

  return (
    <div className="space-y-4">
      <div className="flex items-start justify-between gap-4">
        <div>
          <h1 className="text-xl font-semibold text-(--navy)">{user.full_name}</h1>
          <p className="text-sm text-(--steel)">{user.email}</p>
        </div>
        {!user.is_active ? <span className="tag tag-brick">Inactive</span>
          : user.must_change_password ? <span className="tag tag-amber">Password pending</span>
          : <span className="tag tag-teal">Active</span>}
      </div>

      {msg && (
        <p className={`rounded-sm px-3 py-2 text-sm ${msg.kind === "ok" ? "text-(--teal)" : "text-(--brick)"}`}
          style={{ background: msg.kind === "ok" ? "var(--teal-surface)" : "var(--brick-surface)" }}>{msg.text}</p>
      )}
      {isSelf && <p className="text-sm text-(--steel)">This is your own account. You cannot change your own roles, status or password reset here.</p>}

      <section className="panel space-y-3 p-4">
        <h2 className="font-semibold text-(--navy)">Profile</h2>
        <div className="flex flex-wrap gap-3">
          <input value={fullName} onChange={(e) => setFullName(e.target.value)} className={`${input} min-w-64 flex-1`} />
          <select value={affiliation} onChange={(e) => setAffiliation(e.target.value)} className={input}>
            <option value="internal">Airline employee</option>
            <option value="external_provider">Outstation catering provider</option>
          </select>
          <button className="btn-primary px-4 py-2 text-sm" disabled={pending}
            onClick={() => run(() => updateProfile(user.id, fullName, affiliation), "Profile saved")}>Save</button>
        </div>
      </section>

      <section className="panel space-y-3 p-4">
        <h2 className="font-semibold text-(--navy)">Roles and station scope</h2>
        <div className="space-y-2">
          {user.roles.length === 0 && <p className="text-sm text-(--steel)">No roles assigned — this user cannot do anything yet.</p>}
          {user.roles.map((r) => (
            <div key={r.user_role_id} className="flex items-center justify-between rounded-sm border border-(--border) px-3 py-2 text-sm">
              <span>{r.role_name} <span className="text-(--steel)">· {r.station_code ?? "Network-wide"}</span></span>
              {!isSelf && (
                <button className="text-(--brick) hover:underline" disabled={pending}
                  onClick={() => confirm(`Remove ${r.role_name}?`) && run(() => removeRole(user.id, r.user_role_id), "Role removed")}>Remove</button>
              )}
            </div>
          ))}
        </div>
        {!isSelf && (
          <div className="flex flex-wrap gap-3 border-t border-(--border) pt-3">
            <select value={roleId} onChange={(e) => setRoleId(e.target.value)} className={input}>
              <option value="">Add a role…</option>
              {roles.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
            </select>
            <select value={stationId} onChange={(e) => setStationId(e.target.value)} className={input}>
              <option value="">Network-wide</option>
              {stations.map((s) => <option key={s.id} value={s.id}>{s.code} — {s.name}</option>)}
            </select>
            <button className="btn-secondary px-4 py-2 text-sm" disabled={pending || !roleId}
              onClick={() => run(() => assignRole(user.id, roleId, stationId || null), "Role added", () => setRoleId(""))}>Add</button>
          </div>
        )}
      </section>

      {!isSelf && (
        <section className="panel space-y-3 p-4">
          <h2 className="font-semibold text-(--navy)">Password</h2>
          {tempPw ? (
            <div className="text-sm">
              <p className="mb-1 text-(--steel)">Temporary password (shown once; the user must change it at next sign-in):</p>
              <p className="id-code text-base">{tempPw}</p>
            </div>
          ) : (
            <button className="btn-secondary px-4 py-2 text-sm" disabled={pending}
              onClick={() => { const pw = generateTempPassword(); run(() => resetPassword(user.id, pw), "Password reset", () => setTempPw(pw)); }}>
              Reset to a temporary password
            </button>
          )}
        </section>
      )}

      {!isSelf && (
        <section className="panel space-y-3 p-4">
          <h2 className="font-semibold text-(--navy)">{user.is_active ? "Deactivate" : "Reactivate"}</h2>
          {user.is_active ? (
            <div className="flex flex-wrap gap-3">
              <input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Reason (required, e.g. left the company)" className={`${input} min-w-64 flex-1`} />
              <button className="rounded-sm border border-(--brick) px-4 py-2 text-sm text-(--brick) hover:bg-(--brick-surface)" disabled={pending || !reason.trim()}
                onClick={() => confirm("Deactivate this user? They lose all access immediately.") && run(() => setUserActive(user.id, false, reason), "User deactivated", () => setReason(""))}>Deactivate</button>
            </div>
          ) : (
            <button className="btn-primary px-4 py-2 text-sm" disabled={pending}
              onClick={() => run(() => setUserActive(user.id, true, ""), "User reactivated")}>Reactivate</button>
          )}
        </section>
      )}
    </div>
  );
}
