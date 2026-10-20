/** V588: inter-university transfer — the template's columns, a faculty's students written into an outgoing template, a filled file
 *  read back by its column names (wherever the header row sits under the branding), and the shapes the API answers with. Node-tested. */

/** the template's columns: what the row says, under the names the database reads them by */
export const COLUMNS: [string, string][] = [
  ["direction", "Transfer Direction"], ["matric_no", "Student Matriculation Number"], ["jamb_reg_no", "JAMB Number"], ["student", "Student Name"],
  ["sex", "Sex"], ["date_of_birth", "Date of Birth"], ["email", "Email"], ["phone", "Phone"],
  ["faculty", "Faculty Code"], ["dept", "Department Code"], ["programme", "Programme Code"], ["level", "Level"],
  ["university_code", "University Code"], ["other_programme", "Other University Programme"], ["other_level", "Other University Level"],
  ["effective_session", "Effective Session"], ["reason", "Reason"], ["approval_ref", "Approval Reference"], ["remarks", "Remarks"],
];

export interface TemplateStudent { matric_no: string | null; jamb_reg_no: string | null; student: string; faculty_code: string; dept_code: string; programme_code: string; programme: string; current_level: number; status: string }

/** an outgoing template's rows: each student as the record holds them, the destination university left for the office to fill */
export function outgoingRows(students: TemplateStudent[], session: string): (string | number)[][] {
  return students.map((s) => ["OUTGOING", s.matric_no ?? "", s.jamb_reg_no ?? "", s.student, "", "", "", "", s.faculty_code, s.dept_code, s.programme_code,
    s.current_level, "", "", "", session, "", "", ""]);
}

const norm = (s: string) => s.toLowerCase().replace(/[^a-z]/g, "");
const KEYS = new Map(COLUMNS.flatMap(([k, label]) => [[norm(label), k], [norm(k), k]] as [string, string][]));
// the names a column may also carry
for (const [alias, k] of [["Direction", "direction"], ["Matriculation Number", "matric_no"], ["Matric No", "matric_no"], ["JAMB", "jamb_reg_no"],
  ["JAMB Registration Number", "jamb_reg_no"], ["Name", "student"], ["Gender", "sex"], ["E-mail", "email"], ["Phone Number", "phone"],
  ["Previous University Code", "university_code"], ["Destination University Code", "university_code"], ["Previous Programme", "other_programme"],
  ["Destination Programme", "other_programme"], ["Previous Level", "other_level"]] as [string, string][]) KEYS.set(norm(alias), k);

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

/** the transfers report's rows, S/N first */
export function reportRows(rows: Transfer[]): (string | number)[][] {
  return rows.map((t, i) => [i + 1, t.batch_ref, DIRECTION[t.direction], t.student ?? "", t.matric_no ?? "", t.jamb_reg_no ?? "", t.university,
    t.other_programme ?? "", t.other_level ?? "", t.programme ?? t.programme_code ?? "", t.level ?? "", t.effective_session, outcome(t), t.decided_by_name ?? "",
    t.decided_at ? t.decided_at.slice(0, 10) : ""]);
}
