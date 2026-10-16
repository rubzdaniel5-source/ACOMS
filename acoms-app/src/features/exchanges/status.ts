export const EXCHANGE_STATUS_LABEL: Record<string, string> = {
  OUTBOUND: "Outbound in progress",
  OUTBOUND_RECONCILIATION: "Reconciling outbound",
  AWAITING_RETURN: "Awaiting return",
  RETURN_IN_PROGRESS: "Return in progress",
  READY_TO_CLOSE: "Ready to close",
  CLOSED: "Closed",
  CLOSED_NO_RETURN: "Closed without return",
  CANCELLED: "Cancelled",
};

export const EXCHANGE_STATUS_TAG: Record<string, string> = {
  OUTBOUND: "tag-navy",
  OUTBOUND_RECONCILIATION: "tag-navy",
  AWAITING_RETURN: "tag-amber",
  RETURN_IN_PROGRESS: "tag-navy",
  READY_TO_CLOSE: "tag-teal",
  CLOSED: "tag-teal",
  CLOSED_NO_RETURN: "tag-neutral",
  CANCELLED: "tag-neutral",
};

export type ExchangeRow = {
  id: string; exchange_number: string; status: string; next_action: string | null; next_station_code: string | null;
  hub_code: string; outstation_code: string; hub_station_id: string; outstation_id: string;
  return_required: boolean; created_at: string; closed_at: string | null; close_kind: string | null; close_note: string | null;
  no_return_requested_by: string | null; no_return_pending: boolean; no_return_reason: string | null; no_return_decision: string | null; no_return_decision_note: string | null;
  outbound_id: string | null; outbound_number: string | null; outbound_status: string | null; outbound_flight: string | null; outbound_flight_date: string | null;
  return_id: string | null; return_number: string | null; return_status: string | null; return_flight: string | null; return_flight_date: string | null;
  has_open_discrepancy: boolean;
};

// Progress steps shown for each movement leg.
export const LEG_STEPS = ["REQUESTED", "APPROVED", "IN_TRANSIT", "RECEIVED", "RECONCILIATION", "CLOSED"] as const;
export const LEG_STEP_LABEL: Record<string, string> = {
  REQUESTED: "Requested", APPROVED: "Approved", IN_TRANSIT: "Dispatched", RECEIVED: "Received", RECONCILIATION: "Reconciliation", CLOSED: "Closed",
};
// DISCREPANCY sits at the reconciliation step.
export function legStepIndex(status: string | null): number {
  if (!status) return -1;
  if (status === "DISCREPANCY") return LEG_STEPS.indexOf("RECONCILIATION");
  return LEG_STEPS.indexOf(status as (typeof LEG_STEPS)[number]);
}
