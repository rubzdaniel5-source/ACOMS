import { test } from "node:test";
import assert from "node:assert/strict";
import { buildAlerts } from "../src/features/dashboard/alerts.ts";

type Sources = Parameters<typeof buildAlerts>[0]["sources"];
const ok = (data: unknown[]) => ({ data, error: null });
const hoursAgo = (h: number) => new Date(Date.now() - h * 36e5).toISOString();

function sources(p: { overdue?: unknown[]; adjustments?: unknown[]; exceptions?: unknown[] } = {}): Sources {
  return {
    overdue: ok(p.overdue ?? []), adjustments: ok(p.adjustments ?? []), exceptions: ok(p.exceptions ?? []),
    stations: ok([{ id: "s-ebb", code: "EBB" }, { id: "s-abj", code: "ABJ" }]),
  } as unknown as Sources;
}
const inv = (over: Record<string, unknown>) => ({
  station_id: "s-abj", station_code: "ABJ", source_code: "C058", equipment_name: "Cutlery",
  current_stock: 3, minimum_level: 20, status: "CRITICAL_SHORTAGE", ...over,
});
const build = (o: { invRows?: any[]; sources?: Sources; perms?: string[]; userId?: string | null }) =>
  buildAlerts({ invRows: o.invRows ?? [], sources: o.sources ?? sources(), perms: new Set(o.perms ?? []), userId: o.userId ?? "me" });

test("only critical shortage and critical surplus become stock alerts", () => {
  const a = build({ invRows: [
    inv({ status: "CRITICAL_SHORTAGE" }), inv({ status: "CRITICAL_SURPLUS", source_code: "C2" }),
    inv({ status: "SHORTAGE", source_code: "C3" }), inv({ status: "HEALTHY", source_code: "C4" }), inv({ status: "SURPLUS", source_code: "C5" }),
  ] });
  assert.equal(a.length, 2);
  assert.deepEqual(a.map((x) => x.label).sort(), ["Critical shortage", "Critical surplus"]);
});

test("severity order: critical, then warning, then attention", () => {
  const a = build({
    perms: ["approve_adjustment"],
    invRows: [inv({ status: "CRITICAL_SURPLUS", source_code: "S" })],
    sources: sources({
      adjustments: [{ id: "a1", adjustment_number: "ADJ-1", station_code: "EBB", source_code: "C1", direction: "INCREASE", quantity: 2, requested_at: hoursAgo(5), requested_by: "other" }],
      exceptions: [{ id: "t1", exception_type: "TRANSFER_DISCREPANCY", station_id: "s-abj", reference: "TR-1", updated_at: hoursAgo(1) }],
    }),
  });
  assert.deepEqual(a.map((x) => x.severity), ["critical", "warning", "attention"]);
});

test("within a severity, kinds follow the documented order", () => {
  const a = build({
    invRows: [inv({ status: "CRITICAL_SURPLUS", source_code: "S" })],
    sources: sources({
      exceptions: [
        { id: "d1", exception_type: "DAMAGE_PENDING", station_id: "s-abj", reference: "DR-1", updated_at: hoursAgo(1) },
        { id: "l1", exception_type: "LOSS_PENDING", station_id: "s-abj", reference: "LR-1", updated_at: hoursAgo(1) },
      ],
      overdue: [{ id: "o1", transfer_number: "TR-9", from_station_code: "EBB", to_station_code: "ABJ", hours_since_requested: 400, overdue_kind: "OPEN", hours_in_status: 400 }],
    }),
  });
  assert.deepEqual(a.map((x) => x.label), ["Overdue transfer", "Open loss report", "Critical surplus", "Open damage report"]);
});

test("within a kind, the most urgent comes first", () => {
  const a = build({ invRows: [
    inv({ source_code: "A", current_stock: 15 }), inv({ source_code: "B", current_stock: 1 }), inv({ source_code: "C", current_stock: 9 }),
  ] });
  assert.deepEqual(a.map((x) => x.reference), ["B", "C", "A"]);
});

