import type { TransferStatus } from "@/types/transfers";

// Color meaning is reserved and consistent across the whole app:
// navy = normal in-progress step, amber = needs attention, teal = resolved
// cleanly, brick = exception/problem. Never decorative.
const TAG_CLASS: Record<TransferStatus, string> = {
  REQUESTED: "tag-navy",
  APPROVED: "tag-navy",
  DISPATCHED: "tag-amber",
  IN_TRANSIT: "tag-amber",
  RECEIVED: "tag-navy",
  RECONCILIATION: "tag-navy",
  CLOSED: "tag-teal",
  REJECTED: "tag-brick",
  CANCELLED: "tag-neutral",
  PARTIALLY_RECEIVED: "tag-amber",
  DISPUTED: "tag-brick",
  DISCREPANCY: "tag-brick",
};

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
  return <span className={`tag ${TAG_CLASS[status]}`}>{LABELS[status]}</span>;
}
