"use client";

import Link from "next/link";
import { useState } from "react";

type U = {
  id: string; full_name: string; email: string; affiliation: string; is_active: boolean;
  last_sign_in_at: string | null; must_change_password: boolean;
  roles: { role_name: string; station_code: string | null }[];
};

export function UsersTable({ users }: { users: U[] }) {
  const [q, setQ] = useState("");
  const [status, setStatus] = useState("active");

  const rows = users.filter((u) => {
    if (status === "active" && !u.is_active) return false;
    if (status === "inactive" && u.is_active) return false;
    const t = q.trim().toLowerCase();
    return !t || u.full_name.toLowerCase().includes(t) || u.email.toLowerCase().includes(t) ||
      u.roles.some((r) => r.role_name.toLowerCase().includes(t) || (r.station_code ?? "").toLowerCase().includes(t));
  });

  return (
    <div>
      <div className="mb-3 flex flex-wrap gap-3">
        <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search name, email, role or station"
          className="w-full max-w-sm rounded-sm border border-(--border) px-3 py-2 text-sm" />
        <select value={status} onChange={(e) => setStatus(e.target.value)} className="rounded-sm border border-(--border) px-3 py-2 text-sm">
          <option value="active">Active</option>
          <option value="inactive">Inactive</option>
          <option value="all">All</option>
        </select>
      </div>
      <div className="panel overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="text-left text-xs text-(--steel)">
            <tr><th className="p-3">Name</th><th className="p-3">Roles</th><th className="p-3">Last sign-in</th><th className="p-3">Status</th></tr>
          </thead>
          <tbody>
            {rows.length === 0 && <tr><td colSpan={4} className="p-6 text-center text-(--steel)">No users match.</td></tr>}
            {rows.map((u) => (
              <tr key={u.id} className="border-t border-(--border)">
                <td className="p-3">
                  <Link href={`/admin/users/${u.id}`} className="font-medium text-(--navy) hover:underline">{u.full_name}</Link>
                  <div className="text-xs text-(--steel)">{u.email}</div>
                </td>
                <td className="p-3">
                  <div className="flex flex-wrap gap-1">
                    {u.roles.length === 0 && <span className="text-(--steel)">None</span>}
                    {u.roles.map((r, i) => (
                      <span key={i} className="tag tag-neutral">{r.role_name}{r.station_code ? ` · ${r.station_code}` : ""}</span>
                    ))}
                  </div>
                </td>
                <td className="whitespace-nowrap p-3 text-(--steel)">
                  {u.last_sign_in_at ? new Date(u.last_sign_in_at).toLocaleDateString("en-GB", { dateStyle: "medium" }) : "Never"}
                </td>
                <td className="p-3">
                  {!u.is_active ? <span className="tag tag-brick">Inactive</span>
                    : u.must_change_password ? <span className="tag tag-amber">Password pending</span>
                    : <span className="tag tag-teal">Active</span>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
