import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import {
  ROLL_COLUMNS, actionWord, addCheck, addChunk, addOutcome, changeText, claimedBy, chunkFailed, docxTables, emptyTally, excelDate, findHeader, keptText, readRoll,
  resultSheet, rollGridFromTables, rollHeader, rollName, rollNumbers, rollTemplate, staffNumberOf, unresolvedText, wordTables,
  wrongRoll, type RollResult,
} from "./staff-roll.ts";
import { xlsxWorkbook, zip } from "./xlsx.ts";
import { xlsx } from "./xlsx-write.ts";

const ACADEMIC_HEAD = ["SNO", "FIRST NAME", "MIDDLE NAME", "LAST-SURNAME", "PNO", "SEX", "DATE OF BIRTH", "E-MAIL-PERSONAL", "PHONE NO", "LGA", "STATE",
  "DATE OF 1ST APPT-RANK", "DATE OF CONFIRMATION", "DATE OF LAST PROMOTION", "PRESENT RANK", "DEPARTMENT", "FAC-COLL-DIR"];
const SENIOR_HEAD = ["SNO", "FIRST_NAME", "MIDDLE NAME", "LAST-SURNAME", "PNO", "SEX", "DATE OF BIRTH", "E-MAIL", "PHONE NO", "LGA", "STATE",
  "DATE OF 1ST APPT-RANK", "DATE OF CONFIRMATION", "DATE OF LAST PROMOTION", "PRESENT RANK", "CURRENT POSTING"];
const JUNIOR_HEAD = SENIOR_HEAD.map((h) => (h === "PNO" ? "JP-NO" : h === "FIRST_NAME" ? "FIRST NAME" : h));

const ab = (b: Uint8Array): ArrayBuffer => b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength) as ArrayBuffer;

test("the templates carry the roll's columns exactly: 17 for the teaching staff, 16 for the senior and the junior staff", () => {
  assert.deepEqual(ROLL_COLUMNS.ACADEMIC.map((c) => c.head), ACADEMIC_HEAD);
  assert.deepEqual(ROLL_COLUMNS.SENIOR.map((c) => c.head), SENIOR_HEAD);
  assert.deepEqual(ROLL_COLUMNS.JUNIOR.map((c) => c.head), JUNIOR_HEAD);
  for (const t of ["ACADEMIC", "SENIOR", "JUNIOR"] as const) assert.ok(ROLL_COLUMNS[t].every((c) => c.note.length > 5), `${t}: every column says what it takes`);
});

test("a template downloaded and read back is recognised, its instructions sheet is not taken for the roll", async () => {
  for (const [t, kind, junior] of [["ACADEMIC", "ACADEMIC", false], ["SENIOR", "NON_ACADEMIC", false], ["JUNIOR", "NON_ACADEMIC", true]] as const) {
    const sheets = await xlsxWorkbook(ab(xlsx(rollTemplate(t))), { rowNumbers: true });
    assert.equal(sheets.length, 2);
    assert.equal(sheets[1].name, "Instructions");
    const h = findHeader(sheets[0].rows);
    assert.ok(h, `${t}: the first sheet's heading row is recognised`);
    assert.equal(h.index, 0);
    assert.equal(h.header.kind, kind);
    assert.equal(h.header.junior, junior);
    assert.equal(sheets[0].rows.length, 1, "nothing but the headings: no example row to upload by mistake");
    const text = sheets[1].rows.flat().join(" ");
    for (const w of ["Day first", "NA", "only where the portal has none", "only fills what their record is missing", "(.docx)"]) assert.ok(text.includes(w), `${t}: the instructions say ${w}`);
    assert.equal(findHeader(sheets[1].rows), null);
  }
});

