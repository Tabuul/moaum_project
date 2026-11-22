/**
 * V773: Direct Entry candidates with their qualifications — the Admissions Committee's screening sheet, in the layout of the two
 * workbooks the University gave on 15 November 2026 (the Pharmacy one canonical), for every Direct Entry programme: everyone on
 * JAMB's live Direct Entry list for the programme, registered or not, with the qualification recorded, its score (the points as a
 * percentage of the qualification's own maximum), a Preliminary Fit (a guide, never a decision) and the O'Level the portal holds,
 * ranked by score, ties by name. Built here from GET …/de-candidates; and the same layout read back, the qualifications of a
 * whole list recorded at once (POST …/de-candidates/upload).
 */
import type { Sheet } from "./xlsx.ts";
import type { Cell, CellFill, SheetSpec } from "./xlsx-write.ts";

/** the eleven bases a Direct Entry qualification is recorded under (V773: three real ones added, and what CAPS showed when it
 *  showed no type or nothing at all) */
export type DeBasis = "A_LEVEL" | "IJMB" | "JUPEB" | "NCE" | "ND" | "HND" | "DEGREE" | "DEGREE_FOREIGN" | "UNIVERSITY_DIPLOMA" | "NOT_STATED" | "NOT_AVAILABLE";

/** each basis in words, as admissions.de_basis_label gives them (the one copy of these words here), in this order, and the word for
 *  a candidate with none — the Summary's order, the capture form's choices, the upload's table */
export const DE_BASIS_LABEL: Record<DeBasis | "NONE", string> = {
  A_LEVEL: "GCE A'Level", IJMB: "IJMB - A'Level", JUPEB: "JUPEB - A'Level", NCE: "Nigeria Certificate in Education (NCE)",
  ND: "National Diploma (ND)", HND: "Higher National Diploma (HND)", DEGREE: "1st Degree (Nigeria Universities)",
  DEGREE_FOREIGN: "1st Degree (Other Country Universities)", UNIVERSITY_DIPLOMA: "University Diploma", NOT_STATED: "Not stated in CAPS",
  NOT_AVAILABLE: "Not available", NONE: "Not recorded",
};
/** a degree or a diploma: held as its discipline and its class, with no subjects */
export const CLASS_KINDS: DeBasis[] = ["DEGREE", "DEGREE_FOREIGN", "UNIVERSITY_DIPLOMA", "ND", "HND"];
export const isClassKind = (b: string | null | undefined): boolean => CLASS_KINDS.includes(b as DeBasis);

/** the four Preliminary Fit words and their colours, as the workbooks drew them */
export const DE_FIT_FILL: Record<string, string> = { Relevant: "E2EFDA", "Partly relevant": "FFF2CC", "Not relevant": "F8CBAD", "Check manually": "D9E1F2" };
const CREDIT = "E2EFDA", NO_CREDIT = "F8CBAD";
const CHECK_FILL: Record<string, string> = { PASS: "E2EFDA", PROBLEM: "FFF2CC", NONE: "D9D9D9" };

/** the ranking, in words (the sheet's Ranking note; the JAMB return's RANKING note says the same, lib/de-template.ts) */
export const DE_RANKING = "Candidates are ranked by Total Weighted Score — the points of the qualification that counts as a percentage of its own "
  + "maximum — highest first, ties by name; a qualification without grades has no score and is listed after those with one. Points: "
  + "A'Level, IJMB and JUPEB, the three subjects at A 5, B 4, C 3, D 2, E 1 (A* as A), plus 1 when none is a fail (of 16); a degree, "
  + "First Class 5, 2nd Class Upper 4, 2nd Class Lower 3, 3rd Class 2, Pass 1 (of 5); HND, Distinction 5, Upper Credit 4, Lower Credit 3, "
  + "Pass 2 (of 5); ND, Distinction 4, Upper Credit 3, Lower Credit 2, Pass 1 (of 4); University Diploma, Distinction 4, Credit 3, Merit 2, "
  + "Pass 1 (of 4); NCE, three subjects at Distinction 5, Credit 4, Merit 3, Pass 2 (of 15). The qualification that counts is the "
  + "candidate's highest score. A fail counts nothing; a grade that cannot be read counts nothing and is named, with its qualification.";

