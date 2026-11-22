/** V588: inter-university transfer — the template's columns, a faculty's students written into an outgoing template, a filled file
 *  read back by its column names (wherever the header row sits under the branding), and the shapes the API answers with.
 *  V763: the transfer form — one student, its fields, the body the API takes and what the form must give before it is checked.
 *  Node-tested. */

/** the template's columns: what the row says, under the names the database reads them by */
export const COLUMNS: [string, string][] = [
  ["direction", "Transfer Direction"], ["matric_no", "Student Matriculation Number"], ["jamb_reg_no", "JAMB Number"], ["student", "Student Name"],
  ["sex", "Sex"], ["date_of_birth", "Date of Birth"], ["email", "Email"], ["phone", "Phone"],
  ["faculty", "Faculty Code"], ["dept", "Department Code"], ["programme", "Programme Code"], ["level", "Level"],
  ["university_code", "University Code"], ["other_programme", "Other University Programme"], ["other_level", "Other University Level"],
  ["other_matric_no", "Other University Matriculation Number"], ["other_entry_session", "Other University Entry Session"], ["other_cgpa", "Other University CGPA"],
  ["other_cgpa_scale", "CGPA Scale"], ["documents", "Documents Seen"],
  ["effective_session", "Effective Session"], ["reason", "Reason"], ["approval_ref", "Approval Reference"], ["remarks", "Remarks"],
];

export interface TemplateStudent { matric_no: string | null; jamb_reg_no: string | null; student: string; faculty_code: string; dept_code: string; programme_code: string; programme: string; current_level: number; status: string }

/** an outgoing template's rows: each student as the record holds them, the destination university left for the office to fill */
export function outgoingRows(students: TemplateStudent[], session: string): (string | number)[][] {
  return students.map((s) => ["OUTGOING", s.matric_no ?? "", s.jamb_reg_no ?? "", s.student, "", "", "", "", s.faculty_code, s.dept_code, s.programme_code,
    s.current_level, "", "", "", "", "", "", "", "", session, "", "", ""]);
}

const norm = (s: string) => s.toLowerCase().replace(/[^a-z]/g, "");
const KEYS = new Map(COLUMNS.flatMap(([k, label]) => [[norm(label), k], [norm(k), k]] as [string, string][]));
// the names a column may also carry
for (const [alias, k] of [["Direction", "direction"], ["Matriculation Number", "matric_no"], ["Matric No", "matric_no"], ["JAMB", "jamb_reg_no"],
  ["JAMB Registration Number", "jamb_reg_no"], ["Name", "student"], ["Gender", "sex"], ["E-mail", "email"], ["Phone Number", "phone"],
  ["Previous University Code", "university_code"], ["Destination University Code", "university_code"], ["Previous Programme", "other_programme"],
  ["Destination Programme", "other_programme"], ["Previous Level", "other_level"], ["Previous Matriculation Number", "other_matric_no"],
  ["Session Entered", "other_entry_session"], ["CGPA", "other_cgpa"], ["Documents", "documents"]] as [string, string][]) KEYS.set(norm(alias), k);

/** a filled file read back: the header row found (the branding sits above it), each row by its column names, empty rows left out */
export function readUniversitySheet(grid: string[][]): { rows: Record<string, string>[]; problem: string | null } {
  const hi = grid.slice(0, 30).findIndex((r) => {
    const keys = r.map((c) => KEYS.get(norm(String(c ?? ""))));
    return keys.includes("direction") && keys.includes("university_code") && (keys.includes("matric_no") || keys.includes("jamb_reg_no"));
  });
  if (hi < 0) return { rows: [], problem: "No header naming “Transfer Direction”, “University Code” and a matriculation or JAMB number was found in the first 30 rows. Use the template." };
  const head = grid[hi].map((c) => KEYS.get(norm(String(c ?? ""))) ?? null);
  const rows: Record<string, string>[] = [];
  for (const r of grid.slice(hi + 1)) {
    const row: Record<string, string> = {};
    head.forEach((k, i) => { if (k) { const v = String(r[i] ?? "").trim(); if (v) row[k] = v; } });
    if (row.matric_no || row.jamb_reg_no) rows.push(row);
  }
  return { rows, problem: rows.length ? null : "The file has no row with a matriculation or JAMB number." };
}

