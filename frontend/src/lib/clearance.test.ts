import { test } from "node:test";
import assert from "node:assert/strict";
import { clearanceVerifyPath, stateKind, stateMark, stateWord, studentNumber } from "./clearance.ts";

test("a stage's word reads as a person says it, and a hostel the student never had reads as not required", () => {
  assert.equal(stateWord("NOT_APPLICABLE"), "Not required");
  assert.equal(stateWord("REQUIRES_ACTION"), "Requires action");
  assert.equal(stateWord("PENDING_ACTION"), "Requires action");
  assert.equal(stateWord("COMPLETED"), "Completed");
  assert.equal(stateWord(null), "—");
});

test("the colour of a word: cleared green, held red, asked amber, not required grey", () => {
  assert.equal(stateKind("CLEARED"), "ok");
  assert.equal(stateKind("REJECTED"), "bad");
  assert.equal(stateKind("REQUIRES_ACTION"), "warn");
  assert.equal(stateKind("NOT_APPLICABLE"), "grey");
  assert.equal(stateMark("NOT_APPLICABLE"), "—");
  assert.equal(stateMark("CLEARED"), "✓");
});

test("the certificate's QR names the reference and its check code; the number shown prefers the matric", () => {
  assert.equal(clearanceVerifyPath("FCLR/2026/000012", "a1b2c3"), "/verify/clearance/FCLR/2026/000012?c=a1b2c3");
  assert.equal(studentNumber({ matric_no: null, admission_no: "MOAUM/ADM/26/000001" }), "MOAUM/ADM/26/000001");
  assert.equal(studentNumber({ matric_no: "MOAUM/SCI/26/0001", admission_no: "X" }), "MOAUM/SCI/26/0001");
});

// V665: the Bursary's own CLEARED on a final clearance of an approved award graduates the student, so the desk asks first
test("the word that graduates: the Bursary's own clearance of an approved award, never an override or another office's", async () => {
  const { graduatesOnClear } = await import("./clearance.ts");
  const fc = { finalCheck: { graduates: true } as never };
  assert.equal(graduatesOnClear(fc, "BURSARY", "CLEARED", false), true);
  assert.equal(graduatesOnClear(fc, "BURSARY", "CLEARED", true), false);
  assert.equal(graduatesOnClear(fc, "BURSARY", "NOT_CLEARED", false), false);
  assert.equal(graduatesOnClear(fc, "LIBRARY", "CLEARED", false), false);
  assert.equal(graduatesOnClear({ finalCheck: { graduates: false } as never }, "BURSARY", "CLEARED", false), false);
  assert.equal(graduatesOnClear({}, "BURSARY", "CLEARED", false), false);
});

// V668: the student's own words for where the final clearance stands
test("the final clearance in the student's words: graduated, owing, being assessed, or under way", async () => {
  const { finalWords } = await import("./clearance.ts");
  const base = { awaiting: true, graduated: false, status: "ACTIVE", award: "B.Sc.", minute: "SEN/1", awardSession: "2025/2026", basis: "SENATE", process: "p", reference: "FCLR/2026/000001",
    othersPending: [], bursaryState: "PENDING", assessed: 100000, paid: 100000, waived: 0, outstanding: 0, beingAssessed: 0, owing: [], onlinePayment: true };
  assert.equal(finalWords({ ...base, graduated: true }).title, "You have graduated");
  const owing = finalWords({ ...base, outstanding: 25000, othersPending: [{ unit: "LIBRARY", label: "Library", state: "PENDING" }] });
  assert.equal(owing.kind, "bad");
  assert.match(owing.body, /^Still to clear you: Library\. /);
  assert.equal(finalWords({ ...base, beingAssessed: 1 }).title, "The Bursary is assessing a past semester");
  assert.match(finalWords(base).body, /^Every other office has cleared you\. The Bursary clears you last/);
});
