import { test } from "node:test";
import assert from "node:assert/strict";
import {
  DE_BASIS_LABEL, DE_FIT_FILL, DE_RANKING, andList, basisOfType, deCandidatesColumns, deCandidatesFileName, deCandidatesSheets, deCandidatesSummarySheets,
  fieldOfHeader, parseDeCandidatesWorkbook, splitGrades, type DeCandidateRow, type DeCandidates,
} from "./de-candidates.ts";
import { xlsx, type CellFill, type SheetOpts } from "./xlsx-write.ts";
import { xlsxWorkbook } from "./xlsx.ts";

// ── the upload: the layout read back (invented candidates only) ──

const PHARMACY_HEAD = ["S/N", "REG NO.", "Name", "State", "LGA", "Sex", "Qualification", "Grade", "Has 5 Credits?", "IsCleared", "Status", "Age",
  "Age Qualified?", "Admission Category", "Qualification Type", "Discipline / Subject Combination", "Grades", "Points Obtained", "Max Points",
  "Total Weighted Score", "Class / Points", "Institution", "Year", "Exam / Matric No.", "Preliminary Fit", "Reason", "Other Notes",
  "O'Level Results (CAPS candidate dashboard)", "O'Level Sittings", "English", "Maths", "Physics", "Chemistry", "Biology", "Key Credits (of 5)", "O'Level Check"];
const LAW_HEAD = ["S/N", "REG NO.", "Name", "State", "LGA", "Sex", "Qualification", "Grade", "points", "Has 5 Credits?", "IsCleared", "Status", "Age",
  "Age Qualified?", "Qualification Type (Grade Window)", "Discipline / Subject Combination", "Grades by Subject", "points obtained", "max point",
  "total weighted score", "Class / Points", "Exam Year", "Exam / Matric No.", "Preliminary Fit", "Reason", "Other Notes", "O'Level Results (CAPS candidate dashboard)",
  "O'Level Sittings", "English", "Maths", "Literature", "Government", "CRK", "Total Credits (all subjects)", "O'Level Check"];
/** a row in a header's layout: the named cells filled, the rest blank */
const rowOf = (head: string[], v: Record<string, string>) => head.map((h) => v[h] ?? "");
const sheetOf = (head: string[], rows: Record<string, string>[], name = "ZZ DE Candidates") => ({
  name, rows: [["JAMB CAPS 9773/9774: Direct Entry Candidates for ZZ PROGRAMME, with Qualification Details"], ["A note"], [], head, ...rows.map((r) => rowOf(head, r))],
});
const KEYS = ["line", "regNo", "capsQualification", "capsGrade", "hasFiveCredits", "isCleared", "status", "age", "ageQualified", "admissionCategory",
  "typeText", "basis", "discipline", "awardClass", "subjects", "institution", "year", "examNo", "notes"];

test("Pharmacy's header spellings: the header found under the title and the note, every field read, the row exactly the upload's keys", () => {
  const r = parseDeCandidatesWorkbook([
    { name: "Summary", rows: [["Summary: ZZ"], ["ITEM", "COUNT"]] },
    sheetOf(PHARMACY_HEAD, [{
      "S/N": "3", "REG NO.": "29773000001ZZ", Name: "ZZCHECK ADA", Qualification: "JUPEB - A'Level", Grade: "10", "Has 5 Credits?": "True", IsCleared: "CLEARED",
      Status: "Not Admitted", Age: "20", "Age Qualified?": "True", "Admission Category": "Merit", "Qualification Type": "JUPEB - A'Level",
      "Discipline / Subject Combination": "Biology / Chemistry / Physics", Grades: "Biology: C; Chemistry: C; Physics: C", "Class / Points": "10",
      Institution: "Not shown in CAPS", Year: "2026", "Exam / Matric No.": "ZZ/26/0001",
    }]),
  ]);
  assert.equal(r.sheet, "ZZ DE Candidates");
  assert.equal(r.headerLine, 4);
  assert.deepEqual(r.problems, []);
  assert.equal(r.rows.length, 1);
  assert.deepEqual(Object.keys(r.rows[0]), KEYS, "exactly the upload's keys (the Grades and Class / Points cells are read, not sent)");
  assert.deepEqual(r.rows[0], {
    line: 5, regNo: "29773000001ZZ", capsQualification: "JUPEB - A'Level", capsGrade: 10, hasFiveCredits: true, isCleared: true, status: "Not Admitted",
    age: 20, ageQualified: true, admissionCategory: "Merit", typeText: "JUPEB - A'Level", basis: "JUPEB", discipline: null, awardClass: null,
    subjects: [{ subject: "Biology", grade: "C" }, { subject: "Chemistry", grade: "C" }, { subject: "Physics", grade: "C" }],
    institution: null, year: 2026, examNo: "ZZ/26/0001", notes: [],
  });
});

