/**
 * Old-portal postgraduate applicants migrated (V675): the template built from the PG application the portal holds — the data
 * sheet under a letterhead, with drop-downs read from this portal's faculties, departments, programmes, sessions and the old
 * portal's words — read back on upload into rows of the template's keys, the words for what a row is and does, the ranges the
 * file is sent, checked and imported in, and the error report. The rules are the server's; this file only carries the rows.
 */
import { colName, type Cell, type ListValidation, type SheetSpec } from "./xlsx-write.ts";

/** a cell of a report: text, a number or nothing */
export type ReportCell = string | number | null;

export type Kind = "APPLICANTS" | "ADMITTED";
/** what an upload on the desk is: a template's file (a Kind) or a file of application fee payments (V786) */
export type BatchKind = Kind | "FEES";
export interface Column { key: string; header: string; section: string; required: boolean; note: string | null }
export interface TemplateData {
  kind: Kind; columns: Column[];
  faculties: { code: string; name: string }[];
  departments: { code: string; name: string; faculty: string }[];
  programmes: { code: string; name: string; award: string | null; department: string; faculty: string }[];
  specialisations: { programme_code: string; programme: string; code: string; name: string }[];
  sessions: { name: string; state: string | null }[];
  statuses: { word: string; state: string }[];
}
export interface Problem { code: string; level: "duplicate" | "error" | "conflict" | "review" | "warning"; message: string; fix?: string }
export interface MigrationRow {
  id: string; row_no: number; legacy_no: string | null; applicant: string | null; email: string | null; verdict: string | null; match: string | null;
  action: string | null; programme_code: string | null; session: string | null; target_state: string | null; problems: Problem[] | null;
  result: string | null; result_note: string | null; decided_new: boolean; decided_new_reason: string | null; application_id: string | null;
  student_id: string | null; application_no: string | null; student_no: string | null; sheet_row: string | null; programme_given: string | null; programme_code_given: string | null;
  department_given: string | null; faculty_given: string | null; status_given: string | null; programme_name: string | null;
  department_name: string | null; faculty_name: string | null;
}
export interface Summary {
  id: string; reference: string; kind: BatchKind; state: string; fileName: string; rowsExpected: number; rowsStaged: number; notify: boolean;
  startedAt: string; startedBy: string | null; checkedAt: string | null; completedAt: string | null; abandonedReason: string | null;
  checked: number; ready: number; warnings: number; duplicates: number; conflicts: number; review: number; errors: number;
  newApplicants: number; existingApplicants: number; alreadyStudents: number; admitted: number;
  creates: number; updates: number; reconciles: number; links: number; programmesNotMapped: number; missingData: number;
  proposedFees: number; proposedDocuments: number; readyToImport: number; imported: number;
  created: number; updated: number; reconciled: number; linked: number; unchanged: number; skipped: number; failed: number;
  feesPosted: number; feesUnderReview: number; feesForBursary: number; documents: number; documentsMissing: number;
  importedBefore?: string | null; processed?: number;
}

/** the sheets of the template, by name */
export const SHEET = { guide: "Guide", faculties: "Faculties", departments: "Departments", programmes: "Programmes", specialisations: "Specialisations",
  sessions: "Sessions", statuses: "Statuses" } as const;
export const dataSheetName = (k: Kind) => (k === "ADMITTED" ? "Admitted PG Applicants" : "PG Applicants");
export const kindWord = (k: BatchKind | string) => (k === "ADMITTED" ? "Admitted PG applicants" : k === "FEES" ? "Application fee payments" : "PG applicants");
/** the rows a template leaves for data under its header, each with its drop-downs */
export const TEMPLATE_ROWS = 2000;
/** the letterhead's rows above the column header */
const HEAD_ROWS = 5;

/** a spreadsheet value that would run as a formula when the report is opened is written as text */
export function safeCell(v: Cell): ReportCell {
  if (v === undefined) return null;
  if (typeof v !== "string") return v;
  return /^[=+\-@\t\r]/.test(v) ? `'${v}` : v;
}

/** the template: the data sheet (letterhead, the columns with required ones marked, drop-downs), the guide with an example
 *  row, and this portal's reference lists — never ids to type, only names and codes the upload resolves */
