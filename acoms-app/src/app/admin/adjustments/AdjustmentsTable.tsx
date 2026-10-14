"use client";

import Link from "next/link";
import { useState } from "react";
import { REASON_LABELS, STATUS_TAG } from "@/features/admin/adjustments";

type Row = {
  id: string; adjustment_number: string; status: string; direction: string; quantity: number; reason_code: string;
  requested_at: string; requested_by: string; requested_by_name: string; station_code: string; equipment_name: string; source_code: string;
};

export function AdjustmentsTable({ rows, me, canApprove }: { rows: Row[]; me: string | null; canApprove: boolean }) {
  const pendingForMe = rows.filter((r) => r.status === "REQUESTED" && r.requested_by !== me);
  const [tab, setTab] = useState<"approve" | "mine" | "all">(canApprove && pendingForMe.length > 0 ? "approve" : "all");
  const shown = tab === "approve" ? pendingForMe : tab === "mine" ? rows.filter((r) => r.requested_by === me) : rows;

  const tabBtn = (key: typeof tab, label: string, count?: number) => (
    <button onClick={() => setTab(key)} className={`rounded-sm px-3 py-1.5 text-sm font-medium ${tab === key ? "bg-(--navy) text-white" : "text-(--steel) hover:bg-(--steel-light)"}`}>
      {label}{count !== undefined ? ` (${count})` : ""}
    </button>
  );

  return (
    <div>
      <div className="mb-3 flex gap-2">
        {canApprove && tabBtn("approve", "Needs my approval", pendingForMe.length)}
        {tabBtn("mine", "My requests")}
        {tabBtn("all", "All")}
      </div>
      <div className="panel overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="text-left text-xs uppercase text-(--steel)">
            <tr><th className="p-3">Ref</th><th className="p-3">Station</th><th className="p-3">Equipment</th><th className="p-3 text-right">Change</th><th className="p-3">Reason</th><th className="p-3">Requested by</th><th className="p-3">Status</th></tr>
          </thead>
          <tbody>
            {shown.length === 0 && <tr><td colSpan={7} className="p-6 text-center text-(--steel)">Nothing here.</td></tr>}
            {shown.map((r) => (
              <tr key={r.id} className="border-t border-(--border)">
                <td className="p-3"><Link href={`/admin/adjustments/${r.id}`} className="id-code text-(--navy) hover:underline">{r.adjustment_number}</Link></td>
                <td className="id-code p-3">{r.station_code}</td>
                <td className="p-3">{r.equipment_name}</td>
                <td className={`p-3 text-right font-medium ${r.direction === "INCREASE" ? "text-(--teal)" : "text-(--brick)"}`}>{r.direction === "INCREASE" ? "+" : "−"}{r.quantity}</td>
                <td className="p-3 text-(--steel)">{REASON_LABELS[r.reason_code]}</td>
                <td className="p-3">{r.requested_by_name}<div className="text-xs text-(--steel)">{new Date(r.requested_at).toLocaleDateString("en-GB", { dateStyle: "medium" })}</div></td>
                <td className="p-3"><span className={`tag ${STATUS_TAG[r.status]}`}>{r.status.toLowerCase()}</span></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