test("Law's header spellings: the type, the grades and the year under their own names; a degree held as its discipline and class", () => {
  const r = parseDeCandidatesWorkbook([sheetOf(LAW_HEAD, [
    { "S/N": "1", "REG NO.": "29773000002ZZ", Qualification: "1st Degree (Other Country Universities)", Grade: "16", "Has 5 Credits?": "False", IsCleared: "NOT CLEARED",
      Status: "Not Admitted", Age: "31", "Age Qualified?": "True", "Qualification Type (Grade Window)": "1st Degree (Other Country Universities)",
      "Discipline / Subject Combination": "Law", "Grades by Subject": "Law: 2nd Class Lower", "Class / Points": "2nd Class Lower", "Exam Year": "2019", "Exam / Matric No.": "ZZ1234" },
    { "S/N": "2", "REG NO.": "29773000003ZZ", Qualification: "", "Qualification Type (Grade Window)": "Not stated in CAPS",
      "Discipline / Subject Combination": "Government / Literature in English / CRK", "Grades by Subject": "Government: B; Literature in English: C; CRK: A" },
    { "S/N": "3", "REG NO.": "29773000004ZZ", "Qualification Type (Grade Window)": "Not available", "Discipline / Subject Combination": "Not available", "Grades by Subject": "Not available" },
    { "S/N": "4", "REG NO.": "29773000005ZZ", Qualification: "Nigeria Certificate in Education (NCE)", "Qualification Type (Grade Window)": "Nigeria Certificate in Education (NCE)",
      "Discipline / Subject Combination": "English / Education", "Grades by Subject": "English: Merit; English: Merit; Education: Merit", "Class / Points": "Merit, Merit, Merit" },
  ])]);
  assert.equal(r.rows.length, 4);
  const [deg, ns, na, nce] = r.rows;
  assert.deepEqual([deg.basis, deg.discipline, deg.awardClass, deg.subjects, deg.year, deg.hasFiveCredits, deg.isCleared, deg.institution, deg.admissionCategory],
    ["DEGREE_FOREIGN", "Law", "2nd Class Lower", [], 2019, false, false, null, null]);
  assert.deepEqual([ns.basis, ns.typeText, ns.capsQualification, ns.subjects.map((s) => `${s.subject} ${s.grade}`)],
    ["NOT_STATED", "Not stated in CAPS", null, ["Government B", "Literature in English C", "CRK A"]]);
  assert.deepEqual([na.basis, na.discipline, na.awardClass, na.subjects], ["NOT_AVAILABLE", null, null, []]);
  assert.deepEqual(nce.subjects, [{ subject: "English", grade: "Merit" }, { subject: "English", grade: "Merit" }, { subject: "Education", grade: "Merit" }], "a double major sent as read");
  r.rows.forEach((x) => assert.deepEqual(Object.keys(x), KEYS));
});

test("a row with content but no REG NO. is said, not sent; a file without the layout's header is said", () => {
  const r = parseDeCandidatesWorkbook([sheetOf(PHARMACY_HEAD, [
    { "S/N": "1", "REG NO.": "29773000006ZZ", "Qualification Type": "JUPEB - A'Level" },
    { "S/N": "2", Name: "ZZCHECK NO NUMBER" },
    {},
  ])]);
  assert.equal(r.rows.length, 1);
  assert.deepEqual(r.problems, ["Line 6: REG NO. blank; not sent"]);
  const none = parseDeCandidatesWorkbook([{ name: "Sheet1", rows: [["S/N", "Name"], ["1", "ZZ"]] }]);
  assert.equal(none.sheet, null);
  assert.equal(none.rows.length, 0);
  assert.equal(none.problems.length, 1);
});