test("headings are read whatever their case, spacing, _ or -, and the old sheet's are still known", () => {
  const h = rollHeader(["s/n", "first_name", "Middle  Name", "last surname", "p.no", "Sex", "date-of-birth", "E MAIL", "phone no", "lga", "State",
    "Date of 1st Appt - Rank", "date of confirmation", "DATE OF LAST PROMOTION", "present_rank", "Current Posting"]);
  assert.ok(h);
  assert.equal(h.roll, true);
  assert.equal(h.kind, "NON_ACADEMIC");
  assert.equal(h.at.email, 7);
  assert.equal(h.at.date_first_appointment, 11, "DATE OF 1ST APPT-RANK is the first appointment");
  assert.equal(h.at.present_rank, 14, "and not the rank");
  assert.equal(rollHeader(ACADEMIC_HEAD.map((x) => x.toLowerCase()))?.at.email, 7, "E-MAIL-PERSONAL is the e-mail");
  const unitSheet = rollHeader(["PNO", "Full Names", "Unit", "Present Rank", "CONTISS"]);
  assert.deepEqual([unitSheet?.kind, unitSheet?.at.unit, unitSheet?.at.posting], ["NON_ACADEMIC", 2, undefined], "the old sheet's Unit column is its own key");
  assert.equal(unitSheet && wrongRoll(unitSheet, "ACADEMIC"), "This is the old non-teaching sheet (Unit and CONTISS). Upload it on the non-academic staff desk.");
  const old = rollHeader(["PNO", "Full Names", "Sex", "Date of 1st Appt", "Department", "Present Rank", "Phone No", "CONUASS"]);
  assert.deepEqual([old?.roll, old?.kind, old?.at.full_names, old?.at.conuass], [false, "ACADEMIC", 1, 7]);
  assert.equal(rollHeader(["PNO", "Full Names", "Sex", "Date of 1st Appt", "Department", "Present Rank", "Phone No", "CONTISS"])?.kind, "NON_ACADEMIC");
  assert.equal(rollHeader(["PNO", "Full Names", "Department"])?.kind, null, "the old sheet without its scale says neither");
  assert.equal(rollHeader(["NOVEMBER 2026 NOMINAL ROLL", "", ""]), null);
  assert.equal(rollHeader(["FIRST NAME", "LAST-SURNAME", "DEPARTMENT"]), null, "no staff number: not a staff list");
});

test("the junior roll is told by its JP-NO heading, whatever its title says; a junior is JP and the digits", () => {
  const h = rollHeader(JUNIOR_HEAD);
  assert.deepEqual([h?.junior, h?.kind, rollName(h!)], [true, "NON_ACADEMIC", "the junior staff roll (JP-NO)"]);
  assert.equal(rollName(rollHeader(SENIOR_HEAD)!), "the senior non-teaching staff roll");
  assert.equal(rollName(rollHeader(ACADEMIC_HEAD)!), "the teaching staff roll");
  assert.equal(staffNumberOf({ jp_no: "858" }), "JP858");
  assert.equal(staffNumberOf({ jp_no: "JP 858" }), "JP858");
  assert.equal(staffNumberOf({ pno: "99029" }), "P99029");
  assert.equal(staffNumberOf({ pno: "p99029" }), "P99029");
  assert.equal(staffNumberOf({ pno: "jp12" }), "JP12", "a number written JP… is a junior's");
  assert.equal(staffNumberOf({ pno: "", jp_no: "NA" }), null);
});

const OLD_LECTURER_HEAD = ["PNO", "Full Names", "Sex", "Date of 1st Appt", "Department", "Present Rank", "Phone No", "CONUASS"];
const OLD_STAFF_HEAD = ["PNO", "Full Names", "Sex", "Date of 1st Appt", "Department", "Present Rank", "Phone No", "CONTISS"];

test("a file for the other upload is named for what it is, by the headings it carries; on its own desk it is taken", () => {
  const on = (head: string[], kind: "ACADEMIC" | "NON_ACADEMIC") => wrongRoll(rollHeader(head)!, kind);
  // the teaching staff desk
  assert.equal(on(ACADEMIC_HEAD, "ACADEMIC"), null);
  assert.equal(on(OLD_LECTURER_HEAD, "ACADEMIC"), null);
  assert.equal(on(SENIOR_HEAD, "ACADEMIC"), "This is the senior non-teaching staff roll (CURRENT POSTING). Upload it on the non-academic staff desk.");
  assert.equal(on(JUNIOR_HEAD, "ACADEMIC"), "This is the junior staff roll (JP-NO and CURRENT POSTING). Upload it on the non-academic staff desk.",
    "JP-NO named once");
  assert.equal(on(OLD_STAFF_HEAD, "ACADEMIC"), "This is the old non-teaching sheet (CONTISS). Upload it on the non-academic staff desk.",
    "the old sheet has no CURRENT POSTING");
  // the non-academic staff desk
  assert.equal(on(SENIOR_HEAD, "NON_ACADEMIC"), null);
  assert.equal(on(JUNIOR_HEAD, "NON_ACADEMIC"), null);
  assert.equal(on(OLD_STAFF_HEAD, "NON_ACADEMIC"), null);
  assert.equal(on(ACADEMIC_HEAD, "NON_ACADEMIC"), "This is the teaching staff roll (DEPARTMENT and FAC-COLL-DIR). Upload it on the teaching staff desk.");
  assert.equal(on(OLD_LECTURER_HEAD, "NON_ACADEMIC"), "This is the old teaching-staff sheet (CONUASS). Upload it on the teaching staff desk.",
    "the old sheet has no FAC-COLL-DIR, and its Department does not tell");
  // as the file writes its headings, and only those it has
  assert.equal(on(ACADEMIC_HEAD.filter((h) => h !== "FAC-COLL-DIR"), "NON_ACADEMIC"), "This is the teaching staff roll (DEPARTMENT). Upload it on the teaching staff desk.");
  assert.equal(on(JUNIOR_HEAD.filter((h) => h !== "CURRENT POSTING"), "ACADEMIC"), "This is the junior staff roll (JP-NO). Upload it on the non-academic staff desk.");
  assert.equal(on(SENIOR_HEAD.map((h) => (h === "CURRENT POSTING" ? "Current  posting" : h)), "ACADEMIC"),
    "This is the senior non-teaching staff roll (Current posting). Upload it on the non-academic staff desk.");
  for (const head of [ACADEMIC_HEAD, SENIOR_HEAD, JUNIOR_HEAD, OLD_LECTURER_HEAD, OLD_STAFF_HEAD]) {
    for (const kind of ["ACADEMIC", "NON_ACADEMIC"] as const) assert.ok(((on(head, kind) ?? "").match(/JP-NO/g) ?? []).length <= 1, `${head.join(",")} on ${kind}`);
  }
  assert.equal(on(["PNO", "Full Names", "Department"], "ACADEMIC"), null, "an old sheet that does not say is taken on either desk");
  assert.equal(on(["PNO", "Full Names", "Department"], "NON_ACADEMIC"), null);
  assert.equal(rollName(rollHeader(OLD_LECTURER_HEAD)!), "the old teaching-staff sheet");
  assert.equal(rollName(rollHeader(OLD_STAFF_HEAD)!), "the old non-teaching sheet");
});

