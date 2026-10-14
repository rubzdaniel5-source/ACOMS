"use client";

import Link from "next/link";
import { ExportCsvButton } from "@/components/ui/ExportCsvButton";

type Row = {
  id: string; created_at: string; action: string; actor_label: string | null; entity_type: string; entity_id: string;
  station_code: string | null; reason: string | null; before_state: unknown; after_state: unknown;
};

const LINKS: Record<string, (id: string) => string> = {
  equipment_transfer: (id) => `/transfers/${id}`,
  user: (id) => `/admin/users/${id}`,
  equipment_type: (id) => `/admin/catalogue/${id}`,
  stock_adjustment: (id) => `/admin/adjustments/${id}`,
};

const when = (s: string) => new Date(s).toLocaleString("en-GB", { dateStyle: "short", timeStyle: "medium", timeZone: "Africa/Kampala" });

export function AuditRows({ rows }: { rows: Row[] }) {
  return (
    <div>
      <div className="mb-2 flex justify-end">
        <ExportCsvButton filename="audit-log.csv" rows={rows.map((r) => ({
          when: when(r.created_at), person: r.actor_label ?? "System", action: r.action, entity: r.entity_type, entity_id: r.entity_id,
          station: r.station_code ?? "", reason: r.reason ?? "", before: JSON.stringify(r.before_state ?? ""), after: JSON.stringify(r.after_state ?? ""),
        }))} />
      </div>
      <div className="panel overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="text-left text-sm text-(--steel)">
            <tr><th className="p-3">When</th><th className="p-3">Person</th><th className="p-3">Action</th><th className="p-3">Record</th><th className="p-3">Station</th><th className="p-3">Reason</th></tr>
          </thead>
          <tbody>
            {rows.length === 0 && <tr><td colSpan={6} className="p-6 text-center text-(--steel)">No entries match.</td></tr>}
            {rows.map((r) => {
              const link = LINKS[r.entity_type]?.(r.entity_id);
              const hasDetail = r.before_state != null || r.after_state != null;
              return (
                <tr key={r.id} className="border-t border-(--border) align-top">
                  <td className="whitespace-nowrap p-3">{when(r.created_at)}</td>
                  <td className="p-3">{r.actor_label ?? <span className="text-(--steel)">System</span>}</td>
                  <td className="p-3">
                    <span className="id-code">{r.action}</span>
                    {hasDetail && (
                      <details className="mt-1 text-xs text-(--steel)">
                        <summary className="cursor-pointer">Details</summary>
                        {r.before_state != null && <pre className="mt-1 whitespace-pre-wrap">Before: {JSON.stringify(r.before_state, null, 1)}</pre>}
                        {r.after_state != null && <pre className="mt-1 whitespace-pre-wrap">After: {JSON.stringify(r.after_state, null, 1)}</pre>}
                      </details>
                    )}
                  </td>
                  <td className="p-3">
                    {link ? <Link href={link} className="text-(--navy) hover:underline">{r.entity_type.replace(/_/g, " ")}</Link> : r.entity_type.replace(/_/g, " ")}
                  </td>
                  <td className="id-code p-3">{r.station_code ?? "—"}</td>
                  <td className="p-3 text-(--steel)">{r.reason ?? ""}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
