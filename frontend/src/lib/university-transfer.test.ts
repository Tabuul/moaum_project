import { test } from "node:test";
import assert from "node:assert/strict";
import {
  COLUMNS, DOCUMENTS, cgpaWords, documentWords, emptyForm, errorReportRows, formBody, formErrors, lookedUp, outcome, outgoingRows, readUniversitySheet, reportRows,
  rowWords,
  type CheckedRow, type Lookup, type Transfer,
} from "./university-transfer.ts";

test("an outgoing template carries each student as the record holds them and leaves the university blank", () => {
  const rows = outgoingRows([{ matric_no: "MOAU/AD/BUS/25/12939", jamb_reg_no: "12345678AB", student: "DOE, John", faculty_code: "AD", dept_code: "BUS",
    programme_code: "C00101", programme: "B.Sc. Business Administration", current_level: 300, status: "ACTIVE" }], "2026/2027");
  assert.equal(rows[0].length, COLUMNS.length);
  assert.deepEqual(rows[0].slice(0, 4), ["OUTGOING", "MOAU/AD/BUS/25/12939", "12345678AB", "DOE, John"]);
  assert.deepEqual(rows[0].slice(8, 13), ["AD", "BUS", "C00101", 300, ""]);
  assert.equal(rows[0][COLUMNS.findIndex(([k]) => k === "effective_session")], "2026/2027");
  assert.deepEqual(rows[0].slice(13, 20), ["", "", "", "", "", "", ""]);
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
  assert.deepEqual(reportRows([t])[0], [1, "IUT/2026/000001", "Outgoing", "DOE, John", "M1", "", "University of Jos", "B.Sc. Physics", "", "", "", "B.Sc. Economics", 300,
    "2026/2027", "File", "Transferred out", "ZZREG, A", "2026-10-20"]);
  const formed = { ...t, direction: "INCOMING", other_matric_no: "UJ/2022/SC/0042", other_cgpa: "3.5", other_cgpa_scale: 5, source: "FORM" } as unknown as Transfer;
  assert.deepEqual(reportRows([formed])[0].slice(9, 15), ["UJ/2022/SC/0042", "3.50 of 5", "B.Sc. Economics", 300, "2026/2027", "Form"]);
  assert.equal(cgpaWords(null, null), "");
  assert.equal(cgpaWords(3.2, 4), "3.20 of 4");
});

test("a filled file may carry the form's particulars by their column names", () => {
  const read = readUniversitySheet([
    ["Transfer Direction", "JAMB Number", "University Code", "Previous Matriculation Number", "Session Entered", "CGPA", "CGPA Scale", "Documents Seen"],
    ["INCOMING", "12345678AB", "UNIJOS", "UJ/2022/SC/0042", "2022/2023", "3.45", "5", "TRANSCRIPT, RELEASE_LETTER"],
  ]);
  assert.deepEqual(read.rows, [{ direction: "INCOMING", jamb_reg_no: "12345678AB", university_code: "UNIJOS", other_matric_no: "UJ/2022/SC/0042",
    other_entry_session: "2022/2023", other_cgpa: "3.45", other_cgpa_scale: "5", documents: "TRANSCRIPT, RELEASE_LETTER" }]);
});

const applicantOnly: Lookup = { number: "12345678AB", matchedBy: null, student: null, pendingRef: null,
  applicant: { id: "c", session: "2025/2026", surname: "DOE", otherNames: "Jane", sex: "F", programme: "C00023", programmeName: "B.Sc. Computer Science", offerState: "OFFERED" } };
const onRegister: Lookup = { number: "MOAU/SC/CSC/24/0101", matchedBy: "MATRIC", applicant: null, pendingRef: null,
  student: { id: "s", name: "DOE, John", surname: "DOE", otherNames: "John", sex: "M", dateOfBirth: "2004-01-02", matricNo: "MOAU/SC/CSC/24/0101", jambRegNo: "11112222CD",
    status: "ACTIVE", live: true, faculty: "SC", dept: "CSC", programme: "C00023", programmeName: "B.Sc. Computer Science", level: 300 } };

test("an incoming form goes with the JAMB number, the particulars, the placement here and the documents of its direction", () => {
  const f = { ...emptyForm("INCOMING"), number: " 12345678ab ", surname: "doe", otherNames: "Jane ", sex: "F" as const, dateOfBirth: "2005-03-04", email: " Jane@Example.com ",
    phone: "0803 000 0000", faculty: "SC", dept: "CSC", programme: "C00023", level: "200", universityCode: "unijos", otherProgramme: " B.Sc. Physics ", otherLevel: "200",
    otherMatricNo: "uj/2022/sc/0042", otherEntrySession: "2022/ 2023", otherCgpa: "3.45", otherCgpaScale: "4" as const,
    documents: ["TRANSCRIPT", "ACCEPTANCE_LETTER", "RELEASE_LETTER"], reason: "The Senate approved it", remarks: " Good standing " };
  assert.deepEqual(formErrors(f, applicantOnly, true), {});
  assert.deepEqual(formBody(f, applicantOnly), { direction: "INCOMING", universityCode: "UNIJOS", otherProgramme: "B.Sc. Physics", otherLevel: 200,
    otherMatricNo: "UJ/2022/SC/0042", remarks: "Good standing", jambRegNo: "12345678AB", faculty: "SC", dept: "CSC", programme: "C00023", level: 200,
    otherEntrySession: "2022/2023", otherCgpa: "3.45", otherCgpaScale: 4, documents: ["TRANSCRIPT", "RELEASE_LETTER"], surname: "DOE", otherNames: "Jane", sex: "F",
    dateOfBirth: "2005-03-04", email: "jane@example.com", phone: "0803 000 0000" });
  // a student the register holds already: their own particulars stand, none sent
  const onIt: Lookup = { ...onRegister, number: "12345678AB" };
  const body = formBody(f, onIt);
  assert.equal(body.surname, undefined);
  assert.equal(body.dateOfBirth, undefined);
  assert.deepEqual(formErrors({ ...f, surname: "", sex: "" }, onIt), {});
  // no CGPA: no scale either
  assert.equal(formBody({ ...f, otherCgpa: "" }, applicantOnly).otherCgpaScale, null);
});