/** one candidate's row as GET …/de-candidates gives it; a key whose value is null is left out by the API, so the nullable ones are optional */
export interface DeCandidateRow {
  rank: number; listNo: number; regNo: string; name?: string | null; state?: string | null; lga?: string | null; sex?: string | null;
  capsQualification?: string | null; capsGrade?: number | null; hasFiveCredits?: boolean | null; isCleared?: string | null; status?: string | null;
  age?: number | null; ageQualified?: boolean | null; admissionCategory?: string | null; registered: boolean;
  basis?: string | null; qualificationType: string; discipline?: string | null; grades?: string | null;
  points?: number | null; maxPoints?: number | null; score?: number | null; classPoints?: string | null;
  institution?: string | null; year?: number | null; examNo?: string | null;
  fit: string; reason: string; otherNotes?: string | null;
  olevelResults?: string | null; olevelSittings?: string | null; sittings: number;
  olevelGrades: { subject: string; grade?: string | null; credit: boolean }[];
  keyCredits: number; keyOf: number; totalCredits: number; olevelCheck: string; olevelCheckKind: "PASS" | "PROBLEM" | "NONE" | string;
}
/** one programme's workbook, as GET …/de-candidates?programme= gives it */
export interface DeCandidates {
  session: string; programme: { code: string; name: string }; asAt: string;
  policy?: { state: string; instrument?: string | null } | null;
  olevel: { subjects: string[]; credits: number; sittings: number; required: string[] };
  fit: { source?: "PROGRAMME" | "DEFAULT" | "BUILT_IN" | string | null; criteria: { qualification: string; rule: string }[] };
  rows: DeCandidateRow[];
}
/** a programme with a live Direct Entry row, as GET …/de-candidates/programmes lists it */
export interface DeCandidateProgramme { code: string; name: string; onList: number; registered: number; recorded: number }

/** "A", "A and B", "A, B and C" */
export function andList(items: string[]): string {
  return items.length <= 1 ? (items[0] ?? "") : `${items.slice(0, -1).join(", ")} and ${items[items.length - 1]}`;
}

/** the workbook's name: "DE CANDIDATES DOCTOR OF PHARMACY 2026-2027.xlsx" */
export function deCandidatesFileName(t: { programme: { name: string }; session: string }): string {
  return `DE CANDIDATES ${t.programme.name.replace(/[^A-Za-z0-9]+/g, " ").trim()} ${t.session.replace(/\//g, "-")}.xlsx`;
}

const COLS_CAPS = ["S/N", "REG NO.", "Name", "State", "LGA", "Sex", "Qualification", "Grade", "Has 5 Credits?", "IsCleared", "Status", "Age",
  "Age Qualified?", "Admission Category", "Registered"];
const COLS_QUAL = ["Qualification Type", "Discipline / Subject Combination", "Grades", "Points Obtained", "Max Points", "Total Weighted Score",
  "Class / Points", "Institution", "Year", "Exam / Matric No.", "Preliminary Fit", "Reason", "Other Notes"];
/** the columns of the candidates sheet: the CAPS block, the qualification block, then the O'Level block with one column for each of
 *  the programme's own O'Level subjects */
export function deCandidatesColumns(subjects: string[]): string[] {
  return [...COLS_CAPS, ...COLS_QUAL, "O'Level Results", "O'Level Sittings", ...subjects, `Key Credits (of ${subjects.length})`, "O'Level Check"];
}

const truth = (v: boolean | null | undefined): string => (v === true ? "True" : v === false ? "False" : "");
const num = (v: unknown): number | null => (v === null || v === undefined || v === "" || !Number.isFinite(Number(v)) ? null : Number(v));
const text = (v: unknown): string => (v === null || v === undefined ? "" : String(v));
const heldOlevel = (r: DeCandidateRow): boolean => Number(r.sittings ?? 0) > 0;
/** the grade a row shows for the i-th O'Level subject: by its place, else by its name */
function olevelCell(r: DeCandidateRow, subject: string, i: number) {
  const g = r.olevelGrades ?? [];
  return g[i]?.subject === subject ? g[i] : g.find((x) => x.subject === subject) ?? g[i];
}

