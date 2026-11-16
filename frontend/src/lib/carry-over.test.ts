import { test } from "node:test";
import assert from "node:assert/strict";
import { NO_FILTER, attemptCode, attemptWord, attemptsWords, carrySummary, filterRows, groupRows, historyByCourse, levelsOf, openingView, outcomeWords, RESULT_WORD, selection, type CarryRow, type HistoryRow } from "./carry-over.ts";

const row = (code: string, level: number, sem: number, status: CarryRow["status"], extra: Partial<CarryRow> = {}): CarryRow => ({
  course_id: `id-${code}`, course_code: code, shown_code: code, title: `Title ${code}`, units: 3, level, course_semester: sem, both_semesters: false,
  course_group: code.startsWith("GST") ? "GST" : "OTHER", status, origin_session: null, origin_semester: null, last_grade: null, offering_id: null,
  selectable: ["OUTSTANDING", "NO_RESULT", "NO_RECORD"].includes(status), reason: "", ...extra,
});

const rows: CarryRow[] = [
  row("CSC 101", 100, 1, "OUTSTANDING", { last_grade: "F" }), row("MTH 102", 100, 2, "OUTSTANDING"), row("GST 101", 100, 1, "NO_RECORD", { units: 2 }),
  row("CSC 201", 200, 1, "CLEARED"), row("CSC 202", 200, 2, "NO_RESULT"), row("CSC 301", 300, 1, "ALREADY_REGISTERED"),
  row("CSC 302", 300, 2, "NO_RECORD", { selectable: false, reason: "Course is not offered in this semester; it runs in the second semester" }),
];

test("only outstanding shows what is owed or may be declared; all previous shows every earlier course", () => {
  assert.deepEqual(filterRows(rows, NO_FILTER).map((r) => r.course_code), ["CSC 101", "MTH 102", "GST 101", "CSC 202", "CSC 302"]);
  assert.equal(filterRows(rows, { ...NO_FILTER, view: "ALL" }).length, rows.length);
});

test("the search reads the code with or without its space, the title, the level and the semester; the filters narrow", () => {
  assert.deepEqual(filterRows(rows, { ...NO_FILTER, view: "ALL", q: "csc2" }).map((r) => r.course_code), ["CSC 201", "CSC 202"]);
  assert.deepEqual(filterRows(rows, { ...NO_FILTER, view: "ALL", q: "Title MTH" }).map((r) => r.course_code), ["MTH 102"]);
  assert.deepEqual(filterRows(rows, { ...NO_FILTER, view: "ALL", q: "300 level" }).map((r) => r.course_code), ["CSC 301", "CSC 302"]);
  assert.deepEqual(filterRows(rows, { ...NO_FILTER, view: "ALL", q: "second semester" }).map((r) => r.course_code), ["MTH 102", "CSC 202", "CSC 302"]);
  assert.deepEqual(filterRows(rows, { ...NO_FILTER, view: "ALL", level: 100 }).map((r) => r.course_code), ["CSC 101", "MTH 102", "GST 101"]);
  assert.deepEqual(filterRows(rows, { ...NO_FILTER, semester: 1 }).map((r) => r.course_code), ["CSC 101", "GST 101"]);
  assert.deepEqual(filterRows(rows, { ...NO_FILTER, group: "GST" }).map((r) => r.course_code), ["GST 101"]);
});

test("the levels on offer are the student's own; the rows group by level, then by semester", () => {
  assert.deepEqual(levelsOf(rows), [100, 200, 300]);
  const g = groupRows(rows);
  assert.deepEqual(g.map((x) => x.level), [100, 200, 300]);
  assert.deepEqual(g[0].semesters.map((s) => [s.semester, s.rows.map((r) => r.course_code)]), [[1, ["CSC 101", "GST 101"]], [2, ["MTH 102"]]]);
});

test("the view opens on the outstanding ones, or on every earlier course when the record states none", () => {
  assert.equal(openingView(rows), "OUTSTANDING");
  assert.equal(openingView(rows.filter((r) => r.status !== "OUTSTANDING")), "ALL");
});

test("what is ticked adds up, and a course that cannot be added never counts", () => {
  const s = selection(rows, new Set(["id-CSC 101", "id-GST 101", "id-CSC 202", "id-CSC 201", "id-CSC 302"]));
  assert.equal(s.count, 3);
  assert.equal(s.units, 8);
  assert.deepEqual(s.byLevel, [[100, 2], [200, 1]]);
});

test("an add answered: all added, some refused, none added", () => {
  assert.equal(outcomeWords([{ courseId: "a", added: true }, { courseId: "b", added: true }, { courseId: "c", added: true }]).title, "3 carry-over courses have been added successfully.");
  assert.deepEqual(outcomeWords([{ courseId: "a", added: true }, { courseId: "b", added: true }, { courseId: "c", added: false }]),
    { title: "2 courses added successfully · 1 course could not be added", kind: "warn" });
  assert.equal(outcomeWords([{ courseId: "a", added: false }]).kind, "bad");
});

