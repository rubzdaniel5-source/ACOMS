export type TransferStatus =
  | "REQUESTED"
  | "APPROVED"
  | "DISPATCHED"
  | "IN_TRANSIT"
  | "RECEIVED"
  | "RECONCILIATION"
  | "CLOSED"
  | "REJECTED"
  | "CANCELLED"
  | "PARTIALLY_RECEIVED"
  | "DISPUTED"
  | "DISCREPANCY";

export interface Station {
  id: string;
  code: string;
  name: string;
  station_type: "HUB" | "STOCK_HOLDING" | "NO_STOCK_TURNAROUND";
}

export interface EquipmentType {
  id: string;
  source_code: string;
  name: string;
  reconciliation_tolerance: number;
}

export interface EquipmentTransfer {
  id: string;
  transfer_number: string;
  from_station_id: string;
  to_station_id: string;
  status: TransferStatus;
  requested_by: string;
  requested_at: string;
  approved_by: string | null;
  approved_at: string | null;
  cancelled_by?: string | null;
  cancelled_at?: string | null;
  cancel_reason?: string | null;
  exchange_id?: string | null;
  exchange_leg?: "OUTBOUND" | "RETURN" | null;
  flight_leg_id?: string | null;
  flight_number?: string | null;
  flight_date?: string | null;
  flight_origin_code?: string | null;
  flight_destination_code?: string | null;
  dispatched_by: string | null;
  dispatched_at: string | null;
  received_by: string | null;
  received_at: string | null;
  closed_by: string | null;
  closed_at: string | null;
  reason: string | null;
  priority: "LOW" | "NORMAL" | "HIGH" | "URGENT";
  notes: string | null;
  // Joined for display convenience
  from_station?: Station;
  to_station?: Station;
}

export interface EquipmentTransferItem {
  id: string;
  transfer_id: string;
  equipment_type_id: string;
  quantity_requested: number;
  quantity_approved: number | null;
  quantity_dispatched: number | null;
  quantity_received: number | null;
  quantity_damaged: number;
  quantity_missing: number;
  quantity_rejected: number;
  notes: string | null;
  equipment_type?: EquipmentType;
}
