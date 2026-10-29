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
