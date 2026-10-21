import { test } from "node:test";
import assert from "node:assert/strict";
import { actionWord, changeLines, subjectWord, trailRow, valueWord, type TrailRow } from "./bursary-audit.ts";

const change = (over: Partial<TrailRow> = {}): TrailRow => ({
  at: "2026-10-21T09:00:00Z", kind: "CHANGE", person_id: "p", name: "BURSAR, Ada", office: "bursar", action: "UPDATE",
  subject_type: "finance.fee_schedule", subject_id: "s", reason: "Fees approved by Council", source_ip: "10.0.0.1",
  changes: [{ field: "amount", before: 100000, after: 120000 }], summary: { item: "School fees" }, ...over,
});

test("what was done and on which record read in words", () => {
  assert.equal(actionWord("INSERT"), "Added");
  assert.equal(actionWord("BAD_PASSWORD"), "Wrong password");
  assert.equal(actionWord("SOMETHING_NEW"), "Something new");
  assert.equal(subjectWord("finance.fee_schedule"), "Fee line");
  assert.equal(subjectWord("finance.gateway_event_log"), "Gateway event log");
});

test("an update names what changed; an added record its key facts; a sign-in nothing", () => {
  assert.deepEqual(changeLines(change()), ["amount: 100000 → 120000"]);
  assert.deepEqual(changeLines(change({ action: "INSERT", changes: null, summary: { item: "School fees", amount: 50000 } })), ["item: School fees", "amount: 50000"]);
  assert.deepEqual(changeLines(change({ kind: "SIGN_IN", action: "SIGNED_IN" })), []);
  assert.equal(valueWord(null), "—");
  assert.equal(valueWord("x".repeat(80)).length, 58);
  assert.equal(valueWord({ a: 1 }), '{"a":1}');
});

test("the Excel row follows the headers", () => {
  const row = trailRow(change(), (c) => (c === "bursar" ? "Bursar" : c ?? ""), (s) => s.slice(0, 10));
  assert.deepEqual(row, ["2026-10-21", "BURSAR, Ada", "Bursar", "Changed", "Fee line", "amount: 100000 → 120000", "Fees approved by Council", "10.0.0.1"]);
});