/** the three sheets of a programme's workbook: the candidates, the summary, the fit rules in words */
export function deCandidatesSheets(t: DeCandidates): SheetSpec[] {
  const subjects = t.olevel?.subjects ?? [];
  const k = subjects.length;
  const name = t.programme.name;
  const rows = [...t.rows].sort((a, b) => a.rank - b.rank);

  // ── the candidates ──
  const grid: Cell[][] = [
    [`JAMB CAPS ${t.session}: Direct Entry Candidates for ${name}, with Qualification Details`],
    ["Qualifications as uploaded from CAPS's grade windows and recorded in the portal; O'Level from the portal's JAMB O'Level records. 'Preliminary Fit' is a PRELIMINARY GUIDE for the Admissions Committee, NOT a final decision; rules on the 'Fit Criteria' sheet."],
    [],
    deCandidatesColumns(subjects),
  ];
  const fills: CellFill[] = [];
  for (const r of rows) {
    const at = grid.length;
    const held = heldOlevel(r);
    const grades = subjects.map((s, i) => (held ? text(olevelCell(r, s, i)?.grade ?? "—") : ""));
    grid.push([
      num(r.listNo), r.regNo, text(r.name), text(r.state), text(r.lga), text(r.sex), text(r.capsQualification), num(r.capsGrade),
      truth(r.hasFiveCredits), text(r.isCleared), text(r.status), num(r.age), truth(r.ageQualified), text(r.admissionCategory),
      r.registered ? "Yes" : "No",
      text(r.qualificationType), text(r.discipline), text(r.grades), num(r.points), num(r.maxPoints), num(r.score), text(r.classPoints),
      text(r.institution), num(r.year), text(r.examNo), text(r.fit), text(r.reason), text(r.otherNotes),
      r.olevelResults ?? "No O'Level on record", text(r.olevelSittings), ...grades, num(r.keyCredits), text(r.olevelCheck),
    ]);
    if (num(r.score) !== null) fills.push({ r: at, c: 20, fmt: "0.00", centre: true });
    if (DE_FIT_FILL[r.fit]) fills.push({ r: at, c: 25, fill: DE_FIT_FILL[r.fit], bold: true });
    if (held) subjects.forEach((s, i) => fills.push({ r: at, c: 30 + i, fill: olevelCell(r, s, i)?.credit ? CREDIT : NO_CREDIT, centre: true }));
    if (CHECK_FILL[r.olevelCheckKind]) fills.push({ r: at, c: 31 + k, fill: CHECK_FILL[r.olevelCheckKind] });
  }
  const widths: Record<number, number> = { 0: 5, 1: 17, 2: 28, 3: 11, 4: 13, 5: 5, 6: 24, 7: 7, 8: 9, 9: 12, 10: 12, 11: 6, 12: 9, 13: 10, 14: 10,
    15: 22, 16: 30, 17: 34, 18: 8, 19: 8, 20: 10, 21: 14, 22: 24, 23: 7, 24: 20, 25: 15, 26: 44, 27: 34, 28: 46, 29: 30 };
  subjects.forEach((_, i) => { widths[30 + i] = 9; });
  widths[30 + k] = 9;
  widths[31 + k] = 34;

  // ── the summary ──
  const count = (p: (r: DeCandidateRow) => boolean) => rows.filter(p).length;
  const sum: Cell[][] = [
    [`Summary: ${name} Direct Entry candidates, ${t.session}`],
    [`As at ${t.asAt}. Preliminary Fit is a guide, not a decision.`],
    [],
    ["ITEM", "COUNT"],
    ["Total candidates", rows.length],
    ["By qualification type"],
  ];
  // in DE_BASIS_LABEL's order, "Not recorded" last (a word it does not know, before that)
  const known = Object.values(DE_BASIS_LABEL);
  const place = (q: string) => (known.includes(q) ? known.indexOf(q) : known.length - 1.5);
  const types = [...new Set(rows.map((r) => r.qualificationType))].sort((a, b) => place(a) - place(b));
  for (const q of types) sum.push([q, count((r) => r.qualificationType === q)]);
  const sumFills: CellFill[] = [];
  sum.push(["By preliminary fit"]);
  for (const f of Object.keys(DE_FIT_FILL)) { sumFills.push({ r: sum.length, c: 0, fill: DE_FIT_FILL[f] }); sum.push([f, count((r) => r.fit === f)]); }
  sum.push(["Flags"],
    ["NOT CLEARED in CAPS", count((r) => r.isCleared === "NOT CLEARED")],
    ["Has 5 Credits? = False", count((r) => r.hasFiveCredits === false)],
    ["Not registered on the portal", count((r) => !r.registered)]);
  sum.push(["O'Level check"]);
  const checks: [string, (r: DeCandidateRow) => boolean, string][] = [
    ["Credits in the required subjects", (r) => r.olevelCheckKind === "PASS", CHECK_FILL.PASS],
    ["No credit in a required subject", (r) => text(r.olevelCheck).startsWith("No credit in"), CHECK_FILL.PROBLEM],
    ["Fewer credits than required", (r) => text(r.olevelCheck).startsWith("Only "), CHECK_FILL.PROBLEM],
    ["Awaiting result (A/R)", (r) => text(r.olevelCheck).startsWith("Awaiting"), CHECK_FILL.PROBLEM],
    ["Credits spread over too many sittings", (r) => text(r.olevelCheck).startsWith("Credits spread"), CHECK_FILL.PROBLEM],
    ["No O'Level on record", (r) => r.olevelCheckKind === "NONE", CHECK_FILL.NONE],
  ];
  for (const [label, p, fill] of checks) { sumFills.push({ r: sum.length, c: 0, fill }); sum.push([label, count(p)]); }

  // ── the rules in words ──
  const source = t.fit?.source === "PROGRAMME" ? `${name}'s own rule, set on Admission Settings`
    : t.fit?.source === "DEFAULT" ? "The University's default rule for Direct Entry, set on Admission Settings"
    : `The University's default rule (none set for ${t.session} on Admission Settings)`;
  const crit: Cell[][] = [
    [`Preliminary Fit rules for ${name}, ${t.session}`],
    [source],
    [],
    ["Qualification", "Rule applied"],
    ...(t.fit?.criteria ?? []).map((c) => [c.qualification, c.rule] as Cell[]),
    [],
    ["Notes"],
    ["Institution", "CAPS grade windows do not name the awarding institution; where the exam/matric number begins with letters (BSU, TSU, NSU…), that prefix is shown as a clue only."],
    ["O'Level", `A credit is A1–C6. The programme's O'Level subjects shown are ${subjects.join(", ")}; the check asks for a credit in ${andList(t.olevel?.required ?? [])} and ${t.olevel?.credits ?? 5} credits in all, in no more than ${t.olevel?.sittings ?? 2} sittings. The O'Level is the portal's own record of JAMB's O'Level download. The check does not change the Preliminary Fit.`],
  ];
  // an O'Level subject nobody on the list holds (a rule naming two subjects in one item, as "Physics and any of Chemistry"): said, with the cure
  const withOlevel = rows.filter(heldOlevel);
  const unheld = withOlevel.length ? subjects.filter((s, i) => withOlevel.every((r) => (olevelCell(r, s, i)?.grade ?? "—") === "—")) : [];
  if (unheld.length) crit.push(["O'Level subjects", `No candidate on this list holds a grade in ${unheld.join(", ")}; if one names more than one subject (as "Physics and any of Chemistry" does), write each as its own subject on Admission Settings.`]);
  crit.push(
    ["Preliminary Fit", "A preliminary guide for the Admissions Committee, not a decision: it never changes the rank, the qualified test or the Board's decision."],
    ["Ranking", DE_RANKING],
  );

  return [
    ["DE Candidates", grid, {
      headerFills: [{ from: 0, to: 14, fill: "1F3864" }, { from: 15, to: 27, fill: "385723" }, { from: 28, to: 31 + k, fill: "7030A0" }],
      fills, stripe: false, freezeBelow: 4, freezeCols: 3, widths,
      centre: [0, 5, 7, 8, 9, 11, 12, 14, 18, 19, 20, 23, ...subjects.map((_, i) => 30 + i), 30 + k],
    }],
    ["Summary", sum, { letterheadRows: 3, headerRows: [3], widths: { 0: 60, 1: 12 }, fills: sumFills }],
    ["Fit Criteria", crit, { letterheadRows: 3, headerRows: [3], widths: { 0: 60, 1: 90 } }],
  ];
}

