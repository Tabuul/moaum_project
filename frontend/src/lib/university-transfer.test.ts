import { test } from "node:test";
import assert from "node:assert/strict";
import { COLUMNS, errorReportRows, outcome, outgoingRows, readUniversitySheet, reportRows, rowWords, type CheckedRow, type Transfer } from "./university-transfer.ts";

test("an outgoing template carries each student as the record holds them and leaves the university blank", () => {
  const rows = outgoingRows([{ matric_no: "MOAU/AD/BUS/25/12939", jamb_reg_no: "12345678AB", student: "DOE, John", faculty_code: "AD", dept_code: "BUS",
    programme_code: "C00101", programme: "B.Sc. Business Administration", current_level: 300, status: "ACTIVE" }], "2026/2027");
  assert.equal(rows[0].length, COLUMNS.length);
  assert.deepEqual(rows[0].slice(0, 4), ["OUTGOING", "MOAU/AD/BUS/25/12939", "12345678AB", "DOE, John"]);
  assert.deepEqual(rows[0].slice(8, 13), ["AD", "BUS", "C00101", 300, ""]);
  assert.equal(rows[0][15], "2026/2027");
});

test("a filled file is read by its column names under the branding, its other names accepted, its empty rows left out", () => {
  const grid = [
    ["Rev. Fr. Moses Orshio Adasu University"], ["Inter-University Transfer"], [],
    ["S/N", "Direction", "JAMB Registration Number", "Student Name", "Gender", "Faculty Code", "Department Code", "Programme Code", "Level", "Previous University Code", "Previous Level"],
    ["1", "INCOMING", "12345678AB", "DOE, Jane", "F", "SC", "CSC", "C00023", "200", "UNIJOS", "200"],
    ["2", "", "", "", "", "", "", "", "", "", ""],
  ];
  const read = readUniversitySheet(grid);
  assert.equal(read.problem, null);
  assert.deepEqual(read.rows, [{ direction: "INCOMING", jamb_reg_no: "12345678AB", student: "DOE, Jane", sex: "F", faculty: "SC", dept: "CSC", programme: "C00023",
    level: "200", university_code: "UNIJOS", other_level: "200" }]);
  assert.match(String(readUniversitySheet([["Matric No", "Name"]]).problem), /Use the template/);
});

test("a row is said by its problems, else its review points; the error report keeps every row and what the decision would do", () => {
  const r: CheckedRow = { row: 2, direction: "INCOMING", action: "CREATE_FROM_APPLICANT", status: "WARNING", studentId: null, candidateId: "c", matchedBy: null,
    student: "DOE, Jane", matricNo: null, jambRegNo: "12345678AB", current: null, placement: { faculty: "SC", dept: "CSC", programme: "C00023", level: 200 },
    university: "UNIJOS", universityName: "University of Jos", otherProgramme: null, otherLevel: null, session: "2026/2027", reason: null, problems: [],
    warnings: [{ code: "APPLICANT_LINKED", text: "An applicant under the JAMB number is linked" }] };
  assert.equal(rowWords(r), "An applicant under the JAMB number is linked");
  assert.deepEqual(errorReportRows([r])[0], [2, "Incoming", "DOE, Jane", "", "12345678AB", "UNIJOS", "Valid — look at", "", "SC / CSC / C00023 / 200",
    "A new record, the applicant linked", "An applicant under the JAMB number is linked"]);
  const bad = { ...r, status: "INVALID" as const, problems: [{ code: "TARGET_LEVEL", text: "The level is not the programme's" }] };
  assert.equal(errorReportRows([bad])[0][9], "");
  assert.equal(rowWords(bad), "The level is not the programme's");
});

test("a transfer's outcome is said in words, and the report numbers its rows", () => {
  assert.equal(outcome({ direction: "OUTGOING", status: "COMPLETED", created_student: false }), "Transferred out");
  assert.equal(outcome({ direction: "INCOMING", status: "COMPLETED", created_student: true }), "Taken on: a new record");
  assert.equal(outcome({ direction: "INCOMING", status: "COMPLETED", created_student: false }), "Taken on: the existing record");
  assert.equal(outcome({ direction: "INCOMING", status: "PENDING_APPROVAL", created_student: false }), "Waiting for another officer");
  const t = { batch_ref: "IUT/2026/000001", direction: "OUTGOING", status: "COMPLETED", created_student: false, student: "DOE, John", matric_no: "M1",
    jamb_reg_no: null, university: "University of Jos", other_programme: "B.Sc. Physics", other_level: null, programme: "B.Sc. Economics", programme_code: "C00101",
    level: 300, effective_session: "2026/2027", decided_by_name: "ZZREG, A", decided_at: "2026-10-20T10:00:00Z" } as unknown as Transfer;
  assert.deepEqual(reportRows([t])[0], [1, "IUT/2026/000001", "Outgoing", "DOE, John", "M1", "", "University of Jos", "B.Sc. Physics", "", "B.Sc. Economics", 300,
    "2026/2027", "Transferred out", "ZZREG, A", "2026-10-20"]);
});