test("values read as CAPS writes them; what cannot be read is noted and sent blank", () => {
  const r = parseDeCandidatesWorkbook([sheetOf(PHARMACY_HEAD, [
    { "REG NO.": " 29773000007zz ", "S/N": "1", "Has 5 Credits?": "yes", IsCleared: "1", "Age Qualified?": "0", Grade: "12", Age: "abc", Year: "Session 2023/2024",
      "Qualification Type": "JUPEB - A'Level" },
    { "REG NO.": "29773000008ZZ", "S/N": "2", "Has 5 Credits?": "maybe", IsCleared: "pending", Grade: "120", Age: "121", Year: "1950", "Qualification Type": "",
      Qualification: "Higher National Diploma (HND)", Grades: "", "Discipline / Subject Combination": "Science Laboratory Technology", "Class / Points": "Upper Credit",
      Institution: "ZZ Polytechnic" },
    { "REG NO.": "29773000009ZZ", "S/N": "3", "Qualification Type": "1st Degree (Nigeria Universities)", Grades: "Chemistry: 2nd Class Upper; Biology: 2nd Class Lower" },
    { "REG NO.": "29773000010ZZ", "S/N": "4", "Qualification Type": "ND", Grades: "", "Discipline / Subject Combination": "Accountancy", "Class / Points": "3" },
    { "REG NO.": "29773000011ZZ", "S/N": "5", "Qualification Type": "IJMB - A'Level", Grades: "", "Discipline / Subject Combination": "Biology / Chemistry / Physics" },
    { "REG NO.": "29773000012ZZ", "S/N": "6", "Qualification Type": "Master of Arts" },
  ])]);
  const [a, b, c, d, e, f] = r.rows;
  assert.deepEqual([a.regNo, a.hasFiveCredits, a.isCleared, a.ageQualified, a.capsGrade, a.age, a.year], ["29773000007zz", true, true, false, 12, null, 2023]);
  assert.deepEqual(a.notes, ["Age not read: abc"]);
  assert.deepEqual([b.hasFiveCredits, b.isCleared, b.capsGrade, b.age, b.year], [null, null, null, null, null]);
  assert.deepEqual(b.notes, ["Grade not read: 120", "Has 5 Credits? not read: maybe", "IsCleared not read: pending", "Age not read: 121", "Year not read: 1950"]);
  assert.deepEqual([b.typeText, b.basis, b.discipline, b.awardClass, b.institution], ["Higher National Diploma (HND)", "HND", "Science Laboratory Technology", "Upper Credit", "ZZ Polytechnic"],
    "the type from Qualification when the type column is blank; the class from Class / Points when Grades is blank");
  assert.deepEqual([c.discipline, c.awardClass, c.notes], ["Chemistry", "2nd Class Upper", ["More than one discipline in Grades; the first recorded"]]);
  assert.deepEqual([d.discipline, d.awardClass], ["Accountancy", null], "a number in Class / Points is not a class");
  assert.deepEqual(e.subjects, [{ subject: "Biology", grade: null }, { subject: "Chemistry", grade: null }, { subject: "Physics", grade: null }]);
  assert.deepEqual([f.typeText, f.basis], ["Master of Arts", null], "a type not read: the server refuses the row");
});

test("the type of qualification: every spelling of the workbooks, and the ones a careless test reads wrongly", () => {
  const cases: [string | null, string | null][] = [
    ["JUPEB - A'Level", "JUPEB"], ["IJMB - A'Level", "IJMB"], ["1st Degree (Nigeria Universities)", "DEGREE"], ["1st Degree (Other Country Universities)", "DEGREE_FOREIGN"],
    ["University Diploma", "UNIVERSITY_DIPLOMA"], ["National Diploma (ND)", "ND"], ["Higher National Diploma (HND)", "HND"],
    ["Nigeria Certificate in Education (NCE)", "NCE"], ["Not stated in CAPS", "NOT_STATED"], ["Not available", "NOT_AVAILABLE"],
    ["", "NOT_STATED"], [null, "NOT_STATED"], ["Master of Arts", null],
    ["Bachelor of Science", "DEGREE"], ["Higher National Diploma in Science Laboratory Technology", "HND"], ["National Diploma in Science Lab. Tech.", "ND"],
    ["GCE A’Level", "A_LEVEL"], ["GCE A Levels", "A_LEVEL"], ["Advanced Level", "A_LEVEL"], ["Diploma in Law", "UNIVERSITY_DIPLOMA"], ["B.Sc. obtained abroad", "DEGREE_FOREIGN"],
  ];
  for (const [t, b] of cases) assert.equal(basisOfType(t), b, String(t));
});

test("the grades split into subjects and grades, a grade not released read as none, a repeated subject kept", () => {
  assert.deepEqual(splitGrades("Biology: C; Chemistry: —; Physics: D"), [{ subject: "Biology", grade: "C" }, { subject: "Chemistry", grade: null }, { subject: "Physics", grade: "D" }]);
  assert.deepEqual(splitGrades("Pharmaceutical Technology (Chemistry): Upper Credit"), [{ subject: "Pharmaceutical Technology (Chemistry)", grade: "Upper Credit" }]);
  assert.deepEqual(splitGrades("Not available"), [{ subject: "Not available", grade: null }]);
  assert.deepEqual(splitGrades("English: Merit; English: Merit; Education: Merit").map((s) => s.subject), ["English", "English", "Education"]);
  assert.deepEqual(splitGrades("Time: 10:30; Physics: -; ; Chemistry: –"), [{ subject: "Time: 10", grade: "30" }, { subject: "Physics", grade: null }, { subject: "Chemistry", grade: null }]);
  assert.deepEqual(splitGrades(""), []);
});

// ── the download: the workbook built ──

