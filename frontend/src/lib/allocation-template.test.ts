import { test } from "node:test";
import assert from "node:assert/strict";
import { COLUMNS, EXTRA_ROWS, SHEET, courseOf, lecturerChoice, nameOf, readTemplate, staffOf, templateSheets, type IssuedTemplate } from "./allocation-template.ts";
import { sheetXml, xlsx } from "./xlsx-write.ts";
import { xlsxWorkbook } from "./xlsx.ts";

const issued: IssuedTemplate = {
  context: { facultyCode: "SC", facultyName: "Science", deptCode: "MTC", deptName: "Mathematics and Computer Science", programmeType: "UNDERGRADUATE",
    session: "2026/2027", semester: 1, version: 1, reference: "CAT-2026-000123", issuedAt: "2026-10-15T10:00:00Z", issuedBy: "OFFICER, Invented", issuedOffice: "ictagent" },
  summary: { programmes: 1, classes: 2, open: 1, lecturers: 2, allocations: 2, unallocated: 1 },
  programmes: [{ code: "C00023", name: "B.Sc. Computer Science", category: "UNDER GRADUATE", dept_name: "Mathematics and Computer Science", faculty_name: "Science" }],
  lecturers: [
    { id: "11111111-1111-4111-8111-111111111111", staff_number: "STF/0012", name: "DOE, John", email: "j@example.com", load: 3 },
    { id: "22222222-2222-4222-8222-222222222222", staff_number: "STF/0045", name: "SMITH, Mary", email: null, load: 0 },
  ],
  classes: [
    { course_id: "c1", code: "CSC 301", title: "Data Structures", units: 3, kind: "Core", level: 300, course_semester: 1, offering_id: "o1",
      lecturer_id: "11111111-1111-4111-8111-111111111111", lecturer_staff_number: "STF/0012", lecturer: "DOE, John",
      second_examiner_id: null, second_staff_number: null, second_examiner: null,
      co_lecturers: JSON.stringify([{ staff_number: "STF/0045", name: "SMITH, Mary" }]), programme_codes: "C00023", programme_names: "B.Sc. Computer Science" },
    { course_id: "c2", code: "CSC 303", title: "Database Systems", units: 3, kind: "Core", level: 300, course_semester: 1, offering_id: null,
      lecturer_id: null, lecturer_staff_number: null, lecturer: null, second_examiner_id: null, second_staff_number: null, second_examiner: null,
      co_lecturers: "[]", programme_codes: "C00023", programme_names: "B.Sc. Computer Science" },
  ],
};

test("a choice carries the staff number the upload reads back", () => {
  assert.equal(lecturerChoice("DOE, John", "STF/0012"), "DOE, John — STF/0012");
  assert.equal(staffOf("DOE, John — STF/0012"), "STF/0012");
  assert.equal(nameOf("DOE, John — STF/0012"), "DOE, John");
  assert.equal(staffOf("STF/0099"), "STF/0099");
  assert.equal(courseOf("CSC 301 — Data Structures"), "CSC 301");
  assert.equal(courseOf("CSC 301"), "CSC 301");
});

test("the allocation sheet carries the register's values, locked, with the choices as lists", () => {
  const sheets = templateSheets(issued, "Rev. Fr. Moses Orshio Adasu University", "15 October 2026");
  assert.deepEqual(sheets.map((s) => s[0]), [SHEET.allocation, SHEET.lecturers, SHEET.courses, SHEET.programmes, SHEET.instructions, SHEET.template]);
  const [, rows, opts] = sheets[0];
  const header = rows.findIndex((r) => r[0] === "S/N");
  assert.deepEqual(rows[header], [...COLUMNS]);
  // one row a lead, one a co-lecturer of CSC 301; one row for CSC 303 not allocated; the extra rows at the end
  const data = rows.slice(header + 1);
  assert.equal(data.length, 3 + EXTRA_ROWS);
  assert.deepEqual(data.map((r) => r[0]).slice(0, 3), [1, 2, 3]);
  assert.equal(data[0][COLUMNS.indexOf("Course code")], "CSC 301");
  assert.equal(data[0][COLUMNS.indexOf("Lecturer")], "DOE, John — STF/0012");
  assert.equal(data[1][COLUMNS.indexOf("Role")], "Co-lecturer");
  assert.equal(data[2][COLUMNS.indexOf("Lecturer")], "");
  const xml = sheetXml(rows, false, opts ?? {});
  assert.ok(xml.includes("<sheetProtection"), "the sheet is protected");
  assert.ok(xml.includes(`<formula1>'Lecturers'!$C$2:$C$3</formula1>`), "the lecturer is chosen from the department's list");
  assert.ok(xml.includes("&quot;Lecturer,Co-lecturer,Second examiner&quot;"), "the role is chosen from a list");
  assert.ok(xml.includes(`<formula1>'Courses'!$C$2:$C$3</formula1>`), "an extra row's course is chosen from the department's courses");
  assert.ok(/<col min="17" max="17"[^>]*hidden="1"/.test(xml), "the course id is hidden");
  assert.ok(xml.includes('state="frozen"'), "the header stays in view");
  // the register's cells locked (style 2/7), the lecturer cells editable (style 10/11)
  const lecturerCol = String.fromCharCode(65 + COLUMNS.indexOf("Lecturer"));
  const codeCol = String.fromCharCode(65 + COLUMNS.indexOf("Course code"));
  assert.ok(new RegExp(`<c r="${lecturerCol}${header + 2}" s="1[01]"`).test(xml), "the lecturer cell is editable");
  assert.ok(new RegExp(`<c r="${codeCol}${header + 2}" s="[27]"`).test(xml), "a class's course code is locked");
  assert.ok(new RegExp(`<c r="${codeCol}${header + 5}" s="1[01]"`).test(xml), "an extra row's course is editable");
});