test("a row becomes the roll's keys and its row number; blank, title and repeated heading rows are passed over", () => {
  const grid = [
    ["NOVEMBER 2026 NOMINAL ROLL - SENIOR NON-TEACHING STAFF"],
    JUNIOR_HEAD,
    ["1", "Ada", "Ngozi", "Okafor", "99858", "F", "01/02/1980", "ada@example.com", "08031234567", "Gboko", "Benue", "1/2/2010", "NA", "(Transfer of Service) Another University", "CLERK", "BURSARY"],
    ["", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""],
    ["WORKS DEPARTMENT", "", "", "", "", "", "", "", "", "", "", "", "", "", "", ""],
    JUNIOR_HEAD,
    ["2", "Musa", "", "Bello", "JP99859", "M", "29221", "", "", "", "", "1990", "", "", "DRIVER", "WORKS"],
    ["", "Hauwa", "", "Sani", "", "F", "", "", "", "", "", "", "", "", "", "WORKS"],
  ];
  const r = readRoll(grid);
  assert.ok(r);
  assert.equal(r.headerRow, 2);
  assert.deepEqual(r.rows.map((x) => x.sheet_row), [3, 7, 8], "a named row without a number is sent: the upload reports it");
  assert.deepEqual(r.rows[0], {
    sheet_row: 3, first_name: "Ada", middle_name: "Ngozi", last_name: "Okafor", jp_no: "99858", sex: "F", date_of_birth: "01/02/1980",
    email: "ada@example.com", phone: "08031234567", lga: "Gboko", state: "Benue", date_first_appointment: "1/2/2010", date_of_confirmation: "NA",
    date_of_last_promotion: "(Transfer of Service) Another University", present_rank: "CLERK", posting: "BURSARY",
  });
  assert.equal(r.rows[1].date_of_birth, "01/01/1980", "a date Excel holds as a serial is written day first");
  assert.equal(r.rows[1].date_first_appointment, "1990", "a year alone is not taken for a serial");
  assert.deepEqual(rollNumbers(r), ["JP99858", "JP99859"]);
  assert.equal(excelDate("44197"), "01/01/2021");
  assert.equal(excelDate(" 25/12/1970 "), "25/12/1970");
});

test("a staff number the file already gave is held back and reported as the database reports it", () => {
  const r = readRoll([ACADEMIC_HEAD, ["1", "A", "", "One", "99029", "M"], ["2", "B", "", "Two", "P99029", "F"], ["3", "C", "", "Three", "99030", "F"]]);
  assert.ok(r);
  assert.deepEqual(r.rows.map((x) => x.pno), ["99029", "99030"]);
  assert.equal(r.repeats.length, 1);
  assert.deepEqual([r.repeats[0].row, r.repeats[0].staffNumber, r.repeats[0].action, r.repeats[0].error], [3, "P99029", "ERROR", "P99029 is on this upload already, at row 2"]);
  const t = emptyTally(true, r.repeats);
  assert.deepEqual([t.rows, t.errors, t.firstError], [1, 1, "Row 3 (P99029): P99029 is on this upload already, at row 2"]);
  assert.equal(r.repeats[0].name, "One, A", "named as the row that gave the number first");
  const after = addChunk(t, { rows: 2, created: 0, updated: 1, unchanged: 1, skipped: 0, errors: 0, results: [
    res({ row: 2, staffNumber: "P99029", name: "ZZONE, Ada", action: "UPDATED" }), res({ row: 4, staffNumber: "P99030", name: "ZZTHREE, C", action: "UNCHANGED" }),
  ] });
  assert.equal(after.results.find((x) => x.row === 3)?.name, "ZZONE, Ada", "then as the upload named that first row");
  // a row that failed earlier in the file comes first, though the repeat was found before any request was sent
  const failed = addChunk(after, { rows: 1, errors: 1, results: [res({ row: 1, staffNumber: null, action: "ERROR", error: "no staff number (PNO or JP-NO) on the row" })] });
  assert.equal(failed.firstError, "Row 1: no staff number (PNO or JP-NO) on the row");
});