/** the whole session's summary beside each programme's workbook in the ZIP: one line a programme, and the totals */
export function deCandidatesSummarySheets(parts: DeCandidates[], session: string, asAt: string): SheetSpec[] {
  const figures = (t: DeCandidates): number[] => {
    const c = (p: (r: DeCandidateRow) => boolean) => t.rows.filter(p).length;
    return [t.rows.length, c((r) => r.registered), c((r) => r.fit === "Relevant"), c((r) => r.fit === "Partly relevant"), c((r) => r.fit === "Not relevant"),
      c((r) => r.fit === "Check manually"), c((r) => r.isCleared === "NOT CLEARED"), c((r) => r.hasFiveCredits === false),
      c((r) => r.olevelCheckKind === "PASS"), c((r) => r.olevelCheckKind === "PROBLEM"), c((r) => r.olevelCheckKind === "NONE")];
  };
  const lines = parts.map(figures);
  const total = lines.reduce((a, l) => a.map((v, i) => v + l[i]), new Array<number>(11).fill(0));
  return [["Programme_Summary", [
    [`JAMB CAPS ${session}: Direct Entry Candidates with Qualification Details, every programme`],
    [`As at ${asAt}`],
    [],
    ["SN", "PROGRAMME", "CODE", "CANDIDATES", "REGISTERED", "RELEVANT", "PARTLY RELEVANT", "NOT RELEVANT", "CHECK MANUALLY", "NOT CLEARED",
      "HAS 5 CREDITS? = FALSE", "O'LEVEL PASS", "O'LEVEL PROBLEM", "NO O'LEVEL"],
    ...parts.map((t, i) => [i + 1, t.programme.name, t.programme.code, ...lines[i]] as Cell[]),
    [null, "TOTAL", null, ...total],
  ]]];
}

