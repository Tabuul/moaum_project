import { test } from "node:test";
import assert from "node:assert/strict";
import { freedSummary, inQueue, refusalWords, type Freed } from "./transfer-queue.ts";

const row = (outcome: Freed["outcome"], detail: string | null = null): Freed => ({
  application_id: "a", student_id: "s", matric_no: "M", name: "N", from_programme: "A", to_programme: "B", to_level: 200, outcome, swap_ref: null, detail,
});

test("an application is in the queue until it is effected, declined or withdrawn", () => {
  assert.deepEqual(["APPLIED", "FROM_OK", "TO_OK", "REG_OK", "APPROVED", "RECOMMENDED"].map(inQueue), [true, true, true, true, true, true]);
  assert.deepEqual(["EFFECTED", "DECLINED", "WITHDRAWN", "NOT_RECOMMENDED"].map(inQueue), [false, false, false, false]);
});

test("what freeing came to, and a refusal's words", () => {
  assert.equal(freedSummary([row("MOVED"), row("MOVED"), row("RECORDED"), row("REFUSED")]),
    "2 moved to the programme applied for · 1 already on it (recorded) · 1 not freed — see the reason");
  assert.equal(freedSummary([row("MOVED")]), "1 moved to the programme applied for");
  assert.equal(refusalWords("PTQ_NOT_QUEUED: the application is effected, not in the queue"), "the application is effected, not in the queue");
  assert.equal(refusalWords("plain words"), "plain words");
  assert.equal(refusalWords(null), "");
});