export function templateSheets(t: TemplateData, title: string, school: string): SheetSpec[] {
  const headers = ["S/N", ...t.columns.map((c) => (c.required ? `${c.header} *` : c.header))];
  const head: Cell[][] = [[null, school], [null, title], [null, "One row per applicant from the row below the header. Columns marked * are required; the Guide sheet says what each column takes."], [], []];
  const data: Cell[][] = [...head, headers];
  const first = HEAD_ROWS + 2;               // the first data row, 1-based
  const last = first + TEMPLATE_ROWS - 1;
  const colOf = (key: string) => t.columns.findIndex((c) => c.key === key) + 1;   // 0-based in the sheet: S/N is 0
  const range = (sheet: string, col: string, n: number) => `'${sheet}'!$${col}$2:$${col}$${Math.max(n + 1, 2)}`;
  const validations: [string, Omit<ListValidation, "sqref">][] = [
    ["faculty", { range: range(SHEET.faculties, "B", t.faculties.length) }],
    ["department", { range: range(SHEET.departments, "B", t.departments.length) }],
    ["programme", { range: range(SHEET.programmes, "B", t.programmes.length) }],
    ["programmeCode", { range: range(SHEET.programmes, "A", t.programmes.length) }],
    ["session", { range: range(SHEET.sessions, "A", t.sessions.length) }],
    ["admissionSession", { range: range(SHEET.sessions, "A", t.sessions.length) }],
    ["gender", { list: ["Male", "Female"] }],
    ["applicationStatus", { range: range(SHEET.statuses, "A", t.statuses.length) }],
    ["admissionStatus", { range: range(SHEET.statuses, "A", t.statuses.length) }],
    ["applicationFeeStatus", { list: ["Verified", "Paid", "Unpaid"] }],
    ["acceptanceStatus", { list: ["Accepted"] }],
    ["acceptanceVerification", { list: ["Verified", "Paid"] }],
    ["screeningDecision", { list: ["Cleared", "Not cleared", "Correction required", "Pending"] }],
    ["schoolFeesSemester", { list: ["First", "Second"] }],
  ];
  const sheetValidations: ListValidation[] = validations.filter(([k]) => colOf(k) > 0).map(([k, v]) => {
    const c = colName(colOf(k));
    return { sqref: `${c}${first}:${c}${last}`, ...v, prompt: t.columns.find((x) => x.key === k)?.note ?? undefined };
  });
  const guide: Cell[][] = [[null, school], [null, `${title}: the guide`], [], [],
    ["S/N", "Column", "Section", "Required", "What it takes", "Example"],
    ...t.columns.map((c, i) => [i + 1, c.header, c.section, c.required ? "Yes" : "No", c.note ?? "", exampleOf(c.key, t)])];
  return [
    [dataSheetName(t.kind), data, { freezeBelow: HEAD_ROWS + 1, validations: sheetValidations }],
    [SHEET.guide, guide, { freezeBelow: 5 }],
    [SHEET.faculties, [["Code", "Faculty"], ...t.faculties.map((f) => [f.code, f.name])]],
    [SHEET.departments, [["Code", "Department", "Faculty"], ...t.departments.map((d) => [d.code, d.name, d.faculty])]],
    [SHEET.programmes, [["Code", "Programme", "Award", "Department", "Faculty"], ...t.programmes.map((p) => [p.code, p.name, p.award ?? "", p.department, p.faculty])]],
    [SHEET.specialisations, [["Programme code", "Programme", "Code", "Specialisation"], ...t.specialisations.map((s) => [s.programme_code, s.programme, s.code, s.name])]],
    [SHEET.sessions, [["Session", "Status"], ...t.sessions.map((s) => [s.name, s.state ?? ""])]],
    [SHEET.statuses, [["Old portal's word", "Read on this portal as"], ...t.statuses.map((s) => [s.word, stateWord(s.state)])]],
  ];
}

/** a made-up example of what a column takes, for the guide (never a real person) */
function exampleOf(key: string, t: TemplateData): string {
  const p = t.programmes[0];
  const ex: Record<string, string> = {
    legacyApplicationNo: "PGOLD/2025/00872", lastName: "Example", firstName: "Ada", gender: "Female", dateOfBirth: "14/02/1994",
    phone: "08030000000", email: "ada.example@example.com", session: t.sessions[0]?.name ?? "2025/2026", programme: p?.name ?? "",
    programmeCode: p?.code ?? "", faculty: p?.faculty ?? "", department: p?.department ?? "", applicationStatus: "Submitted",
    applicationFeeStatus: "Verified", applicationFeeReference: "OLDPAY-123456", applicationFeeAmount: "20000", applicationFeeDate: "03/01/2025",
    admissionStatus: "Admitted", admissionDate: "12/05/2025", acceptanceStatus: "Accepted", acceptanceFeeReference: "OLDPAY-654321",
    acceptanceFeeAmount: "50000", acceptanceVerification: "Verified", screeningDecision: "Cleared", docTranscript: "transcript-00872.pdf",
  };
  return ex[key] ?? "";
}

