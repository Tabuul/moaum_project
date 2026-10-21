import { test } from "node:test";
import assert from "node:assert/strict";
import { batchPath, batchState, confirmWords, outcomeWord, tally, verdictKind, verdictWord } from "./graduation-batch.ts";

test("verdicts read in words, and the tally keeps the eligible, the review and the rest apart (V602)", () => {
  assert.equal(verdictWord("CARRY_OVER"), "Carry-over owed");
  assert.equal(verdictKind("CARRY_OVER"), "bad");
  assert.equal(verdictWord("SOMETHING_NEW"), "Something new");
  const t = tally([{ verdict: "ELIGIBLE" }, { verdict: "ELIGIBLE" }, { verdict: "REQUIRES_REVIEW" }, { verdict: "ALREADY_GRADUATED" }, { verdict: "DEFERRED" }]);
  assert.deepEqual([t.selected, t.eligible, t.review, t.alreadyGraduated, t.notEligible], [5, 2, 1, 1, 1]);
  assert.equal(t.byVerdict[0][0], "ELIGIBLE");
  assert.match(confirmWords(t, "2025/2026"), /confirm the award of 2 students for 2025\/2026/);
  assert.match(confirmWords(t, "2025/2026"), /3 of the 5 chosen are left out \(1 requiring review, 1 already graduated, 1 not eligible\)/);
  assert.match(confirmWords(tally([{ verdict: "DEFERRED" }]), "2025/2026"), /nothing will be graduated/);
});

test("outcomes, batch references and the batch's standing", () => {
  assert.deepEqual(outcomeWord({ outcome: "GRADUATED", verdict: "ELIGIBLE", reason: null }), ["Graduated", "ok"]);
  assert.deepEqual(outcomeWord({ outcome: "REFUSED", verdict: "ELIGIBLE", reason: "GRAD_CARRY_OVER: a carry-over is still owed: GST 101" }), ["Refused — GRAD_CARRY_OVER: a carry-over is still owed: GST 101", "bad"]);
  assert.deepEqual(outcomeWord({ outcome: null, verdict: "ELIGIBLE", reason: null }), ["Waiting", "warn"]);
  assert.deepEqual(outcomeWord({ outcome: null, verdict: "DEFERRED", reason: null }), ["Deferred", "info"]);
  assert.equal(batchPath("GRAD/2026/000012"), "2026/000012");
  assert.equal(batchPath("RECON/2026/000012"), null);
  assert.deepEqual(batchState({ closed_at: null, executed_at: null, waiting: 3, eligible: 3 }), ["Opened", "warn"]);
  assert.deepEqual(batchState({ closed_at: null, executed_at: null, waiting: 1, eligible: 3 }), ["In progress", "warn"]);
  assert.deepEqual(batchState({ closed_at: null, executed_at: "2026-10-21", waiting: 0, eligible: 3 }), ["Executed", "ok"]);
  assert.deepEqual(batchState({ closed_at: "2026-10-21", executed_at: "2026-10-21", waiting: 0, eligible: 3 }), ["Closed", "info"]);
});