test("a row with no staff number is sent when it holds more than one cell (the upload reports it); a one-cell title row is passed over", () => {
  const blank = Array(17).fill("");
  const r = readRoll([ACADEMIC_HEAD,
    Object.assign([...blank], { 1: "SENIOR LECTURERS" }),
    Object.assign([...blank], { 5: "M", 14: "LECTURER I", 15: "ACCOUNTING" }),
    Object.assign([...blank], { 0: "3", 1: "Ada", 3: "ZZROW", 4: "99031" })]);
  assert.ok(r);
  assert.deepEqual(r.rows.map((x) => [x.sheet_row, x.pno ?? "", x.present_rank ?? ""]), [[3, "", "LECTURER I"], [4, "99031", ""]]);
});

test("an old sheet's rows keep its keys, so it still loads", () => {
  const r = readRoll([["PNO", "Full Names", "Sex", "Date of 1st Appt", "Department", "Present Rank", "Phone No", "CONTISS"],
    ["997561", "ADAKU NKECHI ZZSAMPLE", "F", "15/06/2003", "OFFICE OF THE REGISTRAR", "EXECUTIVE OFFICER", "08030000561", "CONSOLIDATED"]]);
  assert.ok(r);
  assert.equal(r.header.roll, false);
  assert.deepEqual(r.rows[0], { sheet_row: 2, pno: "997561", full_names: "ADAKU NKECHI ZZSAMPLE", sex: "F", date_first_appointment: "15/06/2003",
    department: "OFFICE OF THE REGISTRAR", present_rank: "EXECUTIVE OFFICER", phone: "08030000561", contiss: "CONSOLIDATED" });
});

const res = (over: Partial<RollResult>): RollResult => ({ row: 2, staffNumber: "P1", name: "ONE, A", action: "UPDATED", changes: [], kept: [], unresolved: [], error: null, ...over });

test("the chunks' answers are summed and their results kept in order", () => {
  let t = emptyTally(false);
  t = addChunk(t, { rows: 2, created: 1, existing: 1, credentialed: 1, granted: 1, records: 2, no_department: 0, skipped: 0, first_error: null,
    missing_departments: null, updated: 1, unchanged: 0, errors: 0, results: [res({ row: 3 }), res({ row: 2, action: "CREATED" })] });
  t = addChunk(t, { rows: 2, created: 0, records: 0, unplaced: 2, skipped: 1, errors: 1, first_error: "Row 9 (P9): no unit", unplaced_units: "ULIS, CALM",
    updated: 0, unchanged: 0, results: [res({ row: 9, action: "SKIPPED", error: "no unit" }), res({ row: 8, action: "ERROR", error: "x", changes: undefined as never })] });
  t = chunkFailed(t, 25, "Gateway timeout");
  assert.deepEqual([t.rows, t.created, t.updated, t.skipped, t.errors, t.credentialed, t.granted, t.notPlaced, t.failedRows],
    [4, 1, 1, 1, 1, 1, 1, 2, 25]);
  assert.deepEqual(t.missing, ["ULIS", "CALM"]);
  assert.equal(t.firstError, "Row 8 (P1): x", "the first problem by row, whichever request it came in");
  assert.equal(t.results.length, 4);
  assert.deepEqual(t.results[3].changes, [], "a result without its lists is given empty ones");
});