test("the carry-over summary counts, adds the units and reads the levels", () => {
  assert.deepEqual(carrySummary([{ units: 3, level: 100 }, { units: 3, level: 100 }, { units: 2, level: 200 }]), { count: 3, units: 8, byLevel: [[100, 2], [200, 1]] });
});

const history: HistoryRow[] = [
  { course_code: "CSC 301", title: "Database Systems", session: "2024/2025", semester: 1, grade: "F", result: "FAILED", owed: true },
  { course_code: "CSC 301", title: "Database Systems", session: "2025/2026", semester: 1, grade: "F", result: "FAILED", owed: true },
  { course_code: "CSC 301", title: "Database Systems", session: "2026/2027", semester: 1, grade: null, result: "REGISTERED", owed: true },
  { course_code: "MTH 302", title: "Real Analysis", session: "2024/2025", semester: 2, grade: "F", result: "FAILED", owed: false },
  { course_code: "MTH 302", title: "Real Analysis", session: "2025/2026", semester: 2, grade: "C", result: "PASSED", owed: false },
];

test("V666: a course owed once, its attempts in words — once failed, or failed again", () => {
  assert.equal(attemptsWords({ course_code: "CSC 301", title: "", units: 3, failed_in: "2024/2025 semester 1", attempts: 1, first_failed_in: "2024/2025 semester 1" }),
    "Failed in 2024/2025 semester 1");
  assert.equal(attemptsWords({ course_code: "CSC 301", title: "", units: 3, failed_in: "2025/2026 semester 1", attempts: 2, first_failed_in: "2024/2025 semester 1" }),
    "Failed 2 times: first 2024/2025 semester 1, last 2025/2026 semester 1");
  // an answer from before V666 (no attempts) reads as one failure
  assert.equal(attemptsWords({ course_code: "CSC 301", title: "", units: 3, failed_in: "2024/2025 semester 1" }), "Failed in 2024/2025 semester 1");
});

test("V666: the history by course — every attempt kept, a course owed or cleared, each attempt in words", () => {
  const g = historyByCourse(history);
  assert.deepEqual(g.map((c) => [c.course_code, c.owed, c.attempts.length]), [["CSC 301", true, 3], ["MTH 302", false, 2]]);
  assert.deepEqual(g[0].attempts.map(attemptWord), ["2024/2025 semester 1 — F", "2025/2026 semester 1 — F", "2026/2027 semester 1 — Registered, no result yet"]);
  assert.equal(attemptWord(g[1].attempts[1]), "2025/2026 semester 2 — C");
  assert.equal(RESULT_WORD.AWAITED, "Result awaited");
});

test("V771: an attempt is shown under the code it was taken under; one under the course's own code reads as before", () => {
  const taken: HistoryRow[] = [
    { course_code: "CSC 301", code_as_taken: "CMP 301", title: "Data Structures", session: "2023/2024", semester: 1, grade: "F", result: "FAILED", owed: true },
    { course_code: "CSC 301", code_as_taken: "CSC 301", title: "Database Systems", session: "2024/2025", semester: 1, grade: "F", result: "FAILED", owed: true },
    { course_code: "CSC 401 BMAS", code_as_taken: null, title: "Compilers", session: "2024/2025", semester: 2, grade: "E", result: "PASSED", owed: false },
  ];
  assert.deepEqual(taken.map(attemptCode), ["CMP 301", "CSC 301", "CSC 401"]);
  assert.deepEqual(historyByCourse(taken)[0].attempts.map(attemptWord), ["2023/2024 semester 1 as CMP 301 — F", "2024/2025 semester 1 — F"]);
  assert.equal(attemptWord(taken[2]), "2024/2025 semester 2 — E");
});

test("V771: a course's attempts sit under the course as the catalogue holds it now; each attempt keeps its own title", () => {
  const taken: HistoryRow[] = [
    { course_code: "CSC 301", code_as_taken: "CMP 301", title: "Data Structures", course_title: "Database Systems", session: "2023/2024", semester: 1, grade: "F", result: "FAILED", owed: true },
    { course_code: "CSC 301", code_as_taken: "CSC 301", title: "Database Systems", course_title: "Database Systems", session: "2024/2025", semester: 1, grade: "F", result: "FAILED", owed: true },
    // an answer from before the heading was given: the first attempt's title heads it
    { course_code: "MTH 302", title: "Real Analysis I", session: "2024/2025", semester: 2, grade: "F", result: "FAILED", owed: true },
  ];
  const g = historyByCourse(taken);
  assert.deepEqual(g.map((c) => [c.course_code, c.title]), [["CSC 301", "Database Systems"], ["MTH 302", "Real Analysis I"]]);
  assert.deepEqual(g[0].attempts.map((a) => a.title), ["Data Structures", "Database Systems"]);
});