/** a made-up candidate, as GET …/de-candidates gives one (null keys left out, as the API leaves them) */
const cand = (r: Partial<DeCandidateRow>): DeCandidateRow => ({
  rank: 1, listNo: 1, regNo: "29773000001ZZ", name: "CHECKV773 ADA", state: "Benue", lga: "Makurdi", sex: "F", hasFiveCredits: true, isCleared: "CLEARED",
  status: "Not Admitted", age: 20, registered: true, basis: "JUPEB", qualificationType: "JUPEB - A'Level", discipline: "Biology / Chemistry / Physics",
  grades: "Biology: C; Chemistry: C; Physics: C", points: 10, maxPoints: 16, score: 62.5, classPoints: "10", institution: "Not shown in CAPS", year: 2026,
  examNo: "ZZ/26/0001", fit: "Relevant", reason: "Passed Biology, Chemistry and Physics (C, C, C); points 10", olevelResults: "Biology: C4; English Language: B3",
  olevelSittings: "WAEC 2025 (4250000001)", sittings: 1,
  olevelGrades: [{ subject: "English Language", grade: "B3", credit: true }, { subject: "Mathematics", grade: "A/R", credit: false }, { subject: "Biology", grade: "—", credit: false }],
  keyCredits: 1, keyOf: 3, totalCredits: 6, olevelCheck: "Awaiting result (A/R) in Mathematics", olevelCheckKind: "PROBLEM", ...r,
});
const book = (rows: DeCandidateRow[], over: Partial<DeCandidates> = {}): DeCandidates => ({
  session: "9773/9774", programme: { code: "C99773", name: "B.Sc. (ED) ZZ STUDIES" }, asAt: "2026-11-15", policy: { state: "IN_FORCE", instrument: "CAC/ZZ/1" },
  olevel: { subjects: ["English Language", "Mathematics", "Biology"], credits: 5, sittings: 2, required: ["English Language", "Mathematics"] },
  fit: { source: "DEFAULT", criteria: [{ qualification: "1st Degree (Nigerian or foreign), any discipline", rule: "First Class/2nd Class Upper/2nd Class Lower = Relevant; 3rd Class = Partly relevant; Pass = Not relevant" }] },
  rows, ...over,
});
const fillAt = (o: SheetOpts | undefined, r: number, c: number): CellFill | undefined => o?.fills?.find((f) => f.r === r && f.c === c);

test("the workbook: the candidates, the summary and the rules, the title and the note above the header on row 4", () => {
  const sheets = deCandidatesSheets(book([cand({})]));
  assert.deepEqual(sheets.map((s) => s[0]), ["DE Candidates", "Summary", "Fit Criteria"]);
  const g = sheets[0][1];
  assert.deepEqual(g[0], ["JAMB CAPS 9773/9774: Direct Entry Candidates for B.Sc. (ED) ZZ STUDIES, with Qualification Details"]);
  assert.ok(String(g[1][0]).startsWith("Qualifications as uploaded from CAPS's grade windows and recorded in the portal;") && String(g[1][0]).endsWith("rules on the 'Fit Criteria' sheet."));
  assert.deepEqual(g[2], []);
  assert.equal(g[3][0], "S/N");
  assert.equal(g[3].length, 30 + 3 + 2);
});

test("the header blocks in their colours, the O'Level block one column for each of the programme's own subjects (3 and 5)", () => {
  for (const subjects of [["English Language", "Mathematics", "Literature in English"], ["English Language", "Mathematics", "Physics", "Chemistry", "Biology"]]) {
    const k = subjects.length;
    const [, g, o] = deCandidatesSheets(book([cand({ olevelGrades: subjects.map((s) => ({ subject: s, grade: "C4", credit: true })) })], { olevel: { subjects, credits: 5, sittings: 2, required: ["English Language", "Mathematics"] } }))[0];
    assert.deepEqual(g[3], deCandidatesColumns(subjects));
    assert.deepEqual(g[3].slice(28), ["O'Level Results", "O'Level Sittings", ...subjects, `Key Credits (of ${k})`, "O'Level Check"]);
    assert.deepEqual([g[3][14], g[3][15], g[3][27]], ["Registered", "Qualification Type", "Other Notes"]);
    assert.deepEqual(o?.headerFills, [{ from: 0, to: 14, fill: "1F3864" }, { from: 15, to: 27, fill: "385723" }, { from: 28, to: 31 + k, fill: "7030A0" }]);
    assert.deepEqual([o?.stripe, o?.freezeBelow, o?.freezeCols], [false, 4, 3]);
    assert.deepEqual(o?.centre, [0, 5, 7, 8, 9, 11, 12, 14, 18, 19, 20, 23, ...subjects.map((_, i) => 30 + i), 30 + k]);
    assert.deepEqual([o?.widths?.[26], o?.widths?.[30], o?.widths?.[30 + k], o?.widths?.[31 + k]], [44, 9, 9, 34]);
  }
});