test("the words for actions, changes, contacts kept and what did not resolve", () => {
  assert.equal(actionWord("CREATED"), "Added");
  assert.equal(actionWord("CREATED", true), "New: to be added");
  assert.equal(actionWord("UPDATED", true), "To be updated");
  assert.equal(actionWord("SKIPPED"), "Not loaded");
  assert.equal(changeText({ field: "date_of_birth", from: null, to: "1970-12-25" }), "Date of birth: — → 25/12/1970");
  assert.equal(changeText({ field: "home_department", from: "ACCOUNTING", to: "BUSINESS ADMINISTRATION" }), "Department: ACCOUNTING → BUSINESS ADMINISTRATION");
  assert.equal(keptText({ field: "email", onRecord: "a@x.ng", onRoll: "b@x.ng", reason: "DIFFERS" }), "E-mail: the roll's b@x.ng differs from the one on the portal, which is kept (a@x.ng)");
  assert.equal(keptText({ field: "phone", onRecord: null, onRoll: "0803", reason: "NOT_A_PHONE" }), "Phone: the roll's 0803 could not be read as a phone number (0 and ten digits, or +234 and ten)");
  assert.match(keptText({ field: "sign_in", onRecord: null, onRoll: "p6", reason: "USERNAME_TOO_SHORT" }), /^Sign-in: .*no sign-in was made$/);
  // V761: someone on record keeps what the record holds — a detail, the posting (once, by place) and the lecturer office
  assert.equal(keptText({ field: "present_rank", onRecord: "LECTURER II", onRoll: "LECTURER I", reason: "DIFFERS" }),
    "Present rank: the roll's LECTURER I differs from the one on the portal, which is kept (LECTURER II)");
  assert.equal(keptText({ field: "posting", onRecord: "Bursary Department", onRoll: "Human Anatomy", reason: "DIFFERS" }),
    "Current posting: the roll's Human Anatomy differs from the one on the portal, which is kept (Bursary Department)");
  assert.equal(keptText({ field: "lecturer_office", onRecord: "Mathematics and Computer Science", onRoll: "Accounting", reason: "OFFICE_KEPT" }),
    "Lecturer office stays in Mathematics and Computer Science: the roll places them in Accounting — an upload moves no office (move it on the Edit form)");
  assert.equal(keptText({ field: "grade", onRecord: "CONSOLIDATED", onRoll: "CONTISS step 7", reason: "DIFFERS" }),
    "Salary scale and step: the roll's CONTISS step 7 differs from the one on the portal, which is kept (CONSOLIDATED)");
  assert.equal(keptText({ field: "home_faculty", onRecord: "Science", onRoll: "Arts", reason: "NOT_THE_DEPARTMENTS" }),
    "Faculty: the roll's Arts is not the faculty the portal holds the department under, so it is not written (Science)");
  assert.equal(unresolvedText({ field: "department", onRoll: "ULIS" }), "Department: ULIS is not on the portal");
  assert.equal(unresolvedText({ field: "posting", onRoll: null }), "Current posting: blank");
  assert.equal(unresolvedText({ field: "date_of_birth", onRoll: "31/02/1970" }), "Date of birth: 31/02/1970 could not be read");
});

