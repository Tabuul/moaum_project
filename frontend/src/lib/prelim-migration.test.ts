import { test } from "node:test";
import assert from "node:assert/strict";
import {
  SHEET, changeFactsOf, figuresOf, fileNameOf, firstProblem, historyLines, legacyFeeOf, mayConfirmNew, otherRoute, progressWords, ranges, readFile, readSheets,
  reasonOk, reportLines, routeChangeOf, rowLink, rowsOf, safeCell, templateOf, templateSheets, words, type Column, type MigrationRow, type TemplateData,
} from "./prelim-migration.ts";
import { colName, xlsx } from "./xlsx-write.ts";

/** the columns as the server's prelim_migration_columns gives them (made up here; Science has no specialisation) */
function columns(route: string, sittings = 2): Column[] {
  const c = (key: string, header: string, section: string, required = false, choices: string[] | null = null): Column => ({ key, header, section, required, note: null, choices });
  const out = [
    c("legacyApplicationNo", "Application Number", "Applicant", true), c("jambRegNo", "JAMB Registration Number", "Applicant"),
    c("surname", "Surname", "Applicant", true), c("firstName", "First Name", "Applicant", true), c("otherNames", "Other Names", "Applicant"),
    c("gender", "Gender", "Applicant", true, ["Male", "Female"]), c("dateOfBirth", "Date of Birth", "Applicant", true), c("email", "Email Address", "Contact"),
    c("phone", "Phone Number", "Contact", true), c("programme", "Programme", "Programme"), c("target", "Intended Programme", "Programme"),
    ...(route === "PRELIMINARY_TECHNOLOGY" ? [c("specialisation", "Specialisation", "Programme")] : []),
    c("examinationNumber", "Examination Number", "Programme"),
  ];
  for (let n = 1; n <= sittings; n++) {
    out.push(c(`olevel${n}Body`, `O'Level ${n} Examination Type`, `O'Level sitting ${n}`, false, ["WAEC", "NECO", "NABTEB", "OTHER"]),
      c(`olevel${n}Qualification`, `O'Level ${n} Qualification`, `O'Level sitting ${n}`), c(`olevel${n}Year`, `O'Level ${n} Examination Year`, `O'Level sitting ${n}`),
      c(`olevel${n}Number`, `O'Level ${n} Examination Number`, `O'Level sitting ${n}`), c(`olevel${n}Results`, `O'Level ${n} Subjects and Grades`, `O'Level sitting ${n}`));
  }
  out.push(c("applicationDate", "Application Date", "Payment"), c("paymentReference", "Application Payment Reference", "Payment"),
    c("amountPaid", "Application Fee Paid", "Payment"), c("paymentStatus", "Payment Status", "Payment", false, ["Paid", "Not Paid", "Pending"]),
    c("applicationStatus", "Application Status", "Status", true), c("admissionStatus", "Admission Status", "Status"));
  return out;
}
const template = (route: string): TemplateData => ({
  route, name: route === "PRELIMINARY_TECHNOLOGY" ? "Preliminary Technology & Industrial Studies" : "Preliminary Science", session: "2026/2027", maxSittings: 2,
  columns: columns(route),
  targets: route === "PRELIMINARY_TECHNOLOGY"
    ? [{ id: "t1", name: "Engineering Area", code: "C90001", group: "Engineering", specialisations: [{ code: "MECH", name: "Mechanical" }, { code: "ELEC", name: "Electrical" }] }]
    : [{ id: "t2", name: "B.Sc. Example Science", code: "C90002", group: "Science", specialisations: [] }],
  qualifications: [{ code: "SSCE", label: "Senior School Certificate" }, { code: "GCE", label: "GCE" }],
  examBodies: ["WAEC", "NECO"], subjects: ["English Language", "Mathematics", "Biology"], grades: ["A1", "B2", "B3", "C4", "C5", "C6", "D7", "E8", "F9"],
  statusWords: {
    application: ["not submitted", "draft", "incomplete", "started", "submitted", "completed", "complete", "pending", "under review", "screening", "being screened", "in review", "withdrawn"],
    admission: ["admitted", "offered", "admission offered", "accepted", "admission accepted", "not admitted", "rejected", "not offered", "declined", "pending", "not yet", "awaiting", "none"],
    payment: ["paid", "not paid"],
  },
  fee: { application: 5000, portal: 0, stated: true },
});

