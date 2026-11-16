import { test } from "node:test";
import assert from "node:assert/strict";
import {
  applyRow, batchEnd, chunkEnds, codeKey, columnsStop, fixedEnds, groupScopedRows, resolveColumns, rowFingerprint, rowHeld, semNum,
} from "./legacy-columns.ts";

const keys = (kind: Parameters<typeof resolveColumns>[0], header: string[]) => Object.fromEntries(resolveColumns(kind, header).map((c) => [c.key, header[c.idx]]));
const REG = ["Matriculation Number", "Course Code", "Course Title", "Credit Units", "Category", "Level", "Session", "Semester"];
const RES = [...REG, "CA", "Exam", "Total", "Outcome"];

test("a registration file reads the course as taken: title, credit units and category, never a units key", () => {
  const k = keys("registration", REG);
  assert.deepEqual(k, { matric: "Matriculation Number", course: "Course Code", creditUnits: "Credit Units", title: "Course Title", category: "Category",
    level: "Level", session: "Session", semester: "Semester" });
  assert.equal("units" in k, false);
});

test("a results file reads the same and the marks", () => {
  const k = keys("results", RES);
  assert.equal(k.creditUnits, "Credit Units");
  assert.equal(k.title, "Course Title");
  assert.equal(k.category, "Category");
  assert.equal(k.ca, "CA");
  assert.equal(k.exam, "Exam");
  assert.equal(k.total, "Total");
  assert.equal(k.outcome, "Outcome");
  assert.equal("units" in k, false);
});

test("credit units only from a column naming them: Credit Unit, CU; a Units column beside them is never read", () => {
  assert.equal(keys("registration", ["Matric", "Code", "Title", "CU", "Category", "Session", "Semester"]).creditUnits, "CU");
  const both = keys("results", ["Matric No", "Course Code", "Course Title", "Units", "Credit Unit", "Category", "Session", "Semester", "Total"]);
  assert.equal(both.creditUnits, "Credit Unit");
  assert.equal("units" in both, false);
  assert.equal(keys("registration", ["Matric", "Course Code", "Title"]).title, "Title");
});

test("the postgraduate uploads keep reading their Units column as units", () => {
  const pg = keys("pgregistration", ["Matriculation Number", "Course Code", "Course Title", "Units", "Kind", "Mode", "Session", "Semester"]);
  assert.equal(pg.units, "Units");
  assert.equal(pg.title, "Course Title");
  assert.equal(pg.kind, "Kind");
  assert.equal(pg.mode, "Mode");
  assert.equal("creditUnits" in pg, false);
  assert.equal(keys("pgresults", ["Matric", "Course Code", "Units", "Total"]).units, "Units");
  assert.equal(columnsStop("pgresults", ["Matric", "Course Code", "Units", "Total"]), null);
});

test("the old portal's Units status code stops an undergraduate file, with the reason", () => {
  for (const h of [["Matric", "Course Code", "Course Title", "Units", "Category", "Session", "Semester"],
    ["Matric", "Course Code", "Course Title", "Unit", "Category"], ["Matric", "Course Code", "Course Title", "Course Unit", "Category"]]) {
    const stop = columnsStop("registration", h);
    assert.ok(stop, h.join(","));
    assert.match(stop.detail, /status code \(1 GST, 2 core, 3 elective, 0 carry-over\), not credit units/);
    assert.match(stop.detail, /add a Credit Units column/);
  }
  assert.ok(columnsStop("results", ["Matric", "Course Code", "Course Title", "Units", "Category", "Total"]));
  assert.equal(columnsStop("registration", ["Matric", "Course Code", "Course Title", "Units", "Credit Units", "Category"]), null);
  assert.equal(columnsStop("registration", REG), null);
  assert.equal(columnsStop("results", RES), null);
});

test("a file without the course as taken is stopped, naming the missing columns", () => {
  const old = columnsStop("registration", ["Matriculation Number", "Course Code", "Level", "Session", "Semester"]);
  assert.ok(old);
  assert.equal(old.title, "The file has no Course Title, Credit Units and Category columns.");
  const one = columnsStop("results", ["Matric", "Course Code", "Course Title", "Credit Units", "Session", "Semester", "Total"]);
  assert.equal(one?.title, "The file has no Category column.");
  assert.equal(columnsStop("biodata", ["Matric", "Surname"]), null);
});

