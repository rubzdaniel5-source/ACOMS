import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { requireAnyPermission } from "@/features/admin/access";
import { getCurrentUserId } from "@/features/auth/permissions";
import { REASON_LABELS, STATUS_TAG } from "@/features/admin/adjustments";
import { DecisionPanel } from "./DecisionPanel";

export default async function AdjustmentDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const perms = await requireAnyPermission(["request_adjustment", "approve_adjustment"]);
  const me = await getCurrentUserId();
  const supabase = await createClient();
  const { data } = await supabase.from("v_stock_adjustments").select("*").eq("id", id).maybeSingle();
  const a = data as any;
  if (!a) notFound();

  const pending = a.status === "REQUESTED";
  const mine = a.requested_by === me;
  const dt = (s: string) => new Date(s).toLocaleString("en-GB", { dateStyle: "medium", timeStyle: "short" });

  return (
    <div className="max-w-2xl">
      <Link href="/admin/adjustments" className="mb-4 inline-block text-sm text-(--steel) hover:text-(--navy)">← Back to adjustments</Link>
      <div className="mb-4 flex items-center gap-3">
        <h1 className="id-code text-xl font-semibold text-(--navy)">{a.adjustment_number}</h1>
        <span className={`tag ${STATUS_TAG[a.status]}`}>{a.status.toLowerCase()}</span>
      </div>

      <dl className="panel grid gap-4 p-5 text-sm sm:grid-cols-2">
        <div><dt className="text-xs text-(--steel)">Station</dt><dd className="id-code">{a.station_code}</dd></div>
        <div><dt className="text-xs text-(--steel)">Equipment</dt><dd>{a.equipment_name} <span className="id-code text-(--steel)">{a.source_code}</span></dd></div>
        <div><dt className="text-xs text-(--steel)">Change</dt>
          <dd className={`text-lg font-semibold ${a.direction === "INCREASE" ? "text-(--teal)" : "text-(--brick)"}`}>{a.direction === "INCREASE" ? "+" : "−"}{a.quantity}</dd></div>
        <div><dt className="text-xs text-(--steel)">Reason</dt><dd>{REASON_LABELS[a.reason_code]}</dd></div>
        <div className="sm:col-span-2"><dt className="text-xs text-(--steel)">Explanation</dt><dd>{a.notes}</dd></div>
        <div><dt className="text-xs text-(--steel)">Requested by</dt><dd>{a.requested_by_name}<div className="text-xs text-(--steel)">{dt(a.requested_at)}</div></dd></div>
        {a.decided_at && (
          <div><dt className="text-xs text-(--steel)">{a.status === "CANCELLED" ? "Cancelled" : a.status === "APPROVED" ? "Approved by" : "Rejected by"}</dt>
            <dd>{a.decided_by_name ?? "Requester"}<div className="text-xs text-(--steel)">{dt(a.decided_at)}</div></dd></div>
        )}
        {a.decision_note && <div className="sm:col-span-2"><dt className="text-xs text-(--steel)">Decision note</dt><dd>{a.decision_note}</dd></div>}
        {a.status === "APPROVED" && (
          <div className="sm:col-span-2"><dt className="text-xs text-(--steel)">Available stock</dt><dd>{a.balance_before} → <strong>{a.balance_after}</strong></dd></div>
        )}
      </dl>

      {pending && (
        <DecisionPanel id={id} canApprove={perms.has("approve_adjustment") && !mine} isMine={mine} />
      )}
    </div>
  );
}