const norm = (s: string) => s.replace(/\*/g, "").replace(/\s+/g, " ").trim().toLowerCase();
/** headers an old export may use for a template column */
const ALIASES: Record<string, string> = {
  "application number": "legacyApplicationNo", "old application no": "legacyApplicationNo", "old application number": "legacyApplicationNo",
  "legacy application number": "legacyApplicationNo", "app no": "legacyApplicationNo", "appno": "legacyApplicationNo",
  "surname": "lastName", "last name": "lastName", "first name": "firstName", "middle name": "middleName", "other names": "otherNames",
  "applicant name": "fullName", "name": "fullName", "full name": "fullName", "sex": "gender", "dob": "dateOfBirth", "phone number": "phone",
  "gsm": "phone", "email address": "email", "state": "stateOfOrigin", "address": "address", "matric no": "matricNo", "matriculation no": "matricNo",
  "jamb no": "jambNo", "jamb reg no": "jambNo", "course": "programme", "programme name": "programme", "dept": "department",
};

export interface ReadFile { rows: Record<string, string>[]; rowNumbers: number[]; unknown: string[]; missing: string[]; sheet: string | null }

/** a filled template read back: the sheet whose header carries the old application number, its columns matched to the
 *  template's keys by their headers (required marks and spacing aside), blank rows left out */
export function readFile(sheets: { name: string; rows: string[][] }[], columns: Column[]): ReadFile {
  const byHeader = new Map(columns.map((c) => [norm(c.header), c.key]));
  const keys = new Set(columns.map((c) => c.key));
  for (const sh of sheets) {
    const h = sh.rows.findIndex((r) => r.some((v) => byHeader.get(norm(v ?? "")) === "legacyApplicationNo" || ALIASES[norm(v ?? "")] === "legacyApplicationNo"));
    if (h < 0) continue;
    const header = sh.rows[h];
    const map: (string | null)[] = header.map((v) => {
      const n = norm(v ?? "");
      if (!n || n === "s/n" || n === "sn") return null;
      const k = byHeader.get(n) ?? ALIASES[n] ?? (keys.has((v ?? "").trim()) ? (v ?? "").trim() : null);
      return k;
    });
    const unknown = header.filter((v, i) => norm(v ?? "") && !map[i] && !["s/n", "sn"].includes(norm(v ?? "")));
    const present = new Set(map.filter(Boolean) as string[]);
    const missing = columns.filter((c) => c.required && !present.has(c.key)
      && !(["lastName", "firstName"].includes(c.key) && present.has("fullName"))).map((c) => c.header);
    const rows: Record<string, string>[] = [];
    const rowNumbers: number[] = [];
    for (let i = h + 1; i < sh.rows.length; i++) {
      const r = sh.rows[i];
      const o: Record<string, string> = {};
      map.forEach((k, j) => {
        const v = (r[j] ?? "").replace(/\s+/g, " ").trim();
        if (k && v) o[k] = v;
      });
      if (Object.keys(o).length) {
        o.sheetRow = String(i + 1);   // the sheet's own row, for the error report
        rows.push(o);
        rowNumbers.push(i + 1);
      }
    }
    return { rows, rowNumbers, unknown, missing, sheet: sh.name };
  }
  return { rows: [], rowNumbers: [], unknown: [], missing: ["Old Application Number"], sheet: null };
}

/** the ranges [from, to] (1-based, inclusive) a file of n rows is sent, checked or imported in */
export function ranges(n: number, size: number): [number, number][] {
  const out: [number, number][] = [];
  for (let from = 1; from <= n; from += size) out.push([from, Math.min(n, from + size - 1)]);
  return out;
}