test("each row: S/N the place on JAMB's list while the rows keep the rank's order; numbers as numbers; the fit, grade and check cells filled", () => {
  const rows = [
    cand({ rank: 2, listNo: 1, regNo: "29773000002ZZ", name: "CHECKV773 ABU", score: 50, points: 2, maxPoints: 4, fit: "Partly relevant", registered: false,
      hasFiveCredits: false, ageQualified: false, isCleared: "NOT CLEARED", otherNotes: "Candidate NOT CLEARED in CAPS; Not registered on the portal" }),
    cand({ rank: 1, listNo: 2, capsGrade: 10, ageQualified: true }),
    cand({ rank: 3, listNo: 3, regNo: "29773000003ZZ", name: "CHECKV773 ZEE", basis: null, qualificationType: "Not recorded", discipline: null, grades: null, points: null,
      maxPoints: null, score: null, classPoints: null, institution: null, year: null, examNo: null, fit: "Check manually", reason: "No qualification recorded",
      olevelResults: null, olevelSittings: null, sittings: 0, olevelGrades: [{ subject: "English Language", credit: false }, { subject: "Mathematics", credit: false }, { subject: "Biology", credit: false }],
      keyCredits: 0, totalCredits: 0, olevelCheck: "No O'Level on record: candidate must upload/verify results", olevelCheckKind: "NONE", hasFiveCredits: false, age: null }),
  ];
  const [, g, o] = deCandidatesSheets(book(rows))[0];
  assert.deepEqual(g.slice(4).map((r) => r[0]), [2, 1, 3], "S/N is listNo, rows in rank order");
  assert.deepEqual(g.slice(4).map((r) => r[1]), ["29773000001ZZ", "29773000002ZZ", "29773000003ZZ"]);
  const first = g[4];
  assert.deepEqual(first.slice(0, 15), [2, "29773000001ZZ", "CHECKV773 ADA", "Benue", "Makurdi", "F", "", 10, "True", "CLEARED", "Not Admitted", 20, "True", "", "Yes"]);
  assert.deepEqual(first.slice(15, 28), ["JUPEB - A'Level", "Biology / Chemistry / Physics", "Biology: C; Chemistry: C; Physics: C", 10, 16, 62.5, "10", "Not shown in CAPS", 2026,
    "ZZ/26/0001", "Relevant", "Passed Biology, Chemistry and Physics (C, C, C); points 10", ""]);
  assert.deepEqual(first.slice(28), ["Biology: C4; English Language: B3", "WAEC 2025 (4250000001)", "B3", "A/R", "—", 1, "Awaiting result (A/R) in Mathematics"]);
  assert.deepEqual(g[5].slice(8, 15), ["False", "NOT CLEARED", "Not Admitted", 20, "False", "", "No"]);
  const none = g[6];
  assert.deepEqual([none[7], none[11], none[15], none[18], none[19], none[20], none[23], none[28], none[29], none[30], none[31], none[32], none[33]],
    [null, null, "Not recorded", null, null, null, null, "No O'Level on record", "", "", "", "", 0]);
  // fills: the score shown to two decimals, the fit in its colour and bold, each O'Level grade cell green for a credit and red otherwise ("A/R", "—" too)
  assert.deepEqual(fillAt(o, 4, 20), { r: 4, c: 20, fmt: "0.00", centre: true });
  assert.equal(fillAt(o, 6, 20), undefined, "no score, no number format");
  assert.deepEqual(fillAt(o, 4, 25), { r: 4, c: 25, fill: DE_FIT_FILL.Relevant, bold: true });
  assert.equal(fillAt(o, 5, 25)?.fill, "FFF2CC");
  assert.equal(fillAt(o, 6, 25)?.fill, "D9E1F2");
  assert.deepEqual([fillAt(o, 4, 30)?.fill, fillAt(o, 4, 31)?.fill, fillAt(o, 4, 32)?.fill, fillAt(o, 4, 30)?.centre], ["E2EFDA", "F8CBAD", "F8CBAD", true]);
  assert.deepEqual([fillAt(o, 6, 30), fillAt(o, 6, 31), fillAt(o, 6, 32)], [undefined, undefined, undefined], "no O'Level: blank and unfilled");
  assert.deepEqual([fillAt(o, 4, 34)?.fill, fillAt(o, 6, 34)?.fill], ["FFF2CC", "D9D9D9"]);
  // the workbook written: the score cell a number in the 0.00 style
  const w = new TextDecoder().decode(xlsx(deCandidatesSheets(book(rows))));
  assert.ok(w.includes('numFmtId="2"'));
  assert.ok(/<c r="U5" s="\d+"><v>62.5<\/v><\/c>/.test(w));
});

