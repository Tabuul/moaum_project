import { test } from "node:test";
import assert from "node:assert/strict";
import { codeProblem, impactLines, impactSentence, normalCode, reasonProblem, REASON_WORDS, type ProgrammeImpact } from "./programme-correction.ts";

test("V716: a programme code is C and five digits, spaces and case forgiven", () => {
  assert.equal(normalCode(" c 00023 "), "C00023");
  assert.equal(codeProblem("", "C00023"), "Give the programme's new code.");
  assert.match(codeProblem("X1", "C00023") ?? "", /C and five digits/);
  assert.equal(codeProblem("c00023", "C00023"), "The code is as it stands; nothing would change.");
  assert.equal(codeProblem("C00024", "C00023"), null);
});

test("V716: a reason is chosen, and Other is explained", () => {
  assert.equal(reasonProblem("", ""), "Choose the reason for the correction.");
  assert.equal(reasonProblem("OTHER", "why"), "“Other” is explained in the remarks.");
  assert.equal(reasonProblem("OTHER", "The Senate renumbered the programme"), null);
  assert.equal(reasonProblem("WRONG_CODE_ENTERED", ""), null);
  assert.equal(REASON_WORDS.JAMB_CODE_CHANGED, "JAMB code changed");
});

test("V716: the impact reads as lines, the history staying put", () => {
  const i: ProgrammeImpact = {
    students: 120, activeStudents: 118, pgApplications: 0, cceCandidates: 0, jupebApplications: 3, feeLines: 4, courseBindings: 42, specialisations: 0,
    ownedCourses: 2, transfersIn: 1, aliases: ["C00011"], jambNames: 2,
    rows: { "people.student.programme_code": 120, "finance.fee_schedule.programme_code": 4, "catalogue.course_offer.programme_code": 42, "admissions.programme_rule.programme_code": 1 },
    history: { "people.record_move.to_programme": 5 },
  };
  const lines = impactLines(i);
  assert.equal(lines[0], "120 students, 118 in study");
  assert.ok(lines.includes("3 JUPEB applications"));
  assert.ok(lines.includes("1 admission rules"));
  assert.ok(lines.includes("1 code already merged into it (C00011): they follow"));
  assert.ok(lines.includes("5 history rows stay under the old code, which keeps its name"));
  assert.match(impactSentence(i), /^120 students and every record/);
  assert.match(impactSentence({ ...i, students: 0 }), /^No student/);
  assert.deepEqual(impactLines(null), []);
});