test("each programme's template: the data sheet under a letterhead, required columns marked, the drop-downs, and its own lists", () => {
  const t = template("PRELIMINARY_TECHNOLOGY");
  t.statusWords = { ...t.statusWords, admission: [...words(t.statusWords?.admission), ...Array.from({ length: 12 }, (_, i) => `another old portal word ${i}`)] };
  const tech = templateSheets(t, "THE UNIVERSITY");
  const sci = templateSheets(template("PRELIMINARY_SCIENCE"), "THE UNIVERSITY");
  const names = (s: typeof tech) => s.map((x) => x[0]);
  assert.deepEqual(names(tech).slice(0, 5), [SHEET.data, SHEET.instructions, SHEET.sample, SHEET.dictionary, SHEET.targets]);
  assert.ok(names(tech).includes(SHEET.specialisations));
  assert.ok(!names(sci).includes(SHEET.specialisations), "Science has no specialisations");
  const header = (s: typeof tech) => s[0][1].find((r) => r[0] === "S/N")!;
  assert.equal(header(tech)[1], "Application Number *");
  assert.ok(header(tech).includes("Specialisation"));
  assert.ok(!header(sci).includes("Specialisation"), "Science has no Specialisation column");
  assert.ok(header(sci).includes("O'Level 2 Subjects and Grades"));
  const v = tech[0][2]!.validations!;
  const at = (k: string) => {
    const i = template("PRELIMINARY_TECHNOLOGY").columns.findIndex((c) => c.key === k) + 1;   // S/N is column A
    return v.find((x) => x.sqref === `${colName(i)}7:${colName(i)}2006`);
  };
  assert.deepEqual(at("gender")?.list, ["Male", "Female"]);
  assert.equal(at("target")?.range, "'Targets'!$A$2:$A$2");
  assert.equal(at("specialisation")?.range, "'Specialisations'!$C$2:$C$3");
  assert.deepEqual(at("olevel1Body")?.list, ["WAEC", "NECO", "NABTEB", "OTHER"]);
  assert.deepEqual(at("olevel1Qualification")?.list, ["SSCE", "GCE"], "the route's qualifications");
  assert.deepEqual(at("paymentStatus")?.list, ["Paid", "Not Paid", "Pending"], "the column's own choices first");
  assert.ok(at("applicationStatus")?.list?.includes("Under Review"), "the old portal's words, title-cased");
  assert.ok(at("admissionStatus")?.range?.startsWith("'Lists'!"), "a list too long for Excel's inline list goes to the Lists sheet");
  assert.ok(names(tech).includes(SHEET.lists));
  const evil = template("PRELIMINARY_SCIENCE");
  evil.targets = [{ id: "x", name: "=HYPERLINK(\"http://x\")", code: "C90003", group: "+Group", specialisations: [] }];
  const targets = templateSheets(evil, "THE UNIVERSITY").find((s) => s[0] === SHEET.targets)![1];
  assert.deepEqual(targets[1], ["'=HYPERLINK(\"http://x\")", "C90003", "'+Group"], "a name from the portal's data is written as text");
  const sample = tech[2][1];
  assert.ok(String(sample[1][1]).includes("ILLUSTRATIVE"));
  const dict = tech[3][1];
  assert.ok(dict.some((r) => r[1] === "Application Number" && r[2] === "Yes"));
  assert.ok(dict.some((r) => r[1] === "Payment Status" && String(r[6]).includes("Bursary")));
  const ins = JSON.stringify(tech[1][1]);
  for (const words of ["DD/MM/YYYY", "YYYY-MM-DD", "S/N column is for presentation only", "Subject:Grade; Subject:Grade", "upload section", "Bursary verifies"]) assert.ok(ins.includes(words), words);
});

