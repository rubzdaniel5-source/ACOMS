export const REASON_LABELS: Record<string, string> = {
  COUNT_CORRECTION: "Physical count correction",
  DATA_ENTRY_ERROR: "Data entry error",
  UNRECORDED_RECEIPT: "Receipt not recorded",
  WRITE_OFF: "Write-off",
  OTHER: "Other",
};

export const STATUS_TAG: Record<string, string> = {
  REQUESTED: "tag-amber",
  APPROVED: "tag-teal",
  REJECTED: "tag-brick",
  CANCELLED: "tag-neutral",
};
