import { test } from "node:test";
import assert from "node:assert/strict";
import {
  SHEET, dataSheetName, firstProblem, historyLines, mayConfirmNew, progressWords, ranges, readFile, reportLines, safeCell, templateSheets,
  type Column, type MigrationRow, type TemplateData,
} from "./pg-migration.ts";

const columns: Column[] = [
  { key: "legacyApplicationNo", header: "Old Application Number", section: "Identification", required: true, note: null },
  { key: "lastName", header: "Last Name", section: "Identification", required: true, note: null },
  { key: "firstName", header: "First Name", section: "Identification", required: true, note: null },
  { key: "email", header: "Email", section: "Identification", required: true, note: null },
  { key: "session", header: "Application Session", section: "PG Application", required: true, note: null },
  { key: "programme", header: "Programme", section: "PG Application", required: true, note: null },
  { key: "gender", header: "Gender", section: "Identification", required: false, note: "Male or Female." },
];
const data: TemplateData = {
  kind: "APPLICANTS", columns,
  faculties: [{ code: "MS", name: "Management Sciences" }], departments: [{ code: "ACC", name: "Accounting", faculty: "Management Sciences" }],
  programmes: [{ code: "C90001", name: "M.Sc. Accounting", award: "MSC", department: "Accounting", faculty: "Management Sciences" }],
  specialisations: [], sessions: [{ name: "2025/2026", state: "current" }], statuses: [{ word: "Submitted", state: "SUBMITTED" }],
};

test("the template is the data sheet under a letterhead, required columns marked, with the guide and this portal's lists", () => {
  const sheets = templateSheets(data, "PG APPLICANT MIGRATION TEMPLATE", "THE UNIVERSITY");
  assert.deepEqual(sheets.map((s) => s[0]), [dataSheetName("APPLICANTS"), SHEET.guide, SHEET.faculties, SHEET.departments, SHEET.programmes, SHEET.specialisations, SHEET.sessions, SHEET.statuses]);
  const rows = sheets[0][1];
  const header = rows.find((r) => r[0] === "S/N")!;
  assert.deepEqual(header, ["S/N", "Old Application Number *", "Last Name *", "First Name *", "Email *", "Application Session *", "Programme *", "Gender"]);
  const v = sheets[0][2]!.validations!;
  assert.ok(v.some((x) => x.range === "'Programmes'!$B$2:$B$2"), "the programme is chosen from this portal's list");
  assert.ok(v.some((x) => x.list?.includes("Female")));
  assert.ok(!JSON.stringify(sheets[4][1]).includes("uuid"), "no database id is a column to type");
});

test("a filled file reads back by its headers, the required marks and spacing aside, blank rows left out, the sheet row kept", () => {
  const sheets = [{ name: "Guide", rows: [["S/N", "Column"]] }, {
    name: "PG Applicants",
    rows: [["THE UNIVERSITY"], [], ["S/N", "Old  Application Number *", "LAST NAME *", "First Name *", "Email *", "Application Session *", "Programme *", "Shoe size"],
      ["1", " PGOLD/2025/00872 ", "Example", "Ada", "ada@example.com", "2025/2026", "M.Sc. Accounting", "41"], ["", "", "", "", "", "", "", ""],
      ["2", "PGOLD/2025/00873", "Sample", "Ben", "", "2025/2026", "M.Sc. Accounting", ""]],
  }];
  const r = readFile(sheets, columns);
  assert.equal(r.sheet, "PG Applicants");
  assert.deepEqual(r.missing, []);
  assert.deepEqual(r.unknown, ["Shoe size"]);
  assert.equal(r.rows.length, 2);
  assert.deepEqual(r.rows[0], { legacyApplicationNo: "PGOLD/2025/00872", lastName: "Example", firstName: "Ada", email: "ada@example.com", session: "2025/2026", programme: "M.Sc. Accounting", sheetRow: "4" });
  assert.equal(r.rows[1].sheetRow, "6");
  assert.equal("email" in r.rows[1], false);
});

test("a file without the template's required columns is named for what it lacks; an old export's 'Applicant Name' stands for the names", () => {
  const r = readFile([{ name: "S", rows: [["Application Number", "Applicant Name", "Email", "Application Session", "Programme"], ["A/1", "DOE, Jane", "j@example.com", "2025/2026", "X"]] }], columns);
  assert.deepEqual(r.missing, []);
  assert.equal(r.rows[0].fullName, "DOE, Jane");
  const none = readFile([{ name: "S", rows: [["Name", "Email"]] }], columns);
  assert.deepEqual(none.missing, ["Old Application Number"]);
});