test("a semester cell is read strictly", () => {
  for (const v of ["First", "first", "1st", "1", "First Semester", "first  semester", "Semester: First"]) assert.equal(semNum(v), 1, v);
  for (const v of ["Second", "2nd", "2", "SECOND SEMESTER"]) assert.equal(semNum(v), 2, v);
  for (const v of ["Summer", "Third", "3rd", "3", "Summer semester"]) assert.equal(semNum(v), 3, v);
  for (const v of ["", "Fourth", "4", "s", "f", "1.5", "Rain", "2nd semester exams"]) assert.equal(semNum(v), 0, v);
  assert.equal(semNum("Third", true), 0);
  assert.equal(semNum("3", true), 0);
  assert.equal(semNum("Second", true), 2);
});

test("what keeps a row back before it is sent", () => {
  assert.equal(rowHeld("registration", { line: "4" }), "No matriculation number");
  assert.equal(rowHeld("results", { course: "CSC 101" }), "No matriculation number");
  assert.equal(rowHeld("pgresults", { course: "CSC 801" }), "");   // as before: passed over
  assert.equal(rowHeld("results", { matric: "Matric No" }), "");
  assert.equal(rowHeld("biodata", { matric: "not a number" }), "No valid matriculation number");
  assert.equal(rowHeld("biodata", { matric: "MOAUM/CSC/22/0001" }), null);
  assert.equal(rowHeld("registration", { matric: "anything the server reads" }), null);
});

test("a course code compared one way", () => {
  assert.equal(codeKey("csc101"), "CSC 101");
  assert.equal(codeKey(" CSC   101 "), "CSC 101");
  assert.equal(codeKey("GST 111"), "GST 111");
  assert.equal(codeKey("CSC 401 BMAS"), "CSC 401 BMAS");
});

test("a row read by the columns found once", () => {
  const cols = resolveColumns("results", RES);
  const o = applyRow(cols, ["MOAUM/CSC/22/0001", "CSC 301", " Data Structures ", "3", "Core", "300", "2024/2025", "First", "", "", "70", "GRADED"]);
  assert.deepEqual(o, { matric: "MOAUM/CSC/22/0001", course: "CSC 301", title: "Data Structures", creditUnits: "3", category: "Core", level: "300",
    session: "2024/2025", semester: "First", total: "70", outcome: "GRADED" });
});

const row = (line: number, matric: string, course: string, session?: string, semester?: string, extra: Record<string, string> = {}) => {
  const o: Record<string, string> = { line: String(line), matric, course, title: "Some Course", creditUnits: "2", category: "Core", ...extra };
  if (session !== undefined && session !== "") o.session = session;
  if (semester !== undefined && semester !== "") o.semester = semester;
  return o;
};
const REG_COLS = resolveColumns("registration", REG);
const NO_SCOPE_COLS = resolveColumns("registration", ["Matriculation Number", "Course Code", "Course Title", "Credit Units", "Category"]);

test("a file's Session and Semester cells are read; a blank or malformed one sets the row aside, never the screen's", () => {
  const g = groupScopedRows("registration", [
    row(2, "A/B/1", "CSC 101", "2023/2024", "First"),
    row(3, "A/B/1", "CSC 102", "", "First"),
    row(4, "A/B/1", "CSC 103", "2023-2024", "First"),
    row(5, "A/B/1", "CSC 104", "2023/2024", ""),
    row(6, "A/B/1", "CSC 105", "2023/2024", "Rain"),
    row(7, "A/B/1", "CSC 106", "2023/2024", "Summer"),
  ], REG_COLS, { session: "2024/2025", semester: "2" });
  assert.equal(g.stop, null);
  assert.deepEqual(g.groups.map((x) => [x.session, x.semester, x.rows.map((r) => r.line)]), [["2023/2024", 1, ["2"]], ["2023/2024", 3, ["7"]]]);
  assert.deepEqual(g.invalid.map((r) => [r.line, r.reason]), [
    ["3", "The Session cell is blank"],
    ["4", "The session \"2023-2024\" is not written YYYY/YYYY"],
    ["5", "The Semester cell is blank"],
    ["6", "The semester \"Rain\" is not First, Second or Summer"],
  ]);
});

test("a postgraduate file has two semesters", () => {
  const cols = resolveColumns("pgresults", ["Matriculation Number", "Course Code", "Units", "Session", "Semester", "Total"]);
  const g = groupScopedRows("pgresults", [{ matric: "M/A/1", course: "BSM 801", session: "2024/2025", semester: "Third" },
    { matric: "M/A/1", course: "BSM 802", session: "2024/2025", semester: "Second" }], cols, { session: "", semester: "1" });
  assert.deepEqual(g.groups.map((x) => [x.semester, x.rows.length]), [[2, 1]]);
  assert.equal(g.invalid[0].reason, "The semester \"Third\" is not First or Second");
});