export interface Place { faculty: string | null; dept: string | null; programme: string | null; level: number | null; programmeName?: string | null; status?: string | null }
export interface Finding { code: string; text: string }
export type Direction = "INCOMING" | "OUTGOING";
export type Action = "TRANSFER_OUT" | "RECORD_ON_EXISTING" | "CREATE_FROM_APPLICANT" | "CREATE";
export interface CheckedRow {
  row: number; direction: Direction | null; action: Action | null; status: "VALID" | "WARNING" | "INVALID"; studentId: string | null; candidateId: string | null;
  matchedBy: string | null; student: string | null; matricNo: string | null; jambRegNo: string | null; current: Place | null; placement: Place;
  university: string | null; universityName: string | null; otherProgramme: string | null; otherLevel: string | null; session: string; reason: string | null;
  problems: Finding[]; warnings: Finding[];
  // V763: the particulars a form (or a file's columns) gives
  surname?: string | null; otherNames?: string | null; sex?: string | null; dateOfBirth?: string | null;
  otherMatricNo?: string | null; otherEntrySession?: string | null; otherCgpa?: number | null; otherCgpaScale?: number | null; documents?: string[]; remarks?: string | null;
}
export interface Validation { total: number; valid: number; warnings: number; invalid: number; duplicates: number; incoming: number; outgoing: number; newRecords: number; rows: CheckedRow[] }

export const STATUS: Record<CheckedRow["status"], [string, "ok" | "warn" | "bad"]> = {
  VALID: ["Valid", "ok"], WARNING: ["Valid — look at", "warn"], INVALID: ["Invalid", "bad"],
};

/** what the decision does with the row */
export const ACTION: Record<Action, string> = {
  TRANSFER_OUT: "Transferred out; the record is kept",
  RECORD_ON_EXISTING: "Recorded on the student's existing record",
  CREATE_FROM_APPLICANT: "A new record, the applicant linked",
  CREATE: "A new record",
};

export const DIRECTION: Record<Direction, string> = { INCOMING: "Incoming", OUTGOING: "Outgoing" };

/** what a row says in one line: its problems, else its review points */
export function rowWords(r: Pick<CheckedRow, "problems" | "warnings">): string {
  return (r.problems.length ? r.problems : r.warnings).map((p) => p.text || p.code).join("; ");
}

const place = (p: Place | null) => (p ? [p.faculty, p.dept, p.programme, p.level].map((x) => x ?? "").join(" / ") : "");

/** the error report: every row as it was checked, its status and why */
export function errorReportRows(rows: CheckedRow[]): (string | number)[][] {
  return rows.map((r) => [r.row, r.direction ? DIRECTION[r.direction] : "", r.student ?? "", r.matricNo ?? "", r.jambRegNo ?? "", r.university ?? "",
    STATUS[r.status][0], place(r.current), place(r.placement), r.action && r.status !== "INVALID" ? ACTION[r.action] : "", rowWords(r)]);
}

export interface Transfer {
  id: string; batch_id: string; batch_ref: string; row_no: number; direction: Direction; status: "PENDING_APPROVAL" | "COMPLETED" | "REJECTED"; student_id: string | null;
  student: string | null; matric_no: string | null; jamb_reg_no: string | null; university_code: string; university: string; other_programme: string | null;
  other_level: number | null; programme_code: string | null; programme: string | null; level: number | null; effective_session: string; created_student: boolean;
  matched_by: string | null; prepared_by_name: string | null; prepared_at: string; decided_by_name: string | null; decided_at: string | null; decision_note: string | null;
  // V763
  other_matric_no?: string | null; other_entry_session?: string | null; other_cgpa?: number | string | null; other_cgpa_scale?: number | null; documents?: string[];
  remarks?: string | null; source?: "FILE" | "FORM" | "APPLICATION";
  /** V766: the online application the transfer was approved from (or, for one the deciding officer rejected, the application it came from) */
  application?: { id: string; applicationNo: string } | null;
}

export const TRANSFER: Record<Transfer["status"], [string, "ok" | "warn" | "bad"]> = {
  PENDING_APPROVAL: ["Waiting", "warn"], COMPLETED: ["Completed", "ok"], REJECTED: ["Rejected", "bad"],
};

/** what a decided transfer did, in a word */
export function outcome(t: Pick<Transfer, "direction" | "status" | "created_student">): string {
  if (t.status === "PENDING_APPROVAL") return "Waiting for another officer";
  if (t.status === "REJECTED") return "Rejected";
  if (t.direction === "OUTGOING") return "Transferred out";
  return t.created_student ? "Taken on: a new record" : "Taken on: the existing record";
}

/** a CGPA as the transfer keeps it: "3.45 of 5" */
export function cgpaWords(cgpa: number | string | null | undefined, scale: number | null | undefined): string {
  if (cgpa === null || cgpa === undefined || cgpa === "") return "";
  return `${Number(cgpa).toFixed(2)} of ${scale ?? 5}`;
}

