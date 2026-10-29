import { test } from "node:test";
import assert from "node:assert/strict";
import {
  EXCEPTION_KINDS, KIND_NOTE, KIND_WORD, markWords, monitorQuery, proposalBody, proposalProblem, REASON_KINDS, REASON_WORD,
  recordCells, RECORD_HEADERS, RESULT_STATES, STATE_WORD, stageWord, type RecordRow,
} from "./result-monitor.ts";

test("V700: every state, exception and reason is said in words, and no result is never a fail", () => {
  for (const s of RESULT_STATES) assert.ok(STATE_WORD[s]);
  for (const k of EXCEPTION_KINDS) { assert.ok(KIND_WORD[k]); assert.ok(KIND_NOTE[k]); }
  for (const r of REASON_KINDS) assert.ok(REASON_WORD[r]);
  assert.equal(STATE_WORD.AWAITING, "Result not available");
  assert.match(KIND_NOTE.MISSING_SCORE, /Not a fail/);
  assert.equal(stageWord("DEPT_BOARD"), "Departmental Board");
  assert.equal(stageWord("NO_SHEET"), "No sheet yet");
  assert.equal(stageWord(null), "—");
});

test("a mark in words: components, the total and grade, an outcome, or none", () => {
  assert.equal(markWords({ ca: 25, exam: 40, total: 65, grade: "B", outcome: "GRADED" }), "CA 25 · Exam 40 · 65 (B)");
  assert.equal(markWords({ ca: 25, exam: 50 }), "CA 25 · Exam 50 · 75");
  assert.equal(markWords({ total: 58, grade: "C", outcome: "GRADED" }), "58 (C)");
  assert.equal(markWords({ outcome: "ABSENT" }), "Absent");
  assert.equal(markWords(null), "No mark");
});

test("a correction request says what stops it before it goes, as the server would", () => {
  const p = { reasonKind: "INCORRECT_SCORE" as const, note: "The exam was 50, not 40, on the script", ca: "25", exam: "50", outcome: "" };
  assert.equal(proposalProblem(p, { ca: 25, exam: 40, outcome: "GRADED" }), null);
  assert.equal(proposalProblem({ ...p, reasonKind: "" }, null), "Choose why the result is wrong.");
  assert.match(proposalProblem({ ...p, note: "wrong" }, null) ?? "", /ten characters/);
  assert.match(proposalProblem({ ...p, exam: "" }, null) ?? "", /together/);
  assert.match(proposalProblem({ ...p, ca: "", exam: "" }, null) ?? "", /names the marks/);
  assert.equal(proposalProblem({ ...p, reasonKind: "WRONG_STUDENT", ca: "", exam: "" }, null), null);   // removed or moved, no mark
  assert.match(proposalProblem({ ...p, ca: "50", exam: "55" }, null) ?? "", /more than 100/);
  assert.match(proposalProblem({ ...p, ca: "45", exam: "40" }, null, 40) ?? "", /out of 40/);
  assert.equal(proposalProblem(p, { ca: 25, exam: 50, outcome: "GRADED" }), "These are the marks on record.");
  assert.deepEqual(proposalBody("sh", "st", p), { sheetId: "sh", studentId: "st", reasonKind: "INCORRECT_SCORE", note: p.note, ca: 25, exam: 50, outcome: "GRADED" });
  assert.deepEqual(proposalBody("sh", "st", { ...p, reasonKind: "WRONG_COURSE", ca: "", exam: "" }),
    { sheetId: "sh", studentId: "st", reasonKind: "WRONG_COURSE", note: p.note, ca: null, exam: null, outcome: null });
});

test("the filters go as a query string, the empty ones left out", () => {
  assert.equal(monitorQuery({ session: "2025/2026", sem: 1, fac: "", dept: null, q: "ada" }), "?session=2025%2F2026&sem=1&q=ada");
  assert.equal(monitorQuery({}), "");
});

test("a record exports with every heading filled, the matric number as text", () => {
  const r: RecordRow = {
    studentId: "s", offeringId: "o", number: "BSU/SC/CSC/23/0001", jamb: "202512345678AB", surname: "Ada", otherNames: "Bem", programmeCode: "C00023",
    programme: "B.Sc. Computer Science", department: "Mathematics and Computer Science", faculty: "Science", level: 200, courseCode: "COS 201",
    courseTitle: "Computer Programming I", units: 3, entryType: "CURRENT", state: "PUBLISHED", lecturer: "Okoro, Ann", sheetId: "sh", stage: "PUBLISHED",
    ca: 25, exam: 40, total: 65, grade: "B", points: 4, qualityPoints: 12, outcome: "GRADED", sitting: "MAIN", publishedAt: "2026-10-01T10:00:00Z",
    versions: 1, uploadedAt: "2026-09-20T10:00:00Z", lastModified: "2026-09-21T10:00:00Z", imported: false, openRequest: null, openAmendment: null,
  };
  const cells = recordCells(r);
  assert.equal(cells.length, RECORD_HEADERS.length);
  assert.equal(cells[0], "ADA, Bem");
  assert.equal(cells[1], "BSU/SC/CSC/23/0001");
  assert.equal(cells[16], "Published");
  assert.equal(cells[19], "2026-09-20");
  assert.equal(recordCells({ ...r, grade: null, outcome: "ABSENT", total: null })[13], "Absent");
});

