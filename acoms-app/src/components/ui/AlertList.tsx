import Link from "next/link";
import type { Alert, Severity } from "@/features/dashboard/alerts";

const TAG: Record<Severity, string> = { critical: "tag-brick", warning: "tag-amber", attention: "tag-info" };

export function AlertList({ alerts }: { alerts: Alert[] }) {
  if (alerts.length === 0) {
    return (
      <div className="panel px-6 py-8 text-center">
        <p className="font-semibold text-(--color-success)">Nothing needs action right now.</p>
        <p className="mt-1 text-sm text-(--color-text-muted)">Shortages, overdue transfers, open reports and approvals will appear here.</p>
      </div>
    );
  }
  return (
    <ul className="panel divide-y divide-(--color-border)">
      {alerts.map((a) => (
        <li key={a.key} className="flex flex-wrap items-start justify-between gap-x-4 gap-y-2 px-4 py-3 text-sm">
          <div className="min-w-0 flex-1">
            <div className="flex flex-wrap items-center gap-2">
              <span className={`tag ${TAG[a.severity]}`}>{a.label}</span>
              {a.station && <span className="id-code text-(--color-text-muted)">{a.station}</span>}
              {a.reference && <span className="id-code font-medium text-(--color-text)">{a.reference}</span>}
            </div>
            <p className="mt-1 text-(--color-text-muted)">{a.detail}</p>
          </div>
          <div className="flex flex-wrap gap-x-4">
            <Link href={a.href} className="inline-flex min-h-11 items-center font-semibold text-(--color-primary) hover:underline">View</Link>
            {a.actions.filter((x) => x.href !== a.href).map((x) => (
              <Link key={x.label} href={x.href} className="inline-flex min-h-11 items-center font-semibold text-(--color-primary) hover:underline">{x.label}</Link>
            ))}
          </div>
        </li>
      ))}
    </ul>
  );
}
