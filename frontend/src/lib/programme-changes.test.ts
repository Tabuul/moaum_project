import { test } from "node:test";
import assert from "node:assert/strict";
import { EXPORT_HEAD, NO_FILTER, admissionWord, exportBody, feeFollowUp, feeWord, filterRows, lagosDay, parseHistory, stageWord, tally, type RegisterRow } from "./programme-changes.ts";

function row(over: Partial<RegisterRow>): RegisterRow {
  return {
    application_id: "a1", application_no: "APP/26/000001", jamb_reg_no: "20261234567AB", surname: "ADA", other_names: "Obi", entry_mode: "UTME",
    applied_code: "C00023", applied_programme: "B.Sc. COMPUTER SCIENCE", applied_faculty: "Science",
    current_code: "C00019", current_programme: "B.Sc. ACCOUNTING", current_faculty: "Management Sciences",
    moved: true, changes: 1, change_id: "q1", kind: "CHANGE", stage: "SCREENING", reason_code: "OLEVEL_NOT_MET", reason: "O'Level requirement not satisfied",
    decided_at: "2026-09-29T23:30:00Z", decided_office: "academic", recommended_office: "academic", stage_now: "SCHOOL_FEES_PAID",
    ...over,
  };
}

test("the day an approval falls on is Lagos's, not UTC's", () => {
  assert.equal(lagosDay("2026-09-29T23:30:00Z"), "2026-09-30");   // 00:30 in Lagos
  assert.equal(lagosDay("2026-09-29T10:00:00+01:00"), "2026-09-29");
  assert.equal(lagosDay(null), "");
  assert.equal(lagosDay("not a date"), "");
});

test("the fee position a correction recorded reads as paid, due and the balance or the excess", () => {
  assert.equal(feeWord({ fees_paid: 150000, fees_due_after: 120000 }), "Paid ₦150,000 · due ₦120,000 · excess ₦30,000");
  assert.equal(feeWord({ fees_paid: 100000, fees_due_after: 120000 }), "Paid ₦100,000 · due ₦120,000 · balance ₦20,000");
  assert.equal(feeWord({ fees_paid: 120000, fees_due_after: 120000 }), "Paid ₦120,000 · due ₦120,000 · settled");
  assert.equal(feeWord({}), "");   // an ordinary change records none — the API leaves the fields out
});

test("the Bursary follows up a correction's excess or balance today, and nothing else", () => {
  assert.equal(feeFollowUp(row({ kind: "CORRECTION", fees_paid: 150000, paid_now: 150000, due_now: 120000 })), "EXCESS");
  assert.equal(feeFollowUp(row({ kind: "CORRECTION", fees_paid: 100000, paid_now: 100000, due_now: 120000 })), "BALANCE");
  assert.equal(feeFollowUp(row({ kind: "CORRECTION", fees_paid: 120000, paid_now: 120000, due_now: 120000 })), null);
  assert.equal(feeFollowUp(row({ kind: "CORRECTION", fees_paid: 0, paid_now: 0, due_now: 120000 })), null);   // nothing paid: the ordinary fees journey
  assert.equal(feeFollowUp(row({ kind: "CHANGE", paid_now: 150000, due_now: 120000 })), null);
});

test("the filters narrow by stage, reason, faculty, programme applied for, the dates and the words", () => {
  const rows = [
    row({ application_id: "1" }),
    row({ application_id: "2", stage: "CORRECTION", kind: "CORRECTION", reason_code: "ADMISSION_ERROR", reason: "Error discovered in the admission", note: "mis-keyed score", decided_at: "2026-10-05T09:00:00Z" }),
    row({ application_id: "3", stage: "BEFORE_DECISION", applied_code: "C00061", applied_programme: "MBBS", current_faculty: "Science", surname: "BELLO" }),
  ];
  assert.deepEqual(filterRows(rows, NO_FILTER).map((r) => r.application_id), ["1", "2", "3"]);
  assert.deepEqual(filterRows(rows, { ...NO_FILTER, stage: "CORRECTION" }).map((r) => r.application_id), ["2"]);
  assert.deepEqual(filterRows(rows, { ...NO_FILTER, reason: "OLEVEL_NOT_MET" }).map((r) => r.application_id), ["1", "3"]);
  assert.deepEqual(filterRows(rows, { ...NO_FILTER, faculty: "Science" }).map((r) => r.application_id), ["3"]);
  assert.deepEqual(filterRows(rows, { ...NO_FILTER, applied: "C00061" }).map((r) => r.application_id), ["3"]);
  assert.deepEqual(filterRows(rows, { ...NO_FILTER, from: "2026-10-01" }).map((r) => r.application_id), ["2"]);
  assert.deepEqual(filterRows(rows, { ...NO_FILTER, to: "2026-09-30" }).map((r) => r.application_id), ["1", "3"]);
  assert.deepEqual(filterRows(rows, { ...NO_FILTER, q: "mis-KEYED" }).map((r) => r.application_id), ["2"]);
  assert.deepEqual(filterRows(rows, { ...NO_FILTER, q: "bello" }).map((r) => r.application_id), ["3"]);
});

test("the tiles count the applicants moved at each stage and the corrections the Bursary still follows", () => {
  const t = tally([row({}), row({ stage: "APPLICANT_REQUEST" }), row({ stage: "BEFORE_DECISION", override: true }),
    row({ stage: "CORRECTION", kind: "CORRECTION", fees_paid: 150000, paid_now: 150000, due_now: 120000 })]);
  assert.deepEqual(t, { applicants: 4, beforeDecision: 2, screening: 1, corrections: 1, overrides: 1, followUp: 1 });
});

test("the export has a column for every heading, S/N first, the words the screen uses", () => {
  const body = exportBody([row({}), row({ stage: "CORRECTION", kind: "CORRECTION", fees_paid: 150000, fees_due_after: 120000, recommended_by: "OKON, Ita", decided_office: "registrar", decided_by: "ADAMU, Grace" })]);
  assert.equal(body.length, 2);
  for (const r of body) assert.equal(r.length, EXPORT_HEAD.length);
  assert.equal(body[0][0], 1);
  assert.equal(body[1][10], "Admission correction");
  assert.equal(body[1][11], "Academic Office · OKON, Ita");
  assert.equal(body[1][12], "Registrar · ADAMU, Grace");
  assert.equal(body[1][15], "Paid ₦150,000 · due ₦120,000 · excess ₦30,000");
  assert.equal(body[0][14], "School fees paid");
});

test("the history is read whatever arrives, and the words fall back to the code", () => {
  assert.equal(parseHistory('[{"id":"x","kind":"CORRECTION","stage":"CORRECTION","from":"A","to":"B"}]')[0].to, "B");
  assert.deepEqual(parseHistory("not json"), []);
  assert.deepEqual(parseHistory('{"a":1}'), []);
  assert.deepEqual(parseHistory(undefined), []);
  assert.equal(stageWord("SCREENING"), "At screening");
  assert.equal(stageWord("SOMETHING_NEW"), "something new");
  assert.equal(admissionWord("MATRICULATED"), "Matriculated");
  assert.equal(admissionWord(null), "—");
});