test("a stuck reconciliation is labelled and described by how long it has waited", () => {
  const a = build({ sources: sources({ overdue: [
    { id: "r1", transfer_number: "TR-5", from_station_code: "EBB", to_station_code: "ABJ", hours_since_requested: 500, overdue_kind: "RECONCILE", hours_in_status: 100 },
    { id: "c1", transfer_number: "TR-6", from_station_code: "EBB", to_station_code: "ABJ", hours_since_requested: 500, overdue_kind: "CLOSE", hours_in_status: 30 },
    { id: "p1", transfer_number: "TR-7", from_station_code: "EBB", to_station_code: "ABJ", hours_since_requested: 60, overdue_kind: "APPROVAL", hours_in_status: 60 },
  ] }) });
  const by = Object.fromEntries(a.map((x) => [x.reference, x]));
  assert.equal(by["TR-5"].label, "Reconciliation overdue");
  assert.match(by["TR-5"].detail, /Received but not reconciled for 4 days/);
  assert.equal(by["TR-5"].station, "ABJ");
  assert.match(by["TR-6"].detail, /Reconciled but not closed for 1 day\./);
  assert.equal(by["TR-7"].label, "Overdue transfer");
  assert.equal(by["TR-7"].station, "EBB");
  assert.match(by["TR-7"].detail, /Waiting for approval for 2 days/);
});

test("you never get an alert to approve your own adjustment", () => {
  const adj = (id: string, by: string) => ({ id, adjustment_number: id, station_code: "EBB", source_code: "C1", direction: "DECREASE", quantity: 3, requested_at: hoursAgo(2), requested_by: by });
  const a = build({ perms: ["approve_adjustment"], userId: "me", sources: sources({ adjustments: [adj("mine", "me"), adj("theirs", "someone")] }) });
  assert.deepEqual(a.map((x) => x.reference), ["theirs"]);
});

test("transfer actions only appear for people who can create transfers", () => {
  const rows = [inv({})];
  assert.equal(build({ invRows: rows, perms: [] })[0].actions.length, 0);
  assert.equal(build({ invRows: rows, perms: ["create_transfer"] })[0].actions[0].label, "Request transfer");
});

test("keys are unique so the list renders without duplicates", () => {
  const a = build({ invRows: [inv({ source_code: "A" }), inv({ source_code: "B" }), inv({ station_id: "s-ebb", station_code: "EBB", source_code: "A" })] });
  assert.equal(new Set(a.map((x) => x.key)).size, a.length);
});

test("failed or empty sources produce no alerts and no crash", () => {
  const empty = { overdue: { data: null }, adjustments: { data: null }, exceptions: { data: null }, stations: { data: null } } as unknown as Sources;
  assert.deepEqual(build({ sources: empty }), []);
});

test("an item marked alert-on-any-shortage alerts when only one unit under the station level", () => {
  const trolley = inv({ source_code: "R052", equipment_name: "Atlas Trolleys FS", status: "SHORTAGE", current_stock: 9, minimum_level: 10, alert_on_any_shortage: true });
  const a = build({ invRows: [trolley], perms: ["create_transfer"] });
  assert.equal(a.length, 1);
  assert.equal(a[0].label, "Below required level");
  assert.match(a[0].detail, /9 available, required 10\. 1 short/);
  assert.equal(a[0].severity, "warning");
});

test("an ordinary item with a plain shortage still does not alert", () => {
  assert.equal(build({ invRows: [inv({ status: "SHORTAGE", alert_on_any_shortage: false })] }).length, 0);
  assert.equal(build({ invRows: [inv({ status: "SHORTAGE" })] }).length, 0);
});

test("a trolley at its required level does not alert", () => {
  assert.equal(build({ invRows: [inv({ status: "NORMAL", current_stock: 10, minimum_level: 10, alert_on_any_shortage: true })] }).length, 0);
});

test("a critical trolley shortage is still critical and appears once", () => {
  const a = build({ invRows: [inv({ status: "CRITICAL_SHORTAGE", alert_on_any_shortage: true })] });
  assert.equal(a.length, 1);
  assert.equal(a[0].severity, "critical");
});