test("the lecturer office moved with a department, a name left blank or written as a query, and words the screen does not know", () => {
  assert.equal(changeText({ field: "lecturer_office", from: "ACCOUNTING", to: "ADVERTISING" }), "Lecturer office moved: ACCOUNTING → ADVERTISING");
  assert.equal(changeText({ field: "lecturer_office", from: null, to: "ADVERTISING" }), "Lecturer office moved: — → ADVERTISING");
  assert.equal(unresolvedText({ field: "first_name", reason: "BLANK" }), "First name blank on the roll — kept as on record");
  assert.equal(unresolvedText({ field: "middle_name", onRoll: null, reason: "BLANK" }), "Middle name blank on the roll — kept as on record");
  assert.equal(unresolvedText({ field: "surname", onRoll: "", reason: "BLANK" }), "Surname blank on the roll — kept as on record");
  assert.equal(unresolvedText({ field: "middle_name", onRoll: "ADA? EZE?", reason: "QUERY" }), "Middle name on the roll is a query (ADA? EZE?) — not written");
  assert.equal(unresolvedText({ field: "first_name", onRoll: "ADA or ADAEZE", reason: "QUERY" }), "First name on the roll is a query (ADA or ADAEZE) — not written");
  assert.equal(unresolvedText({ field: "surname", reason: "QUERY" }), "Surname on the roll is a query — not written");
  assert.equal(unresolvedText({ field: "first_name", onRoll: "DR.", reason: "BLANK" }), "First name on the roll (DR.) holds no name — kept as on record");
  assert.deepEqual(claimedBy([res({ staffNumber: "P99030", changes: [{ field: "email", from: null, to: "A@Example.test" }] })], { "b@example.test": "P99029" }),
    { "b@example.test": "P99029", "a@example.test": "P99030" });
  assert.deepEqual(addOutcome({ results: [res({ action: "UNCHANGED" })] }, "P1"), { existing: true, action: "UNCHANGED", text: "P1 is already on record as entered: nothing changed." });
  assert.deepEqual(addOutcome({ results: [res({ action: "UPDATED", unresolved: [{ field: "given_names", onRoll: "Pet?er", reason: "QUERY" }] })] }, "P1"),
    { existing: true, action: "UPDATED", text: "P1 was already on record, so the record was updated (Given names typed (Pet?er) read as a query — not written)." });
  assert.deepEqual(addOutcome({ results: [res({ action: "UNCHANGED", unresolved: [{ field: "given_names", onRoll: "Dr.", reason: "BLANK" }] })] }, "P1"),
    { existing: true, action: "UNCHANGED", text: "P1 is already on record: nothing changed (Given names typed (Dr.) holds no name — not written)." });
  assert.deepEqual(addOutcome({ results: [res({ action: "CREATED" })] }, "P1"), { existing: false, text: "P1 added.", action: "CREATED" });
  // someone on record whom an Add would rename: the form is told both names first
  const renaming = addCheck({ results: [res({ action: "UPDATED", name: "ZZNEWHIRE, Ada", changes: [
    { field: "surname", from: "ZZADMIN", to: "ZZNEWHIRE" }, { field: "given_names", from: "Ngozi", to: "Ada" }] })] });
  assert.deepEqual(renaming, { ok: true, existing: true, staffNumber: "P1", renames: { from: "ZZADMIN, Ngozi", to: "ZZNEWHIRE, Ada" } });
  const givenOnly = addCheck({ results: [res({ action: "UPDATED", name: "ZZSAME, Ada", changes: [{ field: "given_names", from: "Ngozi", to: "Ada" }] })] });
  assert.deepEqual(givenOnly.ok && givenOnly.renames, { from: "ZZSAME, Ngozi", to: "ZZSAME, Ada" });
  assert.deepEqual(addOutcome({ results: [res({ action: "UPDATED", changes: [{ field: "present_rank", from: "CLERK", to: "SENIOR CLERK" }] })] }, "P1"),
    { existing: true, action: "UPDATED", text: "P1 was already on record, so the record was updated: Present rank: CLERK → SENIOR CLERK." });
  assert.deepEqual(addOutcome({ results: [res({ action: "CREATED", kept: [
    { field: "email", onRecord: null, onRoll: "ada.zz@example", reason: "NOT_AN_EMAIL" },
    { field: "sign_in", onRecord: null, onRoll: "p1", reason: "USERNAME_TOO_SHORT" }] })] }, "P1"),
    { existing: false, action: "CREATED", text: "P1 added (E-mail typed (ada.zz@example) is not an e-mail address — not written; no sign-in made: the staff id is shorter than three characters)." });
  assert.deepEqual(addOutcome({ results: [res({ action: "UNCHANGED", kept: [{ field: "email", onRecord: "a@x.test", onRoll: "b@x.test", reason: "DIFFERS" }] })] }, "P1"),
    { existing: true, action: "UNCHANGED", text: "P1 is already on record: nothing changed (E-mail typed (b@x.test) differs from the one on record (a@x.test), which is kept)." });
  assert.equal(keptText({ field: "email", onRecord: null, onRoll: "a@example.test", reason: "GIVEN_TO_ANOTHER_ROW", givenTo: "JP99858" }),
    "E-mail: the roll's a@example.test is given to another row of this file (JP99858), so it is written for that row only");
  assert.equal(unresolvedText({ field: "full_names", onRoll: "Mrs Ngozi Ada or Adaeze?", reason: "QUERY" }),
    "Full Names on the roll is a query (Mrs Ngozi Ada or Adaeze?) — not written");
  // a field or a reason these words do not know is still shown, as given
  assert.equal(unresolvedText({ field: "blood_group", onRoll: "O?", reason: "SOMETHING_NEW" }), "Blood group: the roll's O? not written (SOMETHING_NEW)");
  assert.equal(unresolvedText({ field: "first_name", onRoll: "ADA", reason: "SOMETHING_NEW" }), "First name: the roll's ADA not written (SOMETHING_NEW)");
  assert.equal(unresolvedText({ field: "lga", reason: "BLANK" }), "LGA: blank on the roll — kept as on record");
  assert.equal(unresolvedText({ field: "new_cell", onRoll: "x" }), "New cell: x could not be read");
  assert.equal(changeText({ field: "new_field", from: "a", to: "b" }), "New field: a → b");
  assert.equal(keptText({ field: "email", onRecord: "a@x.ng", onRoll: "b@x.ng", reason: "SOMETHING_NEW" }), "E-mail: the roll's b@x.ng was not written (SOMETHING_NEW)");
});