// ── the upload: the same layout read back ──

/** one row the upload sends (POST …/de-candidates/upload[/preview]) — exactly these keys */
export interface DeUploadRow {
  line: number; regNo: string; capsQualification: string | null; capsGrade: number | null; hasFiveCredits: boolean | null; isCleared: boolean | null;
  status: string | null; age: number | null; ageQualified: boolean | null; admissionCategory: string | null;
  typeText: string | null; basis: DeBasis | null; discipline: string | null; awardClass: string | null; subjects: { subject: string; grade: string | null }[];
  institution: string | null; year: number | null; examNo: string | null; notes: string[];
}
export interface DeUploadRead { sheet: string | null; headerLine: number | null; rows: DeUploadRow[]; problems: string[] }

type Field = "regNo" | "capsQualification" | "capsGrade" | "hasFiveCredits" | "isCleared" | "status" | "age" | "ageQualified" | "admissionCategory"
  | "typeText" | "discipline" | "grades" | "classPoints" | "institution" | "year" | "examNo";
/** each header as the two workbooks spell it (Pharmacy's and Law's), normalised, and the field it fills */
const HEADERS: Record<string, Field> = {
  "reg no": "regNo", "reg no.": "regNo", "registration number": "regNo", "jamb reg no": "regNo", "rg_num": "regNo",
  qualification: "capsQualification", grade: "capsGrade", "has 5 credits": "hasFiveCredits", iscleared: "isCleared", "is cleared": "isCleared",
  status: "status", age: "age", "age qualified": "ageQualified", "admission category": "admissionCategory",
  "qualification type": "typeText", "qualification type (grade window)": "typeText", "discipline / subject combination": "discipline",
  grades: "grades", "grades by subject": "grades", "class / points": "classPoints", institution: "institution", year: "year", "exam year": "year",
  "exam / matric no": "examNo", "exam / matric no.": "examNo",
};
/** a header as it is compared: lower case, one space, no trailing ".", "?" or ":" */
export const normHeader = (h: unknown): string => String(h ?? "").toLowerCase().replace(/\s+/g, " ").trim().replace(/[.?:]+$/, "").trim();