test("without the columns the screen's session and semester stand; with neither, the file is stopped", () => {
  const ok = groupScopedRows("results", [row(2, "A/B/1", "CSC 101")], NO_SCOPE_COLS, { session: "2022/2023", semester: "2" });
  assert.deepEqual(ok.groups.map((x) => [x.session, x.semester]), [["2022/2023", 2]]);
  const stop = groupScopedRows("results", [row(2, "A/B/1", "CSC 101")], NO_SCOPE_COLS, { session: "", semester: "1" });
  assert.equal(stop.stop?.title, "No session to load against.");
  assert.equal(stop.groups.length, 0);
});

test("one student's course twice in the file: agreeing copies go up once, differing copies not at all", () => {
  const g = groupScopedRows("results", [
    row(2, "A/B/1", "CSC101", "2023/2024", "1", { total: "60" }),
    row(3, "a/b/1", "csc  101", "2023/2024", "First", { total: "60" }),
    row(4, "A/B/1", "CSC 102", "2023/2024", "1", { total: "50" }),
    row(5, "A/B/1", "CSC 102", "2023/2024", "1", { total: "55" }),
    row(6, "A/B/1", "CSC 101", "2024/2025", "1", { total: "40" }),   // another session: not a repeat
    row(7, "A/B/2", "CSC 101", "2023/2024", "1", { total: "60" }),
  ], resolveColumns("results", RES), { session: "", semester: "1" });
  assert.equal(g.repeated, 3);
  assert.deepEqual(g.invalid.map((r) => r.line), ["3", "4", "5"]);
  assert.match(g.invalid[0].reason, /appear earlier in the file \(row 2\)/);
  assert.match(g.invalid[1].reason, /different title, credit units, category or mark/);
  const sent = g.groups.flatMap((x) => x.rows.map((r) => r.line)).sort();
  assert.deepEqual(sent, ["2", "6", "7"]);
});

test("what one copy says: spacing and case aside", () => {
  assert.equal(rowFingerprint({ title: "Data  Structures", creditUnits: " 3", category: "core", total: "70" }),
    rowFingerprint({ title: "Data Structures", creditUnits: "3", category: "CORE", total: "70 " }));
  assert.notEqual(rowFingerprint({ title: "Data Structures", creditUnits: "3" }), rowFingerprint({ title: "Data structures", creditUnits: "3" }));
});

test("a group's rows in student order, its batches cut only between students", () => {
  const rows: Record<string, string>[] = [];
  let line = 2;
  for (const m of ["C/1", "A/1", "B/1"]) for (let i = 0; i < 3; i++) rows.push(row(line++, m, `CSC 10${i}`, "2023/2024", "1"));
  const g = groupScopedRows("registration", rows, REG_COLS, { session: "", semester: "1" }, 4);
  assert.deepEqual(g.groups[0].rows.map((r) => `${r.matric} ${r.course}`), ["A/1 CSC 100", "A/1 CSC 101", "A/1 CSC 102", "B/1 CSC 100", "B/1 CSC 101", "B/1 CSC 102",
    "C/1 CSC 100", "C/1 CSC 101", "C/1 CSC 102"]);
  assert.deepEqual(g.groups[0].ends, [3, 6, 9]);
});

test("batch ends: about the size, never inside a student, a student larger than a batch on their own", () => {
  const rs = (spec: [string, number][]) => spec.flatMap(([m, n]) => Array.from({ length: n }, () => ({ matric: m })));
  assert.deepEqual(chunkEnds(rs([["A", 2], ["B", 2], ["C", 2], ["D", 2]]), 4), [4, 8]);
  assert.deepEqual(chunkEnds(rs([["A", 3], ["B", 3], ["C", 3]]), 4), [3, 6, 9]);
  assert.deepEqual(chunkEnds(rs([["A", 7], ["B", 1]]), 4), [7, 8]);
  assert.deepEqual(chunkEnds(rs([["A", 1], ["B", 7], ["C", 1]]), 4), [1, 8, 9]);
  assert.deepEqual(chunkEnds([], 4), []);
  assert.deepEqual(fixedEnds(9, 4), [4, 8, 9]);
  assert.deepEqual(fixedEnds(8, 4), [4, 8]);
  assert.equal(batchEnd([3, 6, 9], 0), 3);
  assert.equal(batchEnd([3, 6, 9], 3), 6);
  assert.equal(batchEnd([3, 6, 9], 9), Number.POSITIVE_INFINITY);
  assert.deepEqual([1, 2, 3].slice(2, batchEnd([], 2)), [3]);
});