test("a number on record as the other kind of staff is an error like any other: in the check, on the result sheet with its row, and on the Add form", () => {
  const error = "P99029 is on record as teaching staff: they are loaded on the teaching staff desk";
  let t = emptyTally(true);
  t = addChunk(t, { rows: 2, created: 0, updated: 1, unchanged: 0, skipped: 0, errors: 1, first_error: `Row 7 (P99029): ${error}`, results: [
    res({ row: 7, staffNumber: "P99029", action: "ERROR", error }),
    res({ row: 3, staffNumber: "P99030", changes: [{ field: "home_department", from: "Accounting", to: "Advertising" }, { field: "lecturer_office", from: "Accounting", to: "Advertising" }],
      unresolved: [{ field: "middle_name", reason: "BLANK" }] }),
  ] });
  assert.deepEqual([t.errors, t.firstError], [1, `Row 7 (P99029): ${error}`]);
  const s = resultSheet(t, null);
  assert.deepEqual(s.rows.map((r) => [r[0], r[1], r[3], r[7]]), [[3, "P99030", "To be updated", ""], [7, "P99029", "Error", error]]);
  assert.equal(s.rows[0][4], "Department: Accounting → Advertising; Lecturer office moved: Accounting → Advertising");
  assert.equal(s.rows[0][6], "Middle name blank on the roll — kept as on record");
  assert.deepEqual(addCheck({ rows: 1, results: [res({ staffNumber: "P99029", action: "ERROR", error })] }),
    { ok: false, title: "That member of staff could not be added.", detail: error });
});

test("an Add form's check: someone new loads, someone on record the list does not show loads, a row that would not load says why", () => {
  const one = (r: Partial<RollResult>) => ({ rows: 1, results: [res(r)] });
  assert.deepEqual(addCheck(one({ action: "CREATED", staffNumber: "JP99858" })), { ok: true, existing: false, staffNumber: "JP99858" });
  assert.deepEqual(addCheck(one({ action: "UPDATED", changes: [{ field: "category", from: null, to: "NON_ACADEMIC" }] })),
    { ok: true, existing: true, staffNumber: "P1" }, "on record with no establishment record of either kind: it loads");
  assert.deepEqual(addCheck(one({ action: "UNCHANGED" })), { ok: true, existing: true, staffNumber: "P1" });
  // the database reads who is teaching staff (hrm.roll_kind) and refuses the other kind itself: a category it lets change, loads
  assert.deepEqual(addCheck(one({ action: "UPDATED", changes: [{ field: "category", from: "NON_ACADEMIC", to: "ACADEMIC" }] })),
    { ok: true, existing: true, staffNumber: "P1" });
  const other = addCheck(one({ action: "ERROR", error: "P1 is on record as teaching staff: they are loaded on the teaching staff desk" }));
  assert.deepEqual(other, { ok: false, title: "That member of staff could not be added.", detail: "P1 is on record as teaching staff: they are loaded on the teaching staff desk" });
  const skipped = addCheck(one({ action: "SKIPPED", error: "no department matching X is on the portal" }));
  assert.deepEqual(skipped, { ok: false, title: "That member of staff could not be added.", detail: "no department matching X is on the portal" });
  assert.equal(addCheck({ rows: 0, results: [] }).ok, false, "a row the upload did not read");
  assert.equal(addCheck(null).ok, false);
});

test("the result as a sheet: every row in row order, then the staff not on the roll", () => {
  let t = emptyTally(false);
  t = addChunk(t, { rows: 2, results: [res({ row: 5, changes: [{ field: "surname", from: "OKAFOR", to: "OKAFOR-EZE" }] }), res({ row: 2, action: "UNCHANGED" })] });
  const s = resultSheet(t, [{ person_id: "x", staff_number: "P77", name: "ABSENT, ONE", rank: "LECTURER I", posting: "ACCOUNTING" }]);
  assert.equal(s.headers[3], "What happened");
  assert.equal(s.headers[5], "Not written");
  assert.deepEqual(s.rows.map((r) => [r[0], r[3]]), [[2, "Unchanged"], [5, "Updated"], ["", "On the portal, not on this roll"]]);
  assert.equal(s.rows[1][4], "Surname: OKAFOR → OKAFOR-EZE");
  assert.equal(s.rows[2][4], "LECTURER I · ACCOUNTING");
  assert.equal(resultSheet(emptyTally(true), null).headers[3], "What the upload will do");
});

const W = (body: string) => `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>${body}</w:body></w:document>`;
const tc = (text: string, pr = "") => `<w:tc><w:tcPr><w:tcW w:w="100" w:type="dxa"/>${pr}</w:tcPr><w:p><w:pPr><w:tabs><w:tab w:val="left" w:pos="720"/></w:tabs></w:pPr><w:r><w:t xml:space="preserve">${text}</w:t></w:r></w:p></w:tc>`;
const tr = (...cells: string[]) => `<w:tr><w:trPr><w:tblHeader/></w:trPr>${cells.join("")}</w:tr>`;

