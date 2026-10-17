import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { getCurrentUserId, getCurrentUserPermissions } from "@/features/auth/permissions";
import { TransferStatusBadge } from "@/components/ui/TransferStatusBadge";
import { ExchangePanel } from "@/features/exchanges/ExchangePanel";
import { EXCHANGE_STATUS_LABEL, EXCHANGE_STATUS_TAG, LEG_STEPS, LEG_STEP_LABEL, legStepIndex, type ExchangeRow } from "@/features/exchanges/status";
import type { TransferStatus } from "@/types/transfers";

const fmt = (d: string | null) => (d ? new Date(d + "T00:00:00").toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "");

function Progress({ status }: { status: string | null }) {
  const at = legStepIndex(status);
  if (status === "CANCELLED" || status === "REJECTED") return <p className="text-sm text-(--steel)">{status === "CANCELLED" ? "Cancelled" : "Rejected"}</p>;
  return (
    <ol className="flex flex-wrap gap-2" aria-label="Progress">
      {LEG_STEPS.map((s, i) => (
        <li key={s} aria-current={i === at ? "step" : undefined}
          className={`tag ${i < at || (i === at && status === "CLOSED") ? "tag-teal" : i === at ? (status === "DISCREPANCY" ? "tag-brick" : "tag-navy") : "tag-neutral"}`}>
          {LEG_STEP_LABEL[s]}
        </li>
      ))}
    </ol>
  );
}

export default async function ExchangePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();
  const [{ data, error }, perms, userId] = await Promise.all([
    supabase.from("v_equipment_exchanges").select("*").eq("id", id).maybeSingle(),
    getCurrentUserPermissions(),
    getCurrentUserId(),
  ]);
  if (error || !data) {
    return <div className="mx-auto w-full max-w-5xl px-3 py-6 sm:px-6"><p className="alert alert-danger">{error?.message ?? "Exchange not found."}</p></div>;
  }
  const ex = data as ExchangeRow;

  return (
    <div className="mx-auto w-full max-w-5xl px-3 py-6 sm:px-6">
      <Link href="/exchanges" className="mb-4 inline-block text-sm text-(--color-primary) hover:underline">Back to exchanges</Link>
      <div className="mb-6 flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="id-code text-2xl font-semibold text-(--color-text)">{ex.exchange_number}</h1>
          <p className="text-sm text-(--color-text-subtle)">{ex.hub_code} and {ex.outstation_code}</p>
        </div>
        <span className={`tag ${EXCHANGE_STATUS_TAG[ex.status] ?? "tag-neutral"}`}>{EXCHANGE_STATUS_LABEL[ex.status] ?? ex.status}</span>
      </div>

      {ex.next_action && (
        <div className="mb-4 alert alert-info"><span className="font-medium">Next: </span>{ex.next_action}{ex.next_station_code ? ` at ${ex.next_station_code}` : ""}</div>
      )}
      {ex.has_open_discrepancy && <div className="mb-4 alert alert-danger"><span className="font-medium">Unresolved discrepancy. </span>The exchange cannot close until it is resolved.</div>}
      {ex.status === "CLOSED_NO_RETURN" && (
        <div className="mb-4 alert alert-warning">
          <span className="font-medium">Closed without a return. </span>{ex.close_note}
          {ex.no_return_decision_note && <span className="block text-xs">Approval note: {ex.no_return_decision_note}</span>}
        </div>
      )}

      <div className="mb-6 grid gap-4 md:grid-cols-2">
        <section className="panel space-y-3 p-4">
          <h2 className="font-semibold text-(--navy)">Outbound, {ex.hub_code} to {ex.outstation_code}</h2>
          {ex.outbound_id ? (
            <>
              <p className="text-sm"><Link href={`/transfers/${ex.outbound_id}`} className="id-code text-(--color-primary) hover:underline">{ex.outbound_number}</Link>{" "}
                <TransferStatusBadge status={ex.outbound_status as TransferStatus} /></p>
              {ex.outbound_flight && <p className="text-sm text-(--steel)">Flight {ex.outbound_flight}, {fmt(ex.outbound_flight_date)}</p>}
              <Progress status={ex.outbound_status} />
            </>
          ) : <p className="text-sm text-(--steel)">No outbound movement.</p>}
        </section>
        <section className="panel space-y-3 p-4">
          <h2 className="font-semibold text-(--navy)">Return, {ex.outstation_code} to {ex.hub_code}</h2>
          {ex.return_id ? (
            <>
              <p className="text-sm"><Link href={`/transfers/${ex.return_id}`} className="id-code text-(--color-primary) hover:underline">{ex.return_number}</Link>{" "}
                <TransferStatusBadge status={ex.return_status as TransferStatus} /></p>
              {ex.return_flight && <p className="text-sm text-(--steel)">Flight {ex.return_flight}, {fmt(ex.return_flight_date)}</p>}
              <Progress status={ex.return_status} />
            </>
          ) : (
            <p className="text-sm text-(--steel)">{ex.status === "CLOSED_NO_RETURN" ? "No return, by approved exception." : "Not recorded yet. The exchange is not complete until the return is received and reconciled."}</p>
          )}
        </section>
      </div>

      <ExchangePanel ex={ex} perms={[...perms]} userId={userId} />
    </div>
  );
}