import { duplicateCells, lateRows, resolveProblem, standing, toWithdraw, type DuplicateClass, type DuplicateRow } from "./result-monitor.ts";

const cls = (offeringId: string, courseCode: string, decision: DuplicateClass["decision"] = null): DuplicateClass => ({
  offeringId, courseCode, courseTitle: "Check Course", sheetId: "s-" + offeringId, stage: "PUBLISHED", ca: 30, exam: 50, total: 80, grade: "A",
  entryStatus: decision === "WITHDRAWN" ? "WITHDRAWN" : "APPROVED", decision, resolutionId: decision ? "r1" : null, decidedAt: null,
  decidedOffice: decision ? "records" : null, decidedReason: decision ? "The plain code stands" : null,
});

test("V702: a duplicate resolved keeps one class and withdraws every other one standing", () => {
  const two = [cls("o1", "CMS 101"), cls("o2", "BSU-CMS 101")];
  assert.deepEqual(toWithdraw("o1", two).map((c) => c.offeringId), ["o2"]);
  assert.equal(resolveProblem("o1", two, "short"), "Say why this course stands, in ten characters or more.");
  assert.equal(resolveProblem("", two, "The plain code stands"), "Choose the course that stands.");
  assert.equal(resolveProblem("o1", two, "The plain code stands"), null);
  const three = [cls("o1", "CMS 101"), cls("o2", "BSU-CMS 101", "WITHDRAWN"), cls("o3", "MOAU-CMS 101")];
  assert.deepEqual(toWithdraw("o1", three).map((c) => c.offeringId), ["o3"]);
  assert.equal(standing(three).length, 2);
  assert.match(resolveProblem("o2", three, "The plain code stands") ?? "", /withdrawn already/);
  const done = [cls("o1", "CMS 101", "KEPT"), cls("o2", "BSU-CMS 101", "WITHDRAWN")];
  assert.equal(resolveProblem("o1", done, "The plain code stands"), "Nothing else stands beside it.");
  const row: DuplicateRow = { studentId: "s", number: "BSU/SC/CMS/23/1", studentName: "ADE, Bola", programmeCode: "C00023", level: 100, baseCode: "CMS 101", resolved: true, classes: done };
  const cells = duplicateCells(row);
  assert.equal(cells.length, 2);
  assert.deepEqual(cells[1].slice(5, 11), ["BSU-CMS 101", "Check Course", "CA 30 · Exam 50 · 80 (A)", "Published", "WITHDRAWN", "Withdrawn from the registration"]);
});

test("V702: late results read from an uploaded sheet — the heading row, the marks, an outcome, blank rows passed over", () => {
  const ok = lateRows([["Course: CMS 101"], ["S/N", "Matric No.", "Name", "CA", "Exam", "Outcome"], ["1", "BSU/SC/CMS/23/1", "Ade", "20", "45", ""],
    ["", "", "", "", "", ""], ["2", "BSU/SC/CMS/23/2", "Bola", "", "", "absent"]]);
  assert.equal(ok.problem, null);
  assert.deepEqual(ok.rows, [{ number: "BSU/SC/CMS/23/1", ca: 20, exam: 45, outcome: null }, { number: "BSU/SC/CMS/23/2", ca: null, exam: null, outcome: "ABSENT" }]);
  assert.match(lateRows([["Name", "CA", "Exam"]]).problem ?? "", /Matric No\./);
  assert.match(lateRows([["Matric No.", "Total"]]).problem ?? "", /CA column/);
  assert.match(lateRows([["Matric No.", "CA", "Exam"], ["X/1", "twenty", "40"]]).problem ?? "", /not a number/);
  assert.match(lateRows([["Matric No.", "CA", "Exam", "Remark"], ["X/1", "", "", "sick"]]).problem ?? "", /outcome is one of/);
  assert.match(lateRows([["Matric No.", "CA", "Exam"]]).problem ?? "", /no rows/);
});