/** the transfers report's rows, S/N first */
export function reportRows(rows: Transfer[]): (string | number)[][] {
  return rows.map((t, i) => [i + 1, t.batch_ref, DIRECTION[t.direction], t.student ?? "", t.matric_no ?? "", t.jamb_reg_no ?? "", t.university,
    t.other_programme ?? "", t.other_level ?? "", t.other_matric_no ?? "", cgpaWords(t.other_cgpa, t.other_cgpa_scale), t.programme ?? t.programme_code ?? "",
    t.level ?? "", t.effective_session, t.source === "FORM" ? "Form" : t.source === "APPLICATION" ? "Online application" : "File", outcome(t), t.decided_by_name ?? "", t.decided_at ? t.decided_at.slice(0, 10) : ""]);
}

// ── V763: the inter-university transfer form ───────────────────────────────────────────────────────────────────────────

/** the documents the officer saw, by direction: a student coming in, a student going out */
export const DOCUMENTS: { code: string; label: string; direction: Direction }[] = [
  { code: "TRANSCRIPT", label: "Academic transcript from the previous university", direction: "INCOMING" },
  { code: "RELEASE_LETTER", label: "Letter of release from the previous university", direction: "INCOMING" },
  { code: "JAMB_ADMISSION_LETTER", label: "JAMB admission letter", direction: "INCOMING" },
  { code: "OLEVEL_RESULT", label: "O'Level result", direction: "INCOMING" },
  { code: "STUDENT_APPLICATION", label: "The student's written application", direction: "OUTGOING" },
  { code: "ACCEPTANCE_LETTER", label: "The receiving university's letter of acceptance", direction: "OUTGOING" },
];

/** the documents seen, in words */
export function documentWords(codes: string[] | undefined | null): string {
  return (codes ?? []).map((c) => DOCUMENTS.find((d) => d.code === c)?.label ?? c).join("; ");
}

export interface TransferForm {
  direction: Direction;
  /** coming in: the JAMB number; going out: the matriculation or JAMB number */
  number: string;
  surname: string; otherNames: string; sex: "" | "M" | "F"; dateOfBirth: string; email: string; phone: string;
  faculty: string; dept: string; programme: string; level: string;
  universityCode: string; otherProgramme: string; otherLevel: string; otherMatricNo: string; otherEntrySession: string; otherCgpa: string; otherCgpaScale: "4" | "5";
  documents: string[];
  session: string; reason: string; approvalRef: string; remarks: string;
}

export function emptyForm(direction: Direction = "INCOMING"): TransferForm {
  return { direction, number: "", surname: "", otherNames: "", sex: "", dateOfBirth: "", email: "", phone: "", faculty: "", dept: "", programme: "", level: "",
    universityCode: "", otherProgramme: "", otherLevel: "", otherMatricNo: "", otherEntrySession: "", otherCgpa: "", otherCgpaScale: "5", documents: [],
    session: "", reason: "", approvalRef: "", remarks: "" };
}

export interface LookupStudent {
  id: string; name: string; surname: string; otherNames: string; sex: string | null; dateOfBirth: string | null; matricNo: string | null; jambRegNo: string | null;
  status: string; live: boolean; faculty: string | null; dept: string | null; programme: string | null; programmeName: string | null; level: number | null;
}
export interface LookupApplicant {
  id: string; session: string; surname: string | null; otherNames: string | null; sex: string | null; programme: string | null; programmeName: string | null;
  offerState: string | null;
}
/** who a number found (people.university_transfer_lookup) */
export interface Lookup {
  number: string; direction?: Direction | null; matchedBy?: string | null; student?: LookupStudent | null; applicant?: LookupApplicant | null; pendingRef?: string | null;
}

/** a number as the database reads one: no spaces, capitals */
export const numberOf = (v: string) => v.replace(/\s+/g, "").toUpperCase();
const levelOf = (v: string) => (/^\d{3}$/.test(v.trim()) ? Number(v.trim()) : null);

/** the lookup, while it is the one for the number and direction the form now holds; else none */
export function lookedUp(f: Pick<TransferForm, "number" | "direction">, found: Lookup | null): Lookup | null {
  return found && found.number === numberOf(f.number) && (found.direction == null || found.direction === f.direction) ? found : null;
}

/** the form as the API takes it. Coming in, the number is the JAMB number, and the student's particulars go with it unless a record
 *  holds them already; going out, the student is the one the number found — their matriculation number (or, before they have one,
 *  the JAMB number) and the placement the record holds, so the row never states another. The particulars and documents of the other
 *  direction are left out. */