test("the sample's first row takes its intended programme and its specialisation from one target, whatever the targets' order", () => {
  const t = template("PRELIMINARY_TECHNOLOGY");
  t.targets = [{ id: "h", name: "B.Sc. (ED) Home Economics", code: "C90010", group: "Education", specialisations: [] },
    { id: "b", name: "B.Sc. (ED) Business Education", code: "C90011", group: "Education", specialisations: [{ code: "ACC", name: "Accounting Education" }] }];
  const sample = templateSheets(t, "THE UNIVERSITY").find((s) => s[0] === SHEET.sample)![1];
  const head = sample.findIndex((r) => r[0] === "S/N");
  const col = (h: string) => sample[head].indexOf(h);
  assert.deepEqual([sample[head + 1][col("Intended Programme")], sample[head + 1][col("Specialisation")]], ["B.Sc. (ED) Business Education", "Accounting Education"]);
  const sci = template("PRELIMINARY_SCIENCE");
  const plain = templateSheets(sci, "THE UNIVERSITY").find((s) => s[0] === SHEET.sample)![1];
  const h2 = plain.findIndex((r) => r[0] === "S/N");
  assert.equal(plain[h2 + 1][plain[h2].indexOf("Intended Programme")], "B.Sc. Example Science", "no target with specialisations: the first target");
});

test("a row's Open goes where the reader may follow it: the correction of a programme conflict, the desk at the application's own programme and session, the corrections, or nowhere", () => {
  const row = { application_id: "a1", application_no: "APP/26/000021", problems: [], appRoute: null, appSession: null };
  const all = { desk: true, change: true, corrections: true, routes: ["PRELIMINARY_TECHNOLOGY", "PRELIMINARY_SCIENCE"] };
  assert.equal(rowLink(row, "PRELIMINARY_TECHNOLOGY", all), "/preliminary?route=PRELIMINARY_TECHNOLOGY&q=APP%2F26%2F000021");
  const elsewhere = { ...row, appRoute: "PRELIMINARY_SCIENCE", appSession: "2025/2026" };
  assert.equal(rowLink(elsewhere, "PRELIMINARY_TECHNOLOGY", all), "/preliminary?route=PRELIMINARY_SCIENCE&session=2025%2F2026&q=APP%2F26%2F000021",
    "the application's own programme and session, where the desk finds it");
  const snake = { application_id: "a1", application_no: "APP/26/000021", problems: [], app_route: "PRELIMINARY_SCIENCE" };
  assert.equal(rowLink(snake, "PRELIMINARY_TECHNOLOGY", all)?.includes("route=PRELIMINARY_SCIENCE"), true, "snake_case too");
  const conflict = { ...elsewhere, problems: [{ code: "PROGRAMME_CONFLICT", level: "conflict" as const, message: "Already on the portal under Preliminary Science." }] };
  assert.equal(rowLink(conflict, "PRELIMINARY_TECHNOLOGY", all), "/admissions/preliminary/migration?view=corrections&app=a1", "one who may change the programme corrects it");
  assert.equal(rowLink(conflict, "PRELIMINARY_TECHNOLOGY", { ...all, change: false }), "/preliminary?route=PRELIMINARY_SCIENCE&session=2025%2F2026&q=APP%2F26%2F000021");
  const noDesk = { ...all, desk: false, change: false };
  assert.equal(rowLink(row, "PRELIMINARY_TECHNOLOGY", noDesk), "/admissions/preliminary/migration?view=corrections&app=a1", "no desk: the corrections");
  assert.equal(rowLink(row, "PRELIMINARY_TECHNOLOGY", { ...noDesk, corrections: false }), null, "neither: no link");
  assert.equal(rowLink(elsewhere, "PRELIMINARY_TECHNOLOGY", { desk: true, change: false, corrections: true, routes: ["PRELIMINARY_TECHNOLOGY"] }), null,
    "a programme office reads neither the other programme's desk nor its record");
  assert.equal(rowLink(conflict, "PRELIMINARY_TECHNOLOGY", { desk: true, change: false, corrections: true, routes: ["PRELIMINARY_TECHNOLOGY"] }), null,
    "nor a conflict's application on the other programme");
  assert.equal(rowLink({ ...row, application_id: null, application_no: null }, "PRELIMINARY_TECHNOLOGY", all), null, "a row matched to nothing");
});