test("a Word table's cells are their runs joined, whitespace collapsed; spans and nested tables keep the columns under their headings", () => {
  const xml = W(
    `<w:p><w:r><w:t>NOVEMBER 2026 NOMINAL ROLL</w:t></w:r></w:p>` +
    `<w:tbl><w:tblPr><w:tblW w:w="0"/></w:tblPr><w:tblGrid><w:gridCol/></w:tblGrid>` +
    tr(tc("SNO"), tc("FIRST NAME"), tc("LAST-SURNAME")) +
    `<w:tr><w:tc><w:p><w:r><w:t>1</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Ad</w:t></w:r><w:r><w:t>a  </w:t></w:r><w:r><w:tab/><w:t>Ngozi</w:t></w:r></w:p><w:p><w:r><w:t>Jr</w:t></w:r><w:r><w:br/><w:delText>gone</w:delText><w:t>&amp; Co</w:t></w:r></w:p></w:tc>${tc("O&apos;Neil")}</w:tr>` +
    `<w:tr>${tc("WORKS", `<w:gridSpan w:val="2"/>`)}${tc("x")}</w:tr>` +
    `<w:tr><w:trPr><w:gridBefore w:val="1"/></w:trPr>${tc("b")}${tc("c")}</w:tr>` +
    `<w:tr>${tc("2")}<w:tc><w:tbl><w:tr>${tc("in")}${tc("side")}</w:tr></w:tbl><w:p/></w:tc>${tc("z")}</w:tr>` +
    `</w:tbl><w:p><w:r><w:t>Signed</w:t></w:r></w:p>`);
  assert.deepEqual(wordTables(xml), [[
    ["SNO", "FIRST NAME", "LAST-SURNAME"],
    ["1", "Ada Ngozi Jr & Co", "O'Neil"],
    ["WORKS", "", "x"],
    ["", "b", "c"],
    ["2", "in side", "z"],
  ]]);
});

test("a .docx is read through the ZIP helpers of lib/xlsx.ts; a roll split over two tables is one grid", async () => {
  const enc = new TextEncoder();
  const body = W(
    `<w:tbl>${tr(...ACADEMIC_HEAD.map((h) => tc(h)))}${tr(...["1", "Ada", "", "Okafor", "99029", "F"].map((v) => tc(v)), ...Array(11).fill(tc("")))}</w:tbl>` +
    `<w:p/><w:tbl>${tr(...ACADEMIC_HEAD.map((h) => tc(h)))}${tr(...["2", "Musa", "", "Bello", "99030", "M"].map((v) => tc(v)), ...Array(11).fill(tc("")))}</w:tbl>` +
    `<w:tbl>${tr(...["3", "Ngozi", "", "Eze", "99031", "F"].map((v) => tc(v)), ...Array(11).fill(tc("")))}</w:tbl>`);
  const docx = zip([{ name: "[Content_Types].xml", data: enc.encode("<Types/>") }, { name: "word/document.xml", data: enc.encode(body) }]);
  const tables = await docxTables(ab(docx));
  assert.equal(tables.length, 3);
  const grid = rollGridFromTables(tables);
  const r = readRoll(grid);
  assert.ok(r);
  assert.equal(r.header.kind, "ACADEMIC");
  assert.deepEqual(r.rows.map((x) => [x.sheet_row, x.pno, x.last_name]), [[2, "99029", "Okafor"], [4, "99030", "Bello"], [5, "99031", "Eze"]]);
  await assert.rejects(docxTables(ab(enc.encode("not a zip at all, just text"))), /not a Word document/);
  const noDoc = zip([{ name: "xl/workbook.xml", data: enc.encode("<workbook/>") }]);
  await assert.rejects(docxTables(ab(noDoc)), /no document part/);
});

const ROLLS = "C:/Users/ajene/Downloads/NOVEMBER 2026 NOMINAL ROLL-";
const real = (name: string) => `${ROLLS}${name}.docx`;
const present = ["Academic Staff", "Senior Non-Teaching Staff", "Junior Staff"].every((n) => existsSync(real(n)));

test("the three rolls as issued are read whole (read-only; skipped where the files are not on this machine)", { skip: !present && "the November 2026 rolls are not in Downloads" }, async () => {
  for (const [name, kind, junior, rows, cols] of [
    ["Academic Staff", "ACADEMIC", false, 645, 17], ["Senior Non-Teaching Staff", "NON_ACADEMIC", false, 872, 16], ["Junior Staff", "NON_ACADEMIC", true, 197, 16],
  ] as const) {
    const grid = rollGridFromTables(await docxTables(ab(readFileSync(real(name)))));
    assert.equal(grid[0].length, cols, `${name}: ${cols} columns`);
    const r = readRoll(grid);
    assert.ok(r, `${name}: the heading row is recognised`);
    assert.deepEqual([r.header.kind, r.header.junior, r.rows.length, r.repeats.length], [kind, junior, rows, 0], name);
    const numbers = rollNumbers(r);
    assert.equal(numbers.length, rows, `${name}: one staff number a row`);
    assert.ok(numbers.every((n) => (junior ? /^JP\d+$/ : /^P\d+$/).test(n)), `${name}: every number in its series`);
    assert.ok(r.rows.every((x) => x.sheet_row >= 2), `${name}: row numbers below the heading`);
  }
});
