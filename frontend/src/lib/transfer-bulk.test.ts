import { test } from "node:test";
import assert from "node:assert/strict";
import { COLUMNS, errorReportRows, readTransferSheet, rowWords, templateRows, type CheckedRow } from "./transfer-bulk.ts";

test("the template carries each student's current placement in the OLD columns and leaves the NEW ones blank", () => {
  const rows = templateRows([{ matric_no: "MOAU/AD/BUS/25/12939", jamb_reg_no: "12345678AB", student: "DOE, John", faculty_code: "AD", dept_code: "BUS",
    programme_code: "C00101", programme: "B.Sc. Business Administration", current_level: 300, status: "ACTIVE" }], "2026/2027");
  assert.equal(rows[0].length, COLUMNS.length);
  assert.deepEqual(rows[0].slice(0, 11), ["MOAU/AD/BUS/25/12939", "12345678AB", "DOE, John", "AD", "BUS", "C00101", 300, "", "", "", ""]);
  assert.equal(rows[0][11], "2026/2027");
});

test("a filled file is read by its column names under the branding, its empty rows left out", () => {
  const grid = [
    ["Rev. Fr. Moses Orshio Adasu University"], ["Bulk Inter-Departmental Transfer"], [],
    ["S/N", "Student Matriculation Number", "JAMB Number", "Student Name", "Old Faculty Code", "Old Department Code", "Old Programme Code", "Old Level",
     "New Faculty Code", "New Department Code", "New Programme Code", "New Level", "Reason"],
    ["1", "MOAU/AD/BUS/25/12939", "", "DOE, John", "AD", "BUS", "C00101", "300", "SC", "CSC", "C00023", "300", ""],
    ["2", "", "", "", "", "", "", "", "", "", "", "", ""],
  ];
  const read = readTransferSheet(grid);
  assert.equal(read.problem, null);
  assert.equal(read.rows.length, 1);
  assert.deepEqual(read.rows[0], { matric_no: "MOAU/AD/BUS/25/12939", student: "DOE, John", old_faculty: "AD", old_dept: "BUS", old_programme: "C00101",
    old_level: "300", new_faculty: "SC", new_dept: "CSC", new_programme: "C00023", new_level: "300" });
  assert.match(String(readTransferSheet([["Code", "Name"]]).problem), /Use the template/);
});

test("a row is said by its problems, else its review points; the error report keeps every row", () => {
  const r: CheckedRow = { row: 2, status: "INVALID", studentId: "x", matchedBy: "MATRIC", student: "MARY, John", matricNo: "M1",
    current: { faculty: "SC", dept: "PHY", programme: "C00030", level: 300 }, uploadedOld: { faculty: "SC", dept: "BIO", programme: "C00031", level: 300 },
    new: { faculty: "SC", dept: "CSC", programme: "C00023", level: 300 }, transferType: null, session: "2026/2027", reason: null,
    problems: [{ code: "SOURCE_PROGRAMME_MISMATCH", text: "SOURCE PROGRAMME MISMATCH: the file says SC / BIO / C00031" }], warnings: [] };
  assert.match(rowWords(r), /SOURCE PROGRAMME MISMATCH/);
  assert.equal(rowWords({ problems: [], warnings: [{ code: "FACULTY_CHANGE", text: "The student moves to another faculty" }] }), "The student moves to another faculty");
  assert.deepEqual(errorReportRows([r])[0].slice(0, 4), [2, "MARY, John", "M1", "Invalid"]);
});