test("the summary: counts computed (Has 5 Credits? = False counted from false), qualification types in their order, its letterhead stated", () => {
  const rows = [
    cand({ rank: 1, hasFiveCredits: false, qualificationType: "1st Degree (Nigeria Universities)", fit: "Partly relevant", isCleared: "NOT CLEARED" }),
    cand({ rank: 2, registered: false }),
    cand({ rank: 3, hasFiveCredits: undefined, qualificationType: "Not recorded", fit: "Check manually", olevelCheck: "No O'Level on record: candidate must upload/verify results", olevelCheckKind: "NONE", sittings: 0 }),
    cand({ rank: 4, olevelCheck: "Credits in English Language and Mathematics (1 sitting)", olevelCheckKind: "PASS" }),
    cand({ rank: 5, olevelCheck: "No credit in Mathematics" }), cand({ rank: 6, olevelCheck: "Only 3 credits; 5 required" }),
    cand({ rank: 7, olevelCheck: "Credits spread over 3 sittings (max 2 allowed)" }),
  ];
  const [name, s, o] = deCandidatesSheets(book(rows))[1];
  assert.equal(name, "Summary");
  assert.deepEqual(s.slice(0, 5), [["Summary: B.Sc. (ED) ZZ STUDIES Direct Entry candidates, 9773/9774"], ["As at 2026-11-15. Preliminary Fit is a guide, not a decision."], [], ["ITEM", "COUNT"], ["Total candidates", 7]]);
  const after = (label: string, n: number) => s.slice(s.findIndex((r) => r[0] === label) + 1, s.findIndex((r) => r[0] === label) + 1 + n);
  assert.deepEqual(after("By qualification type", 3), [["JUPEB - A'Level", 5], ["1st Degree (Nigeria Universities)", 1], ["Not recorded", 1]]);
  assert.deepEqual(after("By preliminary fit", 4), [["Relevant", 5], ["Partly relevant", 1], ["Not relevant", 0], ["Check manually", 1]]);
  assert.deepEqual(after("Flags", 3), [["NOT CLEARED in CAPS", 1], ["Has 5 Credits? = False", 1], ["Not registered on the portal", 1]]);
  assert.deepEqual(after("O'Level check", 6), [["Credits in the required subjects", 1], ["No credit in a required subject", 1], ["Fewer credits than required", 1],
    ["Awaiting result (A/R)", 2], ["Credits spread over too many sittings", 1], ["No O'Level on record", 1]]);
  assert.deepEqual([o?.letterheadRows, o?.headerRows, o?.widths], [3, [3], { 0: 60, 1: 12 }]);
  const at = (label: string) => s.findIndex((r) => r[0] === label);
  assert.deepEqual(fillAt(o, at("Not relevant"), 0)?.fill, "F8CBAD");
  assert.deepEqual([fillAt(o, at("Credits in the required subjects"), 0)?.fill, fillAt(o, at("Awaiting result (A/R)"), 0)?.fill, fillAt(o, at("No O'Level on record"), 0)?.fill], ["E2EFDA", "FFF2CC", "D9D9D9"]);
  // written: the title and the date line as the letterhead (styles 3 and 4), not a section band
  const w = new TextDecoder().decode(xlsx(deCandidatesSheets(book(rows))));
  assert.ok(w.includes('<row r="1"><c r="A1" s="3" t="inlineStr"><is><t xml:space="preserve">Summary: B.Sc. (ED) ZZ STUDIES'));
});

test("the rules in words: whose rule, each qualification's rule, the notes — and a subject nobody holds named only when nobody holds it", () => {
  const sheet = (b: DeCandidates) => deCandidatesSheets(b)[2];
  const [name, s, o] = sheet(book([cand({})]));
  assert.equal(name, "Fit Criteria");
  assert.deepEqual(s.slice(0, 5), [["Preliminary Fit rules for B.Sc. (ED) ZZ STUDIES, 9773/9774"], ["The University's default rule for Direct Entry, set on Admission Settings"], [],
    ["Qualification", "Rule applied"], ["1st Degree (Nigerian or foreign), any discipline", "First Class/2nd Class Upper/2nd Class Lower = Relevant; 3rd Class = Partly relevant; Pass = Not relevant"]]);
  assert.deepEqual([o?.letterheadRows, o?.headerRows, o?.widths], [3, [3], { 0: 60, 1: 90 }]);
  assert.deepEqual(s.map((r) => r[0]).slice(5), [undefined, "Notes", "Institution", "O'Level", "O'Level subjects", "Preliminary Fit", "Ranking"]);
  assert.equal(s.find((r) => r[0] === "O'Level")?.[1], "A credit is A1–C6. The programme's O'Level subjects shown are English Language, Mathematics, Biology; the check asks for a credit in English Language and Mathematics and 5 credits in all, in no more than 2 sittings. The O'Level is the portal's own record of JAMB's O'Level download. The check does not change the Preliminary Fit.");
  assert.equal(s.find((r) => r[0] === "O'Level subjects")?.[1], "No candidate on this list holds a grade in Biology; if one names more than one subject (as \"Physics and any of Chemistry\" does), write each as its own subject on Admission Settings.");
  assert.equal(s.at(-1)?.[1], DE_RANKING);
  // one candidate holds Biology: no such note; no candidate with O'Level at all: none either
  const held = cand({ olevelGrades: [{ subject: "English Language", grade: "B3", credit: true }, { subject: "Mathematics", grade: "C4", credit: true }, { subject: "Biology", grade: "C5", credit: true }] });
  assert.equal(sheet(book([cand({}), held]))[1].find((r) => r[0] === "O'Level subjects"), undefined);
  assert.equal(sheet(book([cand({ sittings: 0, olevelResults: null, olevelCheckKind: "NONE" })]))[1].find((r) => r[0] === "O'Level subjects"), undefined);
  assert.equal(sheet(book([cand({})], { fit: { source: "PROGRAMME", criteria: [] } }))[1][1][0], "B.Sc. (ED) ZZ STUDIES's own rule, set on Admission Settings");
  assert.equal(sheet(book([cand({})], { fit: { source: "BUILT_IN", criteria: [] } }))[1][1][0], "The University's default rule (none set for 9773/9774 on Admission Settings)");
});