/** the field a header fills: the two workbooks' own spellings first, then the same words spelt another way ("Exam/Matric No",
 *  "Subject Grades", "Grades (by Subject)", "Discipline/Subject Combination", "Exam Yr") — a third committee's sheet is read as the
 *  two given are, and never silently as a blank column. "Grade" alone stays CAPS's figure; the O'Level columns are not read. */
export function fieldOfHeader(h: unknown): Field | null {
  const n = normHeader(h);
  if (!n) return null;
  if (HEADERS[n]) return HEADERS[n];
  const k = n.replace(/[’‘`]/g, "'").replace(/\s*\/\s*/g, "/").replace(/[()]/g, " ").replace(/\s+/g, " ").trim().replace(/[.?:]+$/, "").trim();
  if (/^o'?\s?level|^key credits|^total credits/.test(k)) return null;
  if (/^(jamb )?reg(istration)?\.? ?(no|number|num)\b/.test(k) || k === "rg_num") return "regNo";
  if (/^qualification type\b/.test(k)) return "typeText";
  if (k === "qualification" || /^caps qualification\b/.test(k)) return "capsQualification";
  if (/^(subject )?grades\b/.test(k)) return "grades";
  if (k === "grade" || /^caps grade\b/.test(k)) return "capsGrade";
  if (/^discipline\b|subject combination/.test(k)) return "discipline";
  if (/^class\b/.test(k)) return "classPoints";
  if (/^institution\b/.test(k)) return "institution";
  if (/^(exam |award |awarded |graduation )?(year|yr)\b/.test(k)) return "year";
  if (/^(exam|matric)[a-z./ ]*(no|number|num)\b/.test(k)) return "examNo";
  if (/^has (5|five) credits\b/.test(k)) return "hasFiveCredits";
  if (/^is ?cleared\b/.test(k)) return "isCleared";
  if (/^age qualified\b/.test(k)) return "ageQualified";
  if (/^admission category\b/.test(k)) return "admissionCategory";
  return null;
}

/** words a class of award is written in ("2nd Class Upper", "Upper Credit", "Distinction", "2:1") — how a cell holding a class
 *  alone is told from one holding a discipline alone */
const CLASS_WORDS = /\bclass\b|\bcredit\b|\bdistinction\b|\bmerit\b|\bpass\b|\bfirst\b|\bupper\b|\blower\b|\bhonou?rs?\b|\b[123][:.\-][12]\b/i;

/** the basis a CAPS qualification type names (the first test that matches; null: not read, the server refuses the row) */
export function basisOfType(text: string | null | undefined): DeBasis | null {
  const t = String(text ?? "").toUpperCase().replace(/[‘’]/g, "'").trim();
  if (!t || t.includes("NOT STATED")) return "NOT_STATED";
  if (t.includes("NOT AVAILABLE")) return "NOT_AVAILABLE";
  if (/\bJUPEB\b/.test(t)) return "JUPEB";
  if (/\bIJMB\b/.test(t)) return "IJMB";
  if (/\bA\s*'?\s*LEVELS?\b|ADVANCED LEVEL/.test(t)) return "A_LEVEL";
  if (/HIGHER NATIONAL DIPLOMA|\bHND\b/.test(t)) return "HND";
  if (/NATIONAL DIPLOMA|\bND\b/.test(t)) return "ND";
  if (/\bNCE\b|CERTIFICATE IN EDUCATION/.test(t)) return "NCE";
  if (t.includes("UNIVERSITY DIPLOMA") || t.startsWith("DIPLOMA")) return "UNIVERSITY_DIPLOMA";
  if (/\bDEGREE\b|\bB\.?\s*SC\b|BACHELOR/.test(t)) return /OTHER COUNTR|FOREIGN|ABROAD|OVERSEAS/.test(t) ? "DEGREE_FOREIGN" : "DEGREE";
  return null;
}

/** "Biology: C; Chemistry: —; Physics: D" → each part's subject and grade (split at its last ":"; "—", "–", "-" or blank: no grade) */
export function splitGrades(text: string | null | undefined): { subject: string; grade: string | null }[] {
  return String(text ?? "").split(";").map((p) => p.trim()).filter(Boolean).map((p) => {
    const at = p.lastIndexOf(":");
    if (at < 0) return { subject: p, grade: null };
    const grade = p.slice(at + 1).trim();
    return { subject: p.slice(0, at).trim(), grade: !grade || /^[—–-]+$/.test(grade) ? null : grade };
  });
}

const blank = (v: unknown) => String(v ?? "").trim() === "";
const str = (v: unknown): string | null => (blank(v) ? null : String(v).trim());

/** the workbook read: the first sheet whose header row carries S/N in column A and a REG NO. column; every row under it with a
 *  REG NO. is a candidate's row, as the server's upload takes it */
export function parseDeCandidatesWorkbook(sheets: Sheet[]): DeUploadRead {
  for (const sheet of sheets) {
    const h = sheet.rows.findIndex((r) => ["s/n", "sn"].includes(normHeader(r?.[0])) && (r ?? []).some((c) => fieldOfHeader(c) === "regNo"));
    if (h < 0) continue;
    const head = sheet.rows[h];
    const col: Partial<Record<Field, number>> = {};
    head.forEach((c, i) => { const f = fieldOfHeader(c); if (f && col[f] === undefined) col[f] = i; });
    // a sheet whose Grades column (or whose qualification's type) is not found is not read at all: read as blank, its rows would
    // be recorded over the grades the portal already holds
    const missing = [
      col.grades === undefined ? "the Grades column (“Grades” or “Grades by Subject”)" : null,
      col.typeText === undefined && col.capsQualification === undefined ? "the qualification's type (“Qualification Type” or “Qualification”)" : null,
    ].filter(Boolean);
    if (missing.length) {
      return { sheet: sheet.name, headerLine: h + 1, rows: [], problems: [`The header row (line ${h + 1}) has no column for ${missing.join(" or for ")}: nothing was read, so nothing on record is changed. Name the column as the layout does and choose the file again.`] };
    }
    const rows: DeUploadRow[] = [];
    const problems: string[] = [];
    for (let i = h + 1; i < sheet.rows.length; i++) {
      const r = sheet.rows[i] ?? [];
      const at = (f: Field) => (col[f] === undefined ? "" : String(r[col[f]!] ?? "").trim());
      const line = i + 1;
      if (!at("regNo")) {
        if (r.some((c) => !blank(c))) problems.push(`Line ${line}: REG NO. blank; not sent`);
        continue;
      }
      rows.push(readRow(line, at, (f) => String(head[col[f]!] ?? "").trim()));
    }
    return { sheet: sheet.name, headerLine: h + 1, rows, problems };
  }
  return { sheet: null, headerLine: null, rows: [], problems: ["No sheet has the header row of the Direct Entry candidates layout: S/N in column A and a REG NO. column."] };
}

/** one row's cells as the upload's row: values read, what cannot be read noted */
function readRow(line: number, at: (f: Field) => string, header: (f: Field) => string): DeUploadRow {
  const notes: string[] = [];
  const bool = (f: Field, yes: string[], no: string[]): boolean | null => {
    const v = at(f);
    if (!v) return null;
    const u = v.toUpperCase().replace(/\s+/g, " ");
    if (yes.includes(u)) return true;
    if (no.includes(u)) return false;
    notes.push(`${header(f)} not read: ${v}`);
    return null;
  };
  const int = (f: Field, min: number, max: number): number | null => {
    const v = at(f);
    if (!v) return null;
    const n = Number(v);
    if (Number.isInteger(n) && n >= min && n <= max) return n;
    notes.push(`${header(f)} not read: ${v}`);
    return null;
  };
  // the CAPS columns, read in their order so the notes come in the sheet's order
  const capsGrade = int("capsGrade", 0, 99);
  const hasFiveCredits = bool("hasFiveCredits", ["TRUE", "YES", "1"], ["FALSE", "NO", "0"]);
  const isCleared = bool("isCleared", ["CLEARED", "YES", "TRUE", "1"], ["NOT CLEARED", "NO", "FALSE", "0"]);
  const age = int("age", 0, 120);
  const ageQualified = bool("ageQualified", ["TRUE", "YES", "1"], ["FALSE", "NO", "0"]);
  const yearText = at("year");
  const y = /(19|20)\d\d/.exec(yearText);
  const year = y && Number(y[0]) >= 1960 && Number(y[0]) <= 2100 ? Number(y[0]) : null;
  if (yearText && year === null) notes.push(`${header("year")} not read: ${yearText}`);
  const typeText = str(at("typeText")) ?? str(at("capsQualification"));
  const basis = basisOfType(typeText);
  const institution = str(at("institution"));

  // the qualification as it is held: a degree or diploma its discipline and class; an A'Level or NCE its subjects in their order
  let discipline: string | null = null, awardClass: string | null = null;
  let subjects: { subject: string; grade: string | null }[] = [];
  const parts = splitGrades(at("grades"));
  const classPoints = str(at("classPoints"));
  if (basis && isClassKind(basis)) {
    if (parts.length > 1) notes.push("More than one discipline in Grades; the first recorded");
    // "<Discipline>: <Class>" cut at its first colon (a class may hold one: "Law: 2:1"); without a colon the cell is the class
    // when it reads as one (or repeats the Class column) and the discipline otherwise — each falls back to its own column
    const g = at("grades").split(";").map((x) => x.trim()).filter(Boolean)[0] ?? "";
    const given = (t: string): string | null => (!t || /^[—–-]+$/.test(t) ? null : t);
    const colDiscipline = str(at("discipline"));
    const colClass = classPoints !== null && !Number.isFinite(Number(classPoints)) ? classPoints : null;
    const cut = g.indexOf(":");
    const same = (a: string, b: string | null) => b !== null && a.toLowerCase() === b.toLowerCase();
    if (cut >= 0) {
      discipline = str(g.slice(0, cut)) ?? colDiscipline;
      awardClass = given(g.slice(cut + 1).trim()) ?? colClass;
    } else if (!given(g) || same(g, colDiscipline)) {
      discipline = colDiscipline;
      awardClass = colClass;
    } else if (same(g, colClass) || CLASS_WORDS.test(g)) {
      discipline = colDiscipline;
      awardClass = g;
    } else {
      discipline = colDiscipline ?? g;
      awardClass = colClass;
      if (colDiscipline !== null) notes.push(`Grades not read: ${g}`);
    }
  } else if (basis && basis !== "NOT_AVAILABLE") {
    subjects = parts.length ? parts : at("discipline").split(/\s+\/\s+/).map((s) => s.trim()).filter(Boolean).map((subject) => ({ subject, grade: null }));
  }

  return {
    line, regNo: at("regNo"), capsQualification: str(at("capsQualification")), capsGrade, hasFiveCredits, isCleared,
    status: str(at("status")), age, ageQualified, admissionCategory: str(at("admissionCategory")), typeText, basis, discipline, awardClass, subjects,
    institution: institution && !/^not shown/i.test(institution) ? institution : null, year, examNo: str(at("examNo")),
    notes: notes.slice(0, 10).map((n) => n.slice(0, 200)),
  };
}
