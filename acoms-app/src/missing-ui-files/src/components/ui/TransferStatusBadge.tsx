import type { TransferStatus } from "@/types/transfers";

const STYLES: Record<TransferStatus, string> = {
  REQUESTED: "bg-blue-50 text-blue-700 border-blue-200",
  APPROVED: "bg-indigo-50 text-indigo-700 border-indigo-200",
  DISPATCHED: "bg-amber-50 text-amber-700 border-amber-200",
  IN_TRANSIT: "bg-amber-50 text-amber-700 border-amber-200",
  RECEIVED: "bg-teal-50 text-teal-700 border-teal-200",
  RECONCILIATION: "bg-purple-50 text-purple-700 border-purple-200",
  CLOSED: "bg-slate-100 text-slate-600 border-slate-200",
  REJECTED: "bg-red-50 text-red-700 border-red-200",
  CANCELLED: "bg-slate-100 text-slate-500 border-slate-200",
  PARTIALLY_RECEIVED: "bg-orange-50 text-orange-700 border-orange-200",
  DISPUTED: "bg-red-50 text-red-700 border-red-200",
  DISCREPANCY: "bg-red-50 text-red-700 border-red-200",
};

// Text labels, not color alone, per UI accessibility principle.
const LABELS: Record<TransferStatus, string> = {
  REQUESTED: "Requested",
  APPROVED: "Approved",
  DISPATCHED: "Dispatched",
  IN_TRANSIT: "In Transit",
  RECEIVED: "Received",
  RECONCILIATION: "Reconciliation",
  CLOSED: "Closed",
  REJECTED: "Rejected",
  CANCELLED: "Cancelled",
  PARTIALLY_RECEIVED: "Partially Received",
  DISPUTED: "Disputed",
  DISCREPANCY: "Discrepancy",
};

export function TransferStatusBadge({ status }: { status: TransferStatus }) {
  return (
    <span
      className={`inline-flex items-center rounded-full border px-2.5 py-0.5 text-xs font-medium ${STYLES[status]}`}
    >
      {LABELS[status]}
    </span>
  );
}