test("a filled file reads back by its headings — case, spacing, required marks and an old export's names aside — the S/N column dropped, the sheet row kept", () => {
  const cols = columns("PRELIMINARY_SCIENCE");
  const sheets = [
    { name: SHEET.instructions, rows: [["S/N", "Instruction"], ["1", "Application Number"]] },
    { name: SHEET.sample, rows: [["S/N", "Application Number *", "Surname *"], ["1", "OLD/SAMPLE/1", "Example"]] },
    { name: "Applicants", rows: [["THE UNIVERSITY"], [], ["S/N", "application  NUMBER *", "SURNAME*", "First name", "Sex", "D.O.B", "GSM No", "O’Level 1 Exam Type", "Sitting 2 Grades", "Shoe size"],
      ["1", " OLD/PS/2025/0001 ", "Example", "Ada", "Female", "14/02/2007", "08030000001", "WAEC", "Mathematics:B3", "41"], ["2", "", "", "", "", "", "", "", "", ""],
      ["3", "OLD/PS/2025/0002", "Sample", "Ben", "", "", "", "", "", ""]] },
  ];
  const r = readSheets(sheets, { columns: cols });
  assert.equal(r.sheet, "Applicants", "the sample and the instructions are never read");
  assert.deepEqual(r.unknown, ["Shoe size"]);
  assert.equal(r.rows.length, 2);
  assert.deepEqual(r.rows[0], { legacyApplicationNo: "OLD/PS/2025/0001", surname: "Example", firstName: "Ada", gender: "Female", dateOfBirth: "14/02/2007",
    phone: "08030000001", olevel1Body: "WAEC", olevel2Results: "Mathematics:B3", sheetRow: "4" });
  assert.equal(r.rows[1].sheetRow, "6");
  assert.deepEqual(r.missing, ["Application Status"]);
});

test("a file without the old number's column is named for it; an old export's 'Applicant Name' stands for the names", () => {
  const cols = columns("PRELIMINARY_SCIENCE");
  const none = readSheets([{ name: "S", rows: [["Name", "Email"]] }], { columns: cols });
  assert.equal(none.sheet, null);
  assert.deepEqual(none.missing, ["Application Number"]);
  const full = readSheets([{ name: "S", rows: [["App No", "Applicant Name", "Gender", "Date of Birth", "Phone", "Application Status"], ["P/1", "DOE, Jane", "Female", "01/01/2007", "08030000000", "Submitted"]] }], { columns: cols });
  assert.deepEqual(full.missing, []);
  assert.equal(full.rows[0].fullName, "DOE, Jane");
  assert.equal(full.rows[0].legacyApplicationNo, "P/1");
});

test("the template written to .xlsx reads back as the template: its headings all known, the S/N ignored, and filled rows read", async () => {
  const t = template("PRELIMINARY_TECHNOLOGY");
  const empty = await readFile(xlsx(templateSheets(t, "THE UNIVERSITY")).slice().buffer as ArrayBuffer, t);
  assert.equal(empty.sheet, SHEET.data);
  assert.deepEqual(empty.missing, []);
  assert.deepEqual(empty.unknown, []);
  assert.equal(empty.rows.length, 0);
  const sheets = templateSheets(t, "THE UNIVERSITY");
  const header = sheets[0][1].find((r) => r[0] === "S/N")!;
  const row = header.map((h) => (h === "S/N" ? 1 : h === "Application Number *" ? "=OLD/1" : h === "Surname *" ? "Example" : h === "Phone Number *" ? 8030000001 : null));
  sheets[0][1].push(row);
  const filled = await readFile(xlsx(sheets).slice().buffer as ArrayBuffer, t);
  assert.equal(filled.rows.length, 1);
  assert.equal(filled.rows[0].legacyApplicationNo, "=OLD/1");
  assert.equal(filled.rows[0].phone, "8030000001");
  assert.equal(filled.rows[0].sheetRow, "7");
  assert.equal("S/N" in filled.rows[0], false);
});