test("an incoming form says what it lacks, field by field", () => {
  const e = formErrors({ ...emptyForm("INCOMING"), otherEntrySession: "2022/2024", otherCgpa: "5.2", otherCgpaScale: "5" }, null, true);
  // in the page's order, so the first named is the first to put right; the placement one control at a time
  assert.deepEqual(Object.keys(e), ["number", "surname", "otherNames", "sex", "dateOfBirth", "universityCode", "otherProgramme", "otherLevel", "otherMatricNo",
    "otherEntrySession", "otherCgpa", "faculty", "reason"]);
  const placed = (x: Partial<ReturnType<typeof emptyForm>>) => Object.keys(formErrors({ ...emptyForm("INCOMING"), ...x }, null)).filter((k) => ["faculty", "dept", "programme", "level"].includes(k));
  assert.deepEqual([placed({}), placed({ faculty: "SC" }), placed({ faculty: "SC", dept: "CSC" }), placed({ faculty: "SC", dept: "CSC", programme: "C00023" }),
    placed({ faculty: "SC", dept: "CSC", programme: "C00023", level: "200" })], [["faculty"], ["dept"], ["programme"], ["level"], []]);
  assert.match(String(e.otherCgpa), /5-point/);
  assert.match(String(formErrors({ ...emptyForm("INCOMING"), otherCgpa: "3.456" }, null).otherCgpa), /two decimals/);
  assert.match(String(formErrors({ ...emptyForm("INCOMING"), email: "jane@", phone: "12345" }, null).email), /e-mail/);
  assert.match(String(formErrors({ ...emptyForm("INCOMING"), phone: "12345" }, null).phone), /Nigerian/);
  assert.equal(formErrors({ ...emptyForm("INCOMING"), phone: "+234 803 000 0000" }, null).phone, undefined);
  assert.equal(formErrors(emptyForm("INCOMING"), null, false).reason, undefined);
  // the number must have been looked up as it stands, for the direction the form now holds
  const typed = { ...emptyForm("INCOMING"), number: "12345678AB" };
  assert.match(String(formErrors(typed, null).number), /Press Find/);
  assert.equal(formErrors(typed, applicantOnly).number, undefined);
  assert.match(String(formErrors({ ...typed, number: "12345678AC" }, applicantOnly).number), /Press Find/);
  assert.match(String(formErrors(typed, { ...applicantOnly, direction: "OUTGOING" }).number), /Press Find/);
  const asIncoming: Lookup = { ...applicantOnly, direction: "INCOMING" };
  assert.equal(lookedUp(typed, asIncoming), asIncoming);
  assert.equal(lookedUp({ ...typed, number: " 12345678ab " }, asIncoming), asIncoming);
  assert.equal(lookedUp({ ...typed, direction: "OUTGOING" }, asIncoming), null);
});

test("an outgoing form is about the student the number found: their number and the record's placement, never another", () => {
  const f = { ...emptyForm("OUTGOING"), number: "moau/sc/csc/24/0101", universityCode: "UNIJOS", otherProgramme: "B.Sc. Computer Science", otherLevel: "300",
    otherCgpa: "4.1", otherEntrySession: "2020/2021", documents: ["ACCEPTANCE_LETTER", "TRANSCRIPT"], reason: "The Senate approved it" };
  assert.deepEqual(formErrors(f, onRegister, true), {});
  assert.deepEqual(formBody(f, onRegister), { direction: "OUTGOING", universityCode: "UNIJOS", otherProgramme: "B.Sc. Computer Science", otherLevel: 300,
    otherMatricNo: "", remarks: "", matricNo: "MOAU/SC/CSC/24/0101", jambRegNo: "", faculty: "SC", dept: "CSC", programme: "C00023", level: 300,
    documents: ["ACCEPTANCE_LETTER"] });
  // not yet matriculated: the JAMB number
  const admitted: Lookup = { ...onRegister, student: { ...onRegister.student!, matricNo: null } };
  assert.deepEqual([formBody(f, admitted).matricNo, formBody(f, admitted).jambRegNo], ["", "11112222CD"]);
  // not found, or found for another number: the student must be found first
  assert.match(String(formErrors(f, null).number), /Press Find/);
  assert.match(String(formErrors({ ...f, number: "MOAU/SC/CSC/24/0999" }, onRegister).number), /Press Find/);
  assert.match(String(formErrors(f, { ...onRegister, student: null }).number), /No student holds/);
  assert.equal(formBody({ ...f, number: "MOAU/SC/CSC/24/0999" }, onRegister).programme, undefined);
  const closed: Lookup = { ...onRegister, student: { ...onRegister.student!, status: "TRANSFERRED_OUT", live: false } };
  assert.match(String(formErrors(f, closed).number), /transferred out/);
  assert.match(String(formErrors({ ...f, otherProgramme: "" }, onRegister).otherProgramme), /goes into there/);
});

test("each document belongs to one direction and is said in words", () => {
  assert.deepEqual(DOCUMENTS.filter((d) => d.direction === "OUTGOING").map((d) => d.code), ["STUDENT_APPLICATION", "ACCEPTANCE_LETTER"]);
  assert.equal(documentWords(["TRANSCRIPT", "XYZ"]), "Academic transcript from the previous university; XYZ");
  assert.equal(documentWords(undefined), "");
});