test("the names: a workbook's with the session's / as -, the ZIP's summary one line a programme and the totals; the bases' words in their order", () => {
  assert.equal(deCandidatesFileName(book([])), "DE CANDIDATES B Sc ED ZZ STUDIES 9773-9774.xlsx");
  assert.equal(deCandidatesFileName({ programme: { name: "LL.B (ZZ)" }, session: "2026/2027" }), "DE CANDIDATES LL B ZZ 2026-2027.xlsx");
  const a = book([cand({}), cand({ rank: 2, registered: false, fit: "Not relevant", hasFiveCredits: false, olevelCheckKind: "PASS" })]);
  const b = book([cand({ isCleared: "NOT CLEARED", olevelCheckKind: "NONE" })], { programme: { code: "C99774", name: "ZZ OTHER" } });
  const [[name, s]] = deCandidatesSummarySheets([a, b], "9773/9774", "2026-11-15");
  assert.equal(name, "Programme_Summary");
  assert.deepEqual(s[0], ["JAMB CAPS 9773/9774: Direct Entry Candidates with Qualification Details, every programme"]);
  assert.deepEqual(s[3].slice(0, 4), ["SN", "PROGRAMME", "CODE", "CANDIDATES"]);
  assert.equal(s[3].length, 14);
  assert.deepEqual(s[4], [1, "B.Sc. (ED) ZZ STUDIES", "C99773", 2, 1, 1, 0, 1, 0, 0, 1, 1, 1, 0]);
  assert.deepEqual(s[5], [2, "ZZ OTHER", "C99774", 1, 1, 1, 0, 0, 0, 1, 0, 0, 0, 1]);
  assert.deepEqual(s.at(-1), [null, "TOTAL", null, 3, 2, 2, 0, 1, 0, 1, 1, 1, 1, 1]);
  assert.deepEqual(Object.keys(DE_BASIS_LABEL), ["A_LEVEL", "IJMB", "JUPEB", "NCE", "ND", "HND", "DEGREE", "DEGREE_FOREIGN", "UNIVERSITY_DIPLOMA", "NOT_STATED", "NOT_AVAILABLE", "NONE"]);
  assert.deepEqual([DE_BASIS_LABEL.A_LEVEL, DE_BASIS_LABEL.DEGREE_FOREIGN, DE_BASIS_LABEL.NONE], ["GCE A'Level", "1st Degree (Other Country Universities)", "Not recorded"]);
  assert.equal(andList(["A", "B", "C"]), "A, B and C");
  assert.equal(andList(["A"]), "A");
});

test("the workbook the portal writes reads back through the upload's parser: the same candidates and qualifications", async () => {
  const rows = [cand({}), cand({ rank: 2, listNo: 2, regNo: "29773000002ZZ", basis: "DEGREE", qualificationType: "1st Degree (Nigeria Universities)", discipline: "Chemistry",
    grades: "Chemistry: 2nd Class Upper", classPoints: "2nd Class Upper", institution: "Not shown (exam no. starts \"ZZ\")", hasFiveCredits: false, isCleared: "NOT CLEARED" })];
  const bytes = xlsx(deCandidatesSheets(book(rows)));
  const r = parseDeCandidatesWorkbook(await xlsxWorkbook(bytes.slice().buffer as ArrayBuffer, { rowNumbers: true }));
  assert.equal(r.sheet, "DE Candidates");
  assert.equal(r.headerLine, 4);
  assert.deepEqual(r.rows.map((x) => [x.line, x.regNo, x.basis, x.discipline, x.awardClass, x.subjects.length, x.hasFiveCredits, x.isCleared, x.institution, x.year]),
    [[5, "29773000001ZZ", "JUPEB", null, null, 3, true, true, null, 2026], [6, "29773000002ZZ", "DEGREE", "Chemistry", "2nd Class Upper", 0, false, false, null, 2026]]);
});