test("the file is sent, checked and imported in ranges that cover it once", () => {
  assert.deepEqual(ranges(1201, 500), [[1, 500], [501, 1000], [1001, 1201]]);
  assert.deepEqual(ranges(1, 1000), [[1, 1]]);
  assert.deepEqual(ranges(0, 250), []);
  assert.equal(progressWords("check", 4250, 10000), "Checking 4,250 / 10,000 rows");
});

test("a value that would run as a formula in a report or template is written as text", () => {
  assert.equal(safeCell("=HYPERLINK(\"http://x\")"), "'=HYPERLINK(\"http://x\")");
  assert.equal(safeCell("+234803"), "'+234803");
  assert.equal(safeCell("-1"), "'-1");
  assert.equal(safeCell("@cmd"), "'@cmd");
  assert.equal(safeCell("\tx"), "'\tx");
  assert.equal(safeCell("OLD/PS/1"), "OLD/PS/1");
  assert.equal(safeCell(12), 12);
  assert.equal(safeCell(undefined), null);
});

const row = (over: Partial<MigrationRow>): MigrationRow => ({
  id: "r", row_no: 3, legacy_no: "OLD/1", applicant: "EXAMPLE, Ada", email: null, verdict: "READY", match: "NEW_APPLICANT", action: "CREATE",
  application_id: null, problems: [], decided_new: false, result: null, result_note: null, sheet_row: "9", ...over,
});

test("the error report is a line per problem — the row, the sheet row, the old number, the status, the correction — every cell made safe", () => {
  const lines = reportLines([
    row({ verdict: "ERROR", problems: [{ code: "MISSING_SURNAME", level: "error", message: "The surname is missing.", fix: "Give the surname." }, { code: "JAMB_INVALID", level: "warning", message: "Not a JAMB number." }] }),
    row({ row_no: 5, sheet_row: null, verdict: "READY", result: "FAILED", result_note: "=boom", problems: [] }),
    { row: 7, sheetRow: 12, applicant: "+SAMPLE", legacyNo: "OLD/7", verdict: "CONFLICT", code: "PROGRAMME_MISMATCH", message: "Names Preliminary Science.", fix: "Upload it under Preliminary Science." },
  ]);
  assert.equal(lines.length, 4);
  assert.deepEqual(lines[0], [3, 9, "EXAMPLE, Ada", "OLD/1", "Error", "MISSING_SURNAME", "The surname is missing.", "Give the surname."]);
  assert.deepEqual(lines[1], [3, 9, "EXAMPLE, Ada", "OLD/1", "Error", "JAMB_INVALID", "Not a JAMB number.", ""]);
  assert.deepEqual(lines[2], [5, null, "EXAMPLE, Ada", "OLD/1", "Failed", "IMPORT_FAILED", "'=boom", "Correct the row and upload it again."]);
  assert.deepEqual(lines[3], [7, 12, "'+SAMPLE", "OLD/7", "Conflict", "PROGRAMME_MISMATCH", "Names Preliminary Science.", "Upload it under Preliminary Science."]);
});