test("the file is sent, checked and imported in ranges that cover it once", () => {
  assert.deepEqual(ranges(1201, 500), [[1, 500], [501, 1000], [1001, 1201]]);
  assert.deepEqual(ranges(1, 1000), [[1, 1]]);
  assert.equal(progressWords("import", 4250, 10000), "Importing 4,250 / 10,000 rows");
});

test("a value that would run as a formula in the report is written as text", () => {
  assert.equal(safeCell("=HYPERLINK(\"http://x\")"), "'=HYPERLINK(\"http://x\")");
  assert.equal(safeCell("+234803"), "'+234803");
  assert.equal(safeCell("@cmd"), "'@cmd");
  assert.equal(safeCell("PGOLD/2025/1"), "PGOLD/2025/1");
  assert.equal(safeCell(12), 12);
  assert.equal(safeCell(undefined), null);
});

const row = (over: Partial<MigrationRow>): MigrationRow => ({
  id: "r", row_no: 3, legacy_no: "PGOLD/1", applicant: "Example, Ada", email: null, verdict: "READY", match: "NEW_APPLICANT", action: "CREATE",
  programme_code: null, session: null, target_state: null, problems: [], result: null, result_note: null, decided_new: false, decided_new_reason: null,
  application_id: null, student_id: null, application_no: null, student_no: null, sheet_row: "9", programme_given: null, programme_code_given: null,
  department_given: null, faculty_given: null, status_given: null, programme_name: null, department_name: null, faculty_name: null, ...over,
});

test("the error report is a line per problem, with the row, the sheet row, the old number and the suggested correction", () => {
  const lines = reportLines([
    row({ verdict: "ERROR", problems: [{ code: "EMAIL_MISSING", level: "error", message: "A new applicant needs an email.", fix: "Give the email." }, { code: "PHONE_FORM", level: "warning", message: "Phone not read." }] }),
    row({ row_no: 5, sheet_row: null, verdict: "READY", result: "FAILED", result_note: "=boom", problems: [] }),
  ]);
  assert.equal(lines.length, 3);
  assert.deepEqual(lines[0], [3, 9, "Example, Ada", "PGOLD/1", "Error", "EMAIL_MISSING", "A new applicant needs an email.", "Give the email."]);
  assert.deepEqual(lines[2], [5, null, "Example, Ada", "PGOLD/1", "Failed", "IMPORT_FAILED", "'=boom", "Correct the row and upload it again."]);
});

test("the School confirms a new applicant only where a possible same person alone holds the row", () => {
  const possible = { code: "POSSIBLE_SAME_APPLICANT", level: "review" as const, message: "An applicant of the same surname…" };
  assert.equal(mayConfirmNew(row({ verdict: "REQUIRES_REVIEW", problems: [possible] })), true);
  assert.equal(mayConfirmNew(row({ verdict: "REQUIRES_REVIEW", problems: [possible, { code: "PROGRAMME_NOT_MAPPED", level: "review", message: "x" }] })), false);
  assert.equal(mayConfirmNew(row({ verdict: "REQUIRES_REVIEW", problems: [possible], result: "SKIPPED" })), false);
  assert.equal(mayConfirmNew(row({ verdict: "REQUIRES_REVIEW", problems: [possible], decided_new: true })), false);
  assert.equal(firstProblem(row({ problems: [{ code: "W", level: "warning", message: "w" }, { code: "E", level: "conflict", message: "e" }] }))?.code, "E");
});

test("the history reads each upload in words", () => {
  const [l] = historyLines([{ id: "b", reference: "PG-MIG/2026/000001", kind: "ADMITTED", state: "COMPLETED", file_name: "=x.xlsx", rows_expected: 10,
    started_at: "2026-10-27T10:00:00Z", completed_at: null, started_by: "School, A", created: 4, updated: 1, reconciled: 2, linked: 1, unchanged: 0,
    skipped: 2, failed: 1, admitted: 6, duplicates: 1, errors: 1, conflicts: 0, review: 0, abandoned_reason: null }]);
  assert.equal(l[0], "PG-MIG/2026/000001");
  assert.equal(l[1], "Admitted PG applicants");
  assert.equal(l[2], "'=x.xlsx");
  assert.equal(l[9], 2);
  assert.equal(l[13], "Completed");
});
