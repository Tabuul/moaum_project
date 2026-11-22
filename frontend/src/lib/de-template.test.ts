import { test } from "node:test";
import assert from "node:assert/strict";
import { DE_BASIS, DE_COLS, DE_RANKING_NOTE, deFileName, deLine, dePoints, deRemark, deSheets, mergeDeTemplates, type DeRow, type DeTemplate } from "./de-template.ts";

/** a made-up Direct Entry applicant, as GET …/de-template gives one */
const row = (r: Partial<DeRow>): DeRow => ({
  rank: 1, applicationNo: "APP/64/000001", regNo: "29764000001", name: "CHECKV764 D1", gender: "Female", state: "Benue", lga: "Makurdi",
  programme: "B.Sc. ACCOUNTING", entryLevel: 200, qualification: "A_LEVEL", institution: "Check College", awardedYear: 2024,
  subjects: [{ subject: "Chemistry", grade: "A", points: 5 }, { subject: "Biology", grade: "B", points: 4 }, { subject: "Physics", grade: "C", points: 3 }],
  otherQualifications: null, points: 12, deStatus: "MET", olevelUploaded: true, olevelMissing: null, engGrade: "B3", mathsGrade: "C4", sittings: 1,
  recordedDecision: null, decision: "WAITING", decisionBasis: null, decisionNote: "Qualified: no decision recorded yet", released: false,
  qualified: true, reason: null, ...r,
});

const template = (rows: DeRow[], over: Partial<DeTemplate> = {}): DeTemplate => ({
  kind: "DE", session: "9764/9765", programme: "B.Sc. ACCOUNTING", asAt: "2026-11-15",
  summary: { totalApplicants: 9, registeredApplicants: rows.length, qualifiedCases: 2, nonQualifiedCases: 1, totalQuota: 10, deQuota: 2, deRatio: 20, numberOnMeritList: 1 },
  quotaDistribution: [{ criterion: "National Merit", percent: 50, quota: 1, admitted: 1, shortfall: 0 }],
  lgaAnalysis: [{ lga: "Makurdi", elg: 0, sm: 0, nm: 1, total: 1 }], lgaTotal: { lga: "TOTAL", elg: 0, sm: 0, nm: 1, total: 1 },
  rows, ...over,
});

test("a Direct Entry line: rank, the qualification and its three best subjects, the points, the requirement and the O'Level, the remark", () => {
  const line = deLine(row({}), 0);
  assert.equal(line.length, DE_COLS.length);
  assert.deepEqual(line.slice(0, 11), [1, 1, "29764000001", "CHECKV764 D1", "Female", "Benue", "Makurdi", 200, "A-Level", "Check College", 2024]);
  assert.deepEqual(line.slice(11, 17), ["Chemistry", "A", "Biology", "B", "Physics", "C"]);
  assert.deepEqual(line.slice(17), [12, null, "Meets the requirement", "B3", "C4", 1, null, "Qualified: no decision recorded yet"]);
  assert.equal(deLine(row({ unreadGrades: "Biology A1" }), 0).at(-2), "Biology A1", "a grade not read named for the officer");
  const short = deLine(row({ qualification: "ND", subjects: [{ subject: "Mathematics", grade: "Credit", points: 2 }], points: 2, deStatus: "SHORT",
    decision: "NOT_OFFERED", decisionNote: "Direct Entry subjects short of the programme's requirement", qualified: false,
    reason: "Direct Entry subjects short of the programme's requirement" }), 4, true);
  assert.equal(short.length, DE_COLS.length + 1);
  assert.deepEqual([short[0], short[8], short[11], short[12], short[13], short[19]], [5, "ND", "Mathematics", "Credit", null, "Short of the requirement"]);
  assert.equal(short[short.length - 1], "Direct Entry subjects short of the programme's requirement");
  assert.equal(deLine(row({}), 0, true).at(-1), "Qualified");
  const none = deLine(row({ qualification: null, subjects: [], points: null, deStatus: "UNVERIFIED" }), 0);
  assert.deepEqual([none[8], none[11], none[17], none[19]], [null, null, null, "Not captured"]);
});

test("the remark: the basis an offer stands on, else the Board's note, else what the row's place says", () => {
  assert.equal(deRemark(row({ decision: "OFFERED", decisionBasis: "NM", decisionNote: null })), "National Merit");
  assert.equal(deRemark(row({ decision: "OFFERED", decisionBasis: null, decisionNote: null })), "Recommended");
  assert.equal(deRemark(row({ decision: "WAITING", decisionNote: null })), "Waiting list");
  assert.equal(deRemark(row({ decision: "NOT_OFFERED", decisionNote: "Application not submitted" })), "Application not submitted");
  assert.equal(deRemark(row({ decision: "NOT_OFFERED", decisionNote: null })), "Not recommended");
});