test("the template reads back as rows the server judges, its context from the hidden sheet", async () => {
  const sheets = templateSheets(issued, "Rev. Fr. Moses Orshio Adasu University", "15 October 2026");
  const book = xlsx(sheets);
  const wb = new TextDecoder().decode(book);
  assert.ok(wb.includes(`<sheet name="Template" sheetId="6" state="hidden"`), "the context sheet is hidden");
  const read = readTemplate(await xlsxWorkbook(book.buffer.slice(book.byteOffset, book.byteOffset + book.byteLength) as ArrayBuffer));
  assert.ok(read);
  assert.deepEqual(read.context, { reference: "CAT-2026-000123", version: 1, faculty: "SC", dept: "MTC", programmeType: "UNDERGRADUATE", session: "2026/2027", semester: 1 });
  // the lead and the co-lecturer on record are rows (the server finds them already allocated); the class left blank is counted
  assert.deepEqual(read.rows.map((r) => `${r.courseCode}|${r.staffId}|${r.role}|${r.session}|${r.semester}`),
    ["CSC 301|STF/0012|Lecturer|2026/2027|1", "CSC 301|STF/0045|Co-lecturer|2026/2027|1"]);
  assert.equal(read.blank, 1);
});

test("a filled template: the class allocated, a further co-lecturer on an extra row", () => {
  const sheets = templateSheets(issued, "University", "15 October 2026");
  const grid = sheets[0][1].map((r) => r.map((c) => (c == null ? "" : String(c))));
  const header = grid.findIndex((r) => r[0] === "S/N");
  const L = COLUMNS.indexOf("Lecturer");
  grid[header + 3][L] = "SMITH, Mary — STF/0045";
  const extra = header + 4;
  grid[extra][COLUMNS.indexOf("Course code")] = "CSC 301 — Data Structures";
  grid[extra][L] = "SMITH, Mary — STF/0045";
  grid[extra][COLUMNS.indexOf("Role")] = "Second examiner";
  grid[extra][COLUMNS.indexOf("Cross-department")] = "NO";
  const read = readTemplate([{ name: SHEET.allocation, rows: grid }, { name: SHEET.template, rows: sheets[5][1].map((r) => r.map((c) => String(c ?? ""))) }]);
  assert.ok(read);
  assert.deepEqual(read.rows.map((r) => `${r.row}|${r.courseCode}|${r.staffId}|${r.lecturerName}|${r.role}|${r.crossDepartment}`), [
    `${header + 2}|CSC 301|STF/0012|DOE, John|Lecturer|`,
    `${header + 3}|CSC 301|STF/0045|SMITH, Mary|Co-lecturer|`,
    `${header + 4}|CSC 303|STF/0045|SMITH, Mary|Lecturer|`,
    `${header + 5}|CSC 301|STF/0045|SMITH, Mary|Second examiner|`,
  ]);
  assert.equal(read.blank, 0);
});

test("a workbook that is not a department template is not read as one", () => {
  assert.equal(readTemplate([{ name: "Allocations", rows: [["Staff ID", "Course code"], ["STF/1", "CSC 301"]] }]), null);
});