test("an officer confirms a new applicant only where a possible same person alone holds the row", () => {
  const possible = { code: "POSSIBLE_SAME_APPLICANT", level: "review" as const, message: "An applicant of the same surname, first name and date of birth…" };
  assert.equal(mayConfirmNew(row({ verdict: "REQUIRES_REVIEW", problems: [possible] })), true);
  assert.equal(mayConfirmNew(row({ verdict: "REQUIRES_REVIEW", problems: [possible, { code: "FEE_REFERENCE_ELSEWHERE", level: "conflict", message: "x" }] })), false);
  assert.equal(mayConfirmNew(row({ verdict: "REQUIRES_REVIEW", problems: [possible], result: "SKIPPED" })), false);
  assert.equal(mayConfirmNew(row({ verdict: "REQUIRES_REVIEW", problems: [possible], decided_new: true })), false);
  assert.equal(firstProblem(row({ problems: [{ code: "W", level: "warning", message: "w" }, { code: "E", level: "conflict", message: "e" }] }))?.code, "E");
});

test("the history reads each upload in words, its cells made safe", () => {
  const [l] = historyLines([{ id: "b", reference: "PRELIM-MIG/2026/000001", route: "PRELIMINARY_SCIENCE", route_name: "Preliminary Science", file_name: "=x.xlsx",
    started_at: "2026-11-12T10:00:00Z", started_by_name: "OFFICER, Invented", started_office: "ict", state: "COMPLETED", rows_expected: 10, created: 4, updated: 1,
    reconciled: 2, unchanged: 1, skipped: 1, failed: 1, fees_held: 3 }]);
  assert.equal(l[0], "PRELIM-MIG/2026/000001");
  assert.equal(l[1], "Preliminary Science");
  assert.equal(l[2], "'=x.xlsx");
  assert.equal(l[4], "OFFICER, Invented (ict)");
  assert.deepEqual(l.slice(5, 13), [10, 8, 4, 3, 1, 1, 1, 3], "successful: created, updated, reconciled or already on record");
  assert.equal(historyLines([{ reference: "R", successful: 2, created: 9 }])[0][6], 2, "the server's count when it gives one");
  assert.equal(l[13], "Completed");
});

test("the server's answers read one way: the template, the correction's check, a correction and an old-portal fee", () => {
  const t = templateOf({ route: "PRELIMINARY_SCIENCE", name: "Preliminary Science", session: "2026/2027", fileName: "X.xlsx", maxSittings: 2,
    columns: [{ key: "gender", header: "Gender", section: "Applicant", required: true, note: null, choices: ["Male", "Female"] }, { key: "x", header: "", section: "" }],
    targets: [{ id: "t", name: "B.Sc. Example", code: "C90002", group: "Science", kind: "PROGRAMME", specialisations: [] }],
    qualifications: [{ code: "SSCE", label: "SSCE" }], examBodies: ["WAEC"], subjects: ["Mathematics"], grades: ["A1"],
    statusWords: { payment: [{ word: "Paid", value: "PAID" }] }, fee: { application: 5000, portal: 0, stated: true } });
  assert.equal(t.columns.length, 1, "a column without a header is not a column");
  assert.deepEqual(t.columns[0].choices, ["Male", "Female"]);
  assert.deepEqual(words(t.statusWords?.payment), ["Paid"]);
  assert.deepEqual(t.fee, { application: 5000, portal: 0, stated: true });
  const c = changeFactsOf({ may: false, refusal: { code: "PRELIM_CHANGE_DECIDED", message: "the application is decided" }, applicationNo: "APP/26/000001",
    legacyNo: "OLD/1", applicantName: "EXAMPLE, Ada", route: "PRELIMINARY_TECHNOLOGY", routeName: "Preliminary Technology & Industrial Studies",
    toRoute: "PRELIMINARY_SCIENCE", toRouteName: "Preliminary Science", state: "APPROVED", stateAfter: "APPROVED", feeStatus: "HELD", feeAmount: 5000,
    feeReferences: ["OLDPAY-1"], toRouteFee: 5000, feeCovers: true, missing: [{ step: "PROGRAMME", field: "target", message: "Choose the target programme under Preliminary Science" }] });
  assert.deepEqual([c.may, c.refusal?.code, c.name, c.fromName, c.toName, c.toState, c.feeStatus, c.feePaid, c.newFee, c.feeCovers],
    [false, "PRELIM_CHANGE_DECIDED", "EXAMPLE, Ada", "Preliminary Technology & Industrial Studies", "Preliminary Science", "APPROVED", "HELD", 5000, 5000, true]);
  assert.deepEqual(c.feeReferences, ["OLDPAY-1"]);
  assert.deepEqual(c.missing, ["Choose the target programme under Preliminary Science"]);
  const ch = routeChangeOf({ reference: "PRELIM-CHG/2026/000001", fromRouteName: "Preliminary Technology & Industrial Studies", toRouteName: "Preliminary Science",
    actor: "OFFICER, Invented", actorOffice: "ict", result: "REFUSED", refusalMessage: "the outcome stands" });
  assert.deepEqual([ch.fromName, ch.toName, ch.by, ch.office, ch.refusal], ["Preliminary Technology & Industrial Studies", "Preliminary Science", "OFFICER, Invented", "ict", "the outcome stands"]);
  const fee = legacyFeeOf({ id: "f", applicationNo: "APP/26/000001", legacyNo: "OLD/1", reference: "OLDPAY-1", amount: "5000.00", state: "REQUIRES_REVIEW", uploadedByYou: true, mayDecide: false });
  assert.deepEqual([fee.reference, fee.amount, fee.uploadedByMe, fee.mayDecide], ["OLDPAY-1", 5000, true, false]);
  assert.equal(legacyFeeOf({ legacy_reference: "OLDPAY-2", paid_on: "2025-01-03" }).reference, "OLDPAY-2", "the desk's snake_case rows too");
});

