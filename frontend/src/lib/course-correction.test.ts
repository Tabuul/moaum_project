import { test } from "node:test";
import assert from "node:assert/strict";
import { REASONS, impactLines, impactSentence, readyToReview, reasonText, type CorrectionCheck, type CourseImpact } from "./course-correction.ts";

const NONE: CourseImpact = {
  registrations: 0, currentRegistrations: 0, currentSession: "2026/2027", students: 0, carryOvers: 0, results: 0, publishedResults: 0, scoreSheets: 0,
  classes: 0, lecturerAllocations: 0, programmeBindings: 0, programmes: 0, cbtExams: 0, questions: 0, deferred: 0, oldPortalResults: 0,
  broadsheetOmissions: 0, pastClasses: 0, pastClassesOtherTitle: 0, generalOffice: null, changes: 0,
};

const check = (patch: Partial<CorrectionCheck> = {}): CorrectionCheck => ({
  id: "0190a1b2-0000-7000-8000-000000000001", code: "CSC 401", shown: "CSC 401", title: "Operating System", version: "v1",
  newCode: "CSC 401", newTitle: "Operating Systems", key: "CSC 401", codeChanged: false, titleChanged: true, separate: false,
  generalOffice: null, refusal: null, sameCode: [], sameTitle: [], impact: NONE, may: { code: true, title: true }, ...patch,
});

test("the University's ten reasons, Other last", () => {
  assert.equal(REASONS.length, 10);
  assert.equal(REASONS[0][0], "OFFICIAL_CORRECTION");
  assert.equal(REASONS[9][0], "OTHER");
});

test("the impact reads each count that is not nought, and the opening sentence counts registrations and results", () => {
  assert.deepEqual(impactLines(NONE), []);
  assert.equal(impactSentence(NONE), "Nothing hangs on this course yet.");
  const i = { ...NONE, registrations: 1245, students: 1200, currentRegistrations: 40, results: 830, publishedResults: 800, scoreSheets: 6, carryOvers: 12,
    classes: 7, lecturerAllocations: 3, programmeBindings: 4, programmes: 4, cbtExams: 1, generalOffice: "gst" };
  const lines = impactLines(i);
  assert.equal(lines[0], "1,245 registrations (1,200 students), 40 in 2026/2027");
  assert.ok(lines.includes("12 carry-over registrations"));
  assert.ok(lines.includes("830 results, 800 published on 6 score sheets"));
  assert.ok(lines.includes("3 lecturer allocations"));
  assert.ok(lines.includes("4 programmes bind it (4 bindings)"));
  assert.ok(lines.includes("a GST course: its classification stays"));
  assert.equal(impactSentence(i), "This course has 1,245 registrations and 830 result records. The change shows on every one of them: they stay on the same course.");
});

test("the form is ready only with a change, a reason, Other explained, and nothing refused", () => {
  const form = { code: "CSC 401", title: "Operating Systems", reason: "", remarks: "" };
  assert.equal(readyToReview(form, null), "Checking…");
  assert.equal(readyToReview(form, check()), "Choose the reason for the change.");
  assert.equal(readyToReview({ ...form, reason: "TYPOGRAPHICAL_ERROR" }, check()), null);
  assert.equal(readyToReview({ ...form, reason: "OTHER", remarks: "x" }, check()), "Explain \"Other\" in the remarks.");
  assert.equal(readyToReview({ ...form, reason: "OTHER", remarks: "Senate minute 14" }, check()), null);
  assert.equal(readyToReview({ ...form, title: "  " }, check()), "Give the course its title.");
  // nothing typed yet is a hint, not a refusal
  assert.equal(readyToReview(form, check({ refusal: { code: "COURSE_UNCHANGED", message: "The code and the title are as they stand; nothing would change." } })), "Change the code or the title.");
  assert.equal(impactLines({ ...NONE, programmeBindings: 2, programmes: 1 })[0], "1 programme binds it (2 bindings)");
  const refused = check({ refusal: { code: "COURSE_SAME_CODE_AND_TITLE", message: "CSC 401 — Operating Systems is already a course." } });
  assert.equal(readyToReview({ ...form, reason: "TYPOGRAPHICAL_ERROR" }, refused), "CSC 401 — Operating Systems is already a course.");
  assert.equal(readyToReview({ ...form, reason: "TYPOGRAPHICAL_ERROR" }, check({ codeChanged: true, may: { code: false, title: true } })), "You may not change this course's code.");
});

test("the reason written to the audit names the reason and the remarks", () => {
  assert.equal(reasonText("TYPOGRAPHICAL_ERROR", "  title  misspelt "), "Typographical error: title misspelt");
  assert.equal(reasonText("OFFICIAL_CORRECTION", ""), "Official course correction");
});