/** the SHA-256 of the file, in hex, as the server keeps it */
export async function sha256Hex(buf: ArrayBuffer): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", buf);
  return Array.from(new Uint8Array(d)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

export const VERDICT: Record<string, [string, "ok" | "info" | "warn" | "bad" | "grey"]> = {
  READY: ["Ready", "ok"], WARNING: ["Ready, with a note", "info"], DUPLICATE_IN_FILE: ["Duplicate in the file", "warn"],
  CONFLICT: ["Conflict", "bad"], REQUIRES_REVIEW: ["Requires review", "warn"], ERROR: ["Error", "bad"],
};
export const RESULT: Record<string, [string, "ok" | "info" | "warn" | "bad" | "grey"]> = {
  CREATED: ["Created", "ok"], UPDATED: ["Updated", "ok"], RECONCILED: ["Reconciled", "ok"], LINKED: ["Linked to the student", "ok"],
  UNCHANGED: ["Already on record", "grey"], SKIPPED: ["Not imported", "warn"], FAILED: ["Failed", "bad"],
};
export const MATCH: Record<string, string> = {
  NEW_APPLICANT: "New applicant", EXISTING_APPLICANT: "Existing applicant", EXISTING_STUDENT: "Already a student",
};
export const ACTION: Record<string, string> = {
  CREATE: "Create new", UPDATE: "Update existing", RECONCILE: "Reconcile", LINK_STUDENT: "Link to the student",
};
export const STATE_WORD: Record<string, string> = {
  SUBMITTED: "Submitted", DEPT_RECOMMENDED: "Dept recommended", DEPT_DECLINED: "Dept declined", FAC_RECOMMENDED: "Faculty recommended",
  FAC_DECLINED: "Faculty declined", OFFERED: "Admitted (offer)", NOT_OFFERED: "Not admitted", ACCEPTED: "Accepted", ADMITTED: "On the register",
};
export const stateWord = (s: string | null | undefined) => (s ? STATE_WORD[s] ?? s.toLowerCase().replace(/_/g, " ") : "—");
export const MIGRATION_STATUS: Record<string, string> = {
  MIGRATED_AND_PENDING: "Migrated · pending", MIGRATED_AND_ADMITTED: "Migrated · admitted", MIGRATED_AND_ACCEPTED: "Migrated · accepted",
  MIGRATED_AND_SCREENED: "Migrated · screened", MIGRATED_AND_STUDENT: "Migrated · student",
};
export const BATCH_STATE: Record<string, [string, "ok" | "info" | "warn" | "bad" | "grey"]> = {
  STAGING: ["Uploading", "info"], CHECKED: ["Checked", "info"], IMPORTING: ["Importing", "warn"], COMPLETED: ["Completed", "ok"], ABANDONED: ["Set aside", "grey"],
};

/** the row's first problem that holds it back, else its first note */
export function firstProblem(r: Pick<MigrationRow, "problems">): Problem | null {
  const ps = r.problems ?? [];
  return ps.find((p) => p.level !== "warning") ?? ps[0] ?? null;
}

/** can the School confirm a new applicant on this row (a possible same person, nothing else holding it)? */
export function mayConfirmNew(r: Pick<MigrationRow, "problems" | "verdict" | "result" | "decided_new">): boolean {
  if (r.result || r.decided_new || r.verdict !== "REQUIRES_REVIEW") return false;
  const held = (r.problems ?? []).filter((p) => p.level !== "warning");
  return held.length > 0 && held.every((p) => p.code === "POSSIBLE_SAME_APPLICANT" || p.code === "POSSIBLE_STUDENT");
}

export const REPORT_HEAD = ["Row", "Sheet row", "Applicant", "Old application number", "Status", "Error type", "Error message", "Suggested correction"];
/** the error report: a line for each problem of each row not plainly ready, in the file's row order */
export function reportLines(rows: MigrationRow[]): ReportCell[][] {
  const out: Cell[][] = [];
  for (const r of rows) {
    const status = r.result === "FAILED" ? "Failed" : (VERDICT[r.verdict ?? ""]?.[0] ?? r.verdict ?? "");
    const ps = r.problems ?? [];
    const at: Cell[] = [r.row_no, r.sheet_row ? Number(r.sheet_row) : null, r.applicant ?? "", r.legacy_no ?? "", status];
    if (r.result === "FAILED") out.push([...at, "IMPORT_FAILED", r.result_note ?? "", "Correct the row and upload it again."]);
    for (const p of ps) out.push([...at, p.code, p.message, p.fix ?? ""]);
  }
  return out.map((l) => l.map(safeCell));
}

export const HISTORY_HEAD = ["Batch reference", "Source", "File", "Total rows", "Created", "Updated", "Admitted", "Reconciled", "Duplicates", "Errors",
  "Started", "Completed", "Imported by", "Status"];
export interface BatchLine {
  id: string; reference: string; kind: BatchKind; state: string; file_name: string; rows_expected: number; started_at: string; completed_at: string | null;
  started_by: string | null; created: number; updated: number; reconciled: number; linked: number; unchanged: number; skipped: number; failed: number;
  admitted: number; duplicates: number; errors: number; conflicts: number; review: number; abandoned_reason: string | null;
}
const day = (v: string | null) => (v ? new Date(v).toLocaleString("en-GB", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "");
export function historyLines(rows: BatchLine[]): ReportCell[][] {
  return rows.map((b) => [b.reference, kindWord(b.kind), b.file_name, b.rows_expected, b.created, b.updated, b.admitted, b.reconciled, b.duplicates,
    b.errors + b.failed, day(b.started_at), day(b.completed_at), b.started_by ?? "", BATCH_STATE[b.state]?.[0] ?? b.state].map(safeCell));
}

/** the progress of a chunked step, in real rows */
export function progressWords(step: "upload" | "check" | "import", done: number, total: number): string {
  const verb = step === "upload" ? "Sending" : step === "check" ? "Checking" : "Importing";
  return `${verb} ${done.toLocaleString("en-GB")} / ${total.toLocaleString("en-GB")} rows`;
}