test("the preview's figures, the pages, the other programme, the file names and the reason a correction takes", () => {
  const f = figuresOf({ rows: 12, ready: 5, warning: 2, invalid: 3, existing: 4, duplicates: 1, newApplicants: 3, toUpdate: 2, paymentsToVerify: 6, programmeConflicts: 1,
    results: { CREATED: 3, UPDATED: 1, FAILED: 1 } });
  assert.equal(f.valid, 7);
  assert.equal(f.invalid, 3);
  assert.equal(f.created, 3);
  assert.equal(f.failed, 1);
  assert.equal(f.imported, 5);
  // the summary as admissions.prelim_migration_summary words it: rows staged so far beside the file's, the verdicts' "skipped" beside the result's
  const s = figuresOf({ rowsExpected: 10, rows: 6, staged: 6, ready: 4, warning: 1, error: 2, invalid: 2, skipped: 3, importSkipped: 1, imported: 5, feesHeld: 2 });
  assert.deepEqual([s.rows, s.staged, s.valid, s.invalid, s.skipped, s.notImported, s.imported, s.feesHeld], [10, 6, 5, 2, 3, 1, 5, 2]);
  assert.deepEqual(rowsOf({ total: 40, rows: [{ a: 1 }] }), { rows: [{ a: 1 }], total: 40 });
  assert.deepEqual(rowsOf([{ a: 1, total_count: 9 }]).total, 9);
  assert.equal(otherRoute("PRELIMINARY_TECHNOLOGY"), "PRELIMINARY_SCIENCE");
  assert.equal(otherRoute("PRELIMINARY_SCIENCE"), "PRELIMINARY_TECHNOLOGY");
  assert.equal(otherRoute("PROFICIENCY_CERTIFICATE"), null);
  assert.equal(fileNameOf("PRELIMINARY_TECHNOLOGY"), "PRELIMINARY_TECHNOLOGY_INDUSTRIAL_STUDIES_APPLICANTS_TEMPLATE.xlsx");
  assert.equal(fileNameOf("PRELIMINARY_SCIENCE"), "PRELIMINARY_SCIENCES_APPLICANTS_TEMPLATE.xlsx");
  assert.equal(fileNameOf("PRELIMINARY_SCIENCE", "GIVEN.xlsx"), "GIVEN.xlsx");
  assert.equal(reasonOk("Wrong programme"), false);
  assert.equal(reasonOk("Applied under the wrong programme"), true);
});