test("the workbook: the summary with the Direct Entry share, then the merit list, the other qualified, the non-qualified and the ranked sheet in rank order", () => {
  const rows = [
    row({ rank: 3, name: "CHECKV764 D3", decision: "NOT_OFFERED", qualified: false, reason: "O'Level result not uploaded", decisionNote: "O'Level result not uploaded" }),
    row({ rank: 1, name: "CHECKV764 D2", decision: "OFFERED", decisionBasis: "NM", decisionNote: null }),
    row({ rank: 2, name: "CHECKV764 D1" }),
  ];
  const sheets = deSheets(template(rows));
  assert.deepEqual(sheets.map((s) => s[0]), ["Admission_Summary", "Merit_List", "Other_Qualified_Cases", "Non_Qualified_Cases", "Ranked_sheet"]);
  const summary = sheets[0][1];
  assert.equal(summary[1][1], "9764/9765 DIRECT ENTRY MERIT ADMISSION SUMMARY FOR B.Sc. ACCOUNTING");
  assert.deepEqual(summary[8], [1, "Total Applicants", 9]);
  assert.deepEqual(summary[13], [6, "DE Quota (20%)", 2]);
  assert.ok(summary.some((r) => r[1] === "National Merit"), "the quota distribution over the Direct Entry share");
  assert.ok(summary.some((r) => typeof r[1] === "string" && r[1].startsWith("By the score of the qualification that counts: candidates are ranked by Total Weighted Score")), "the ranking rule said");
  const names = (i: number) => sheets[i][1].slice(8).map((r) => r[3]);
  assert.deepEqual(names(1), ["CHECKV764 D2"]);
  assert.deepEqual(names(2), ["CHECKV764 D1"]);
  assert.deepEqual(names(3), ["CHECKV764 D3"]);
  assert.deepEqual(names(4), ["CHECKV764 D2", "CHECKV764 D1", "CHECKV764 D3"]);
  assert.equal(sheets[4][1][7].at(-1), "DE REMARKS");
  assert.deepEqual(sheets[3][1][8].at(-1), "O'Level result not uploaded");
  assert.equal(deSheets(template(rows), true).length, 1, "the summary alone");
});

test("the whole session: each programme's summary added up, a ratio only when every programme read the same, one workbook name per programme", () => {
  const a = template([row({})]);
  const b = template([row({ programme: "B.Sc. BUSINESS MANAGEMENT" })], { programme: "B.Sc. BUSINESS MANAGEMENT", summary: { ...a.summary, deRatio: 40, deQuota: 4 } });
  const m = mergeDeTemplates([a, b], "9764/9765", "2026-11-15");
  assert.equal(m.summary.totalApplicants, 18);
  assert.equal(m.summary.deQuota, 6);
  assert.equal(m.summary.deRatio, null);
  assert.equal(mergeDeTemplates([a, a], "9764/9765", "2026-11-15").summary.deRatio, 20);
  assert.deepEqual(m.lgaTotal, { lga: "TOTAL", elg: 0, sm: 0, nm: 2, total: 2 });
  assert.equal(m.perProgramme?.length, 2);
  const sheets = deSheets(m, true);
  assert.deepEqual(sheets.map((s) => s[0]), ["Admission_Summary", "Programme_Summary"]);
  assert.equal(sheets[0][1][13][1], "DE Quota");
  assert.equal(deFileName(a), "DE ADMISSION TEMPLATE B Sc ACCOUNTING 9764-9765.xlsx");
  assert.equal(deFileName({ programme: "", session: "2026/2027" }), "DE ADMISSION TEMPLATE ALL PROGRAMMES 2026-2027.xlsx");
});

test("V773: DE POINTS shows the score beside the points, so the order by score reads off the sheet; an API without the maximum keeps the bare points", () => {
  assert.equal(dePoints({ points: 15, maxPoints: 16, score: 93.75 }), "15/16 (93.75%)");
  assert.equal(dePoints({ points: 5, maxPoints: 5, score: 100 }), "5/5 (100.00%)");
  assert.equal(dePoints({ points: 10, maxPoints: 16, score: 62.5 }), "10/16 (62.50%)");
  assert.equal(dePoints({ points: 12 }), 12);
  assert.equal(dePoints({ points: null, maxPoints: 16, score: null }), null);
  const line = deLine(row({ points: 15, maxPoints: 16, score: 93.75 }), 0);
  assert.equal(line[DE_COLS.indexOf("DE POINTS")], "15/16 (93.75%)");
  assert.equal(deLine(row({}), 0)[DE_COLS.indexOf("DE POINTS")], 12, "bare 12 without maxPoints");
});

test("V773: the RANKING note is the score rule, the grades not read named under their column; the new bases in JAMB's words", () => {
  assert.ok(DE_RANKING_NOTE.startsWith("By the score of the qualification that counts: candidates are ranked by Total Weighted Score — the points of the qualification that counts as a percentage of its own maximum — highest first, ties by name;"));
  assert.ok(DE_RANKING_NOTE.includes("plus 1 when none is a fail (of 16)") && DE_RANKING_NOTE.includes("NCE, three subjects at Distinction 5, Credit 4, Merit 3, Pass 2 (of 15)"));
  assert.ok(DE_RANKING_NOTE.endsWith("counts nothing and is named under GRADES NOT READ, with its qualification."));
  const summary = deSheets(template([row({})]))[0][1];
  assert.equal(summary.at(-1)?.[1], DE_RANKING_NOTE);
  assert.deepEqual([DE_BASIS.DEGREE, DE_BASIS.DEGREE_FOREIGN, DE_BASIS.UNIVERSITY_DIPLOMA, DE_BASIS.NOT_STATED, DE_BASIS.NOT_AVAILABLE],
    ["Degree", "Foreign degree", "University Diploma", "Not stated", "Not available"]);
  assert.equal(DE_BASIS.A_LEVEL, "A-Level");
  assert.equal(deLine(row({ qualification: "DEGREE", subjects: [{ subject: "Chemistry", grade: "2nd Class Upper", points: 4 }], points: 4, maxPoints: 5, score: 80 }), 0)[8], "Degree");
});
