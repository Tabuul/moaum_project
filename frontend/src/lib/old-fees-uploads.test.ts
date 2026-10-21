import { test } from "node:test";
import assert from "node:assert/strict";
import { addTotals, mayDecide, mayWithdraw, STATE_WORD } from "./old-fees-uploads.ts";

test("the checked parts' totals add up, the duplicate sample kept to fifty", () => {
  const a = addTotals({}, { rows: 500, cleared: 480, no_student: 20, duplicate_sample: Array.from({ length: 40 }, (_, i) => `A${i}`) });
  const b = addTotals(a, { rows: 3, cleared: 2, duplicates: 1, duplicate_sample: Array.from({ length: 20 }, (_, i) => `B${i}`) });
  assert.equal(b.rows, 503);
  assert.equal(b.cleared, 482);
  assert.equal(b.no_student, 20);
  assert.equal(b.duplicates, 1);
  assert.equal(b.duplicate_sample?.length, 50);
  assert.equal(b.duplicate_sample?.[49], "B9");
});

test("the Bursar decides an upload waiting or being loaded; the officer withdraws one not yet decided", () => {
  assert.equal(mayDecide("bursar", { state: "PENDING" }), true);
  assert.equal(mayDecide("bursar", { state: "APPROVING" }), true);
  assert.equal(mayDecide("bursar", { state: "APPROVED" }), false);
  assert.equal(mayDecide("studentaccounts", { state: "PENDING" }), false);
  assert.equal(mayWithdraw("studentaccounts", { state: "PENDING" }), true);
  assert.equal(mayWithdraw("studentaccounts", { state: "APPROVING" }), false);
  assert.equal(mayWithdraw("bursar", { state: "PENDING" }), false);
  assert.equal(STATE_WORD.PENDING[0], "Waiting for the Bursar");
});