test("V773 review: a header spelt another way fills its field, and a sheet without its Grades column is not read at all", () => {
  const parse = parseDeCandidatesWorkbook;
  const fields: [string, string | null][] = [
    ["Grades", "grades"], ["Grades by Subject", "grades"], ["Subject Grades", "grades"], ["Grades (by Subject)", "grades"],
    ["Grade", "capsGrade"], ["Exam / Matric No.", "examNo"], ["Exam/Matric No", "examNo"], ["Matric No.", "examNo"],
    ["Discipline / Subject Combination", "discipline"], ["Discipline/Subject Combination", "discipline"],
    ["Qualification Type (Grade Window)", "typeText"], ["Qualification", "capsQualification"], ["Year", "year"], ["Exam Year", "year"],
    ["Class / Points", "classPoints"], ["Class/Points", "classPoints"], ["REG NO.", "regNo"], ["Registration Number", "regNo"],
    ["Has 5 Credits?", "hasFiveCredits"], ["IsCleared", "isCleared"], ["Age Qualified?", "ageQualified"], ["Age", "age"],
    ["O'Level Results", null], ["O'Level Sittings", null], ["Key Credits (of 5)", null], ["Points Obtained", null], ["Reason", null], ["English", null],
  ];
  for (const [h, f] of fields) assert.equal(fieldOfHeader(h), f, h);
  // the grades column under a spelling of the same words: read
  const ok = parse([{ name: "DE", rows: [["S/N", "REG NO.", "Qualification Type", "Discipline/Subject Combination", "Subject Grades"],
    ["1", "29773000001AA", "JUPEB - A'Level", "Biology / Chemistry / Physics", "Biology: C; Chemistry: B; Physics: D"]] }]);
  assert.equal(ok.rows.length, 1);
  assert.deepEqual(ok.rows[0].subjects, [{ subject: "Biology", grade: "C" }, { subject: "Chemistry", grade: "B" }, { subject: "Physics", grade: "D" }]);
  // no Grades column the portal knows: nothing read (the rows would be recorded over the grades held)
  const bad = parse([{ name: "DE", rows: [["S/N", "REG NO.", "Qualification Type", "Discipline / Subject Combination", "Results"],
    ["1", "29773000001AA", "JUPEB - A'Level", "Biology / Chemistry / Physics", "Biology: C; Chemistry: B; Physics: D"]] }]);
  assert.equal(bad.rows.length, 0);
  assert.equal(bad.problems.length, 1);
  assert.match(bad.problems[0], /no column for the Grades column/);
  // nor one without the qualification's type
  const noType = parse([{ name: "DE", rows: [["S/N", "REG NO.", "Grades"], ["1", "29773000001AA", "Biology: C"]] }]);
  assert.equal(noType.rows.length, 0);
  assert.match(noType.problems[0], /the qualification's type/);
});

test("V773 review: a degree's discipline and class — cut at the first colon, a class alone never recorded as the discipline", () => {
  const parse = parseDeCandidatesWorkbook;
  const head = ["S/N", "REG NO.", "Qualification Type", "Discipline / Subject Combination", "Grades", "Class / Points"];
  const one = (discipline: string | null, grades: string | null, cls: string | null, type = "1st Degree (Nigeria Universities)") =>
    parse([{ name: "DE", rows: [head, ["1", "29773000002AA", type, discipline ?? "", grades ?? "", cls ?? ""]] }]).rows[0];
  // the layout's own form
  let r = one("Forestry", "Forestry: 2nd Class Upper", "2nd Class Upper");
  assert.deepEqual([r.discipline, r.awardClass, r.notes], ["Forestry", "2nd Class Upper", []]);
  // a class that holds a colon
  r = one(null, "Law: 2:1", null);
  assert.deepEqual([r.discipline, r.awardClass], ["Law", "2:1"]);
  // the class alone (what the portal's own download writes for an award held without a discipline): no discipline invented
  r = one(null, "2nd Class Upper", "2nd Class Upper");
  assert.deepEqual([r.discipline, r.awardClass], [null, "2nd Class Upper"]);
  r = one(null, "Upper Credit", null, "National Diploma (ND)");
  assert.deepEqual([r.discipline, r.awardClass], [null, "Upper Credit"]);
  // the discipline alone in Grades, the class in its own column
  r = one(null, "Biochemistry", "2nd Class Lower");
  assert.deepEqual([r.discipline, r.awardClass], ["Biochemistry", "2nd Class Lower"]);
  r = one("Forestry", "Forestry", "3rd Class");
  assert.deepEqual([r.discipline, r.awardClass], ["Forestry", "3rd Class"]);
  // nothing in Grades: both from their columns
  r = one("Nursing", null, "First Class");
  assert.deepEqual([r.discipline, r.awardClass], ["Nursing", "First Class"]);
  // a Grades cell that is neither, beside a Discipline column: said, not guessed
  r = one("Nursing", "see transcript", "2nd Class Upper");
  assert.deepEqual([r.discipline, r.awardClass, r.notes], ["Nursing", "2nd Class Upper", ["Grades not read: see transcript"]]);
});