export function formBody(f: TransferForm, found: Lookup | null): Record<string, unknown> {
  const t = (v: string) => v.trim();
  const body: Record<string, unknown> = { direction: f.direction, universityCode: t(f.universityCode).toUpperCase(), otherProgramme: t(f.otherProgramme),
    otherLevel: levelOf(f.otherLevel), otherMatricNo: numberOf(f.otherMatricNo), remarks: t(f.remarks) };
  const docs = (d: Direction) => f.documents.filter((c) => DOCUMENTS.some((x) => x.code === c && x.direction === d));
  if (f.direction === "OUTGOING") {
    const s = lookedUp(f, found)?.student ?? null;
    if (s) {
      Object.assign(body, { matricNo: s.matricNo ?? "", jambRegNo: s.matricNo ? "" : s.jambRegNo ?? "", faculty: s.faculty ?? "", dept: s.dept ?? "",
        programme: s.programme ?? "", level: s.level });
    } else {
      body.matricNo = numberOf(f.number);
    }
    body.documents = docs("OUTGOING");
    return body;
  }
  Object.assign(body, { jambRegNo: numberOf(f.number), faculty: f.faculty, dept: f.dept, programme: f.programme, level: levelOf(f.level),
    otherEntrySession: f.otherEntrySession.replace(/\s+/g, ""), otherCgpa: t(f.otherCgpa), otherCgpaScale: t(f.otherCgpa) ? Number(f.otherCgpaScale) : null,
    documents: docs("INCOMING") });
  if (!lookedUp(f, found)?.student) {
    Object.assign(body, { surname: t(f.surname).toUpperCase(), otherNames: t(f.otherNames), sex: f.sex, dateOfBirth: f.dateOfBirth,
      email: t(f.email).toLowerCase(), phone: t(f.phone) });
  }
  return body;
}

export type FormField = keyof TransferForm;

/** what the form must give before it is checked, field by field and in the page's order (so the first is the one to put right
 *  first, never a control still closed) — the database checks the rest and says it. Either way the number must have been looked
 *  up as it stands: the form is about the student the number finds. */
export function formErrors(f: TransferForm, found: Lookup | null, registering = false): Partial<Record<FormField, string>> {
  const e: Partial<Record<FormField, string>> = {};
  const n = numberOf(f.number);
  const current = !!lookedUp(f, found);
  const student = current ? found!.student ?? null : null;
  if (f.direction === "INCOMING") {
    if (!n) e.number = "Give the student's JAMB registration number: it is how the student is matched, so no one is placed twice";
    else if (!current) e.number = "Press Find: the form is about the student the JAMB number finds";
    if (!student) {
      if (!f.surname.trim()) e.surname = "Give the surname";
      if (!f.otherNames.trim()) e.otherNames = "Give the other names";
      if (!f.sex) e.sex = "Choose the sex";
      if (!/^\d{4}-\d{2}-\d{2}$/.test(f.dateOfBirth)) e.dateOfBirth = "Give the date of birth";
      if (f.email.trim() && !/^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$/.test(f.email.trim())) e.email = "That is not an e-mail address";
      const digits = f.phone.replace(/[^0-9]/g, "");
      if (f.phone.trim() && !(/^0\d{10}$/.test(digits) || /^234\d{10}$/.test(digits))) e.phone = "A Nigerian phone number: 11 digits from 0, or +234";
    }
  } else {
    if (!n) e.number = "Give the student's matriculation or JAMB number";
    else if (!current) e.number = "Press Find: the transfer is made on the record the number finds";
    else if (!student) e.number = "No student holds that number";
    else if (!student.live) e.number = `The record is ${student.status.toLowerCase().replace(/_/g, " ")}; only a live record is transferred out`;
  }
  if (!f.universityCode.trim()) e.universityCode = f.direction === "INCOMING" ? "Choose the previous university" : "Choose the receiving university";
  if (!f.otherProgramme.trim()) e.otherProgramme = f.direction === "INCOMING" ? "Give the programme studied there" : "Give the programme the student goes into there";
  if (f.direction === "INCOMING") {
    if (!/^\d{3}$/.test(f.otherLevel.trim())) e.otherLevel = "Give the level reached there (100, 200 …)";
    if (!f.otherMatricNo.trim()) e.otherMatricNo = "Give the matriculation number at the previous university";
    const es = f.otherEntrySession.replace(/\s+/g, "");
    if (es && !(/^\d{4}\/\d{4}$/.test(es) && Number(es.slice(5)) === Number(es.slice(0, 4)) + 1)) e.otherEntrySession = "Written 2022/2023";
    const g = f.otherCgpa.trim();
    if (g && !/^\d(\.\d{1,2})?$/.test(g)) e.otherCgpa = "A number with up to two decimals, such as 3.45";
    else if (g && Number(g) > Number(f.otherCgpaScale)) e.otherCgpa = `Above the ${f.otherCgpaScale}-point scale`;
    // the placement asked for one control at a time: each opens once the one before it is chosen
    if (!f.faculty) e.faculty = "Choose the faculty the student comes into";
    else if (!f.dept) e.dept = "Choose the department";
    else if (!f.programme) e.programme = "Choose the programme the student comes into";
    else if (!/^\d{3}$/.test(f.level)) e.level = "Choose the level the student comes into";
  }
  if (registering && f.reason.trim().length < 10) e.reason = "Ten characters or more: the Senate's approval, the transfer policy";
  return e;
}
