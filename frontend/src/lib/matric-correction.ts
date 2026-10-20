/** V579: a matriculation number corrected, the old number kept — the shapes the API answers with, the words for kinds and states,
 *  the number as the register keeps it, the faculty → department → programme narrowing. Node-tested. */

export interface FoundStudent {
  student_id: string; surname: string; other_names: string; matric_no: string | null; former_no: string | null; corrected_by: string | null;
  admission_no: string | null; jamb_reg_no: string | null; programme_code: string | null; programme: string | null; dept_code: string | null;
  department: string | null; faculty_code: string | null; faculty: string | null; current_level: number | null; status: string; pending_ref: string | null;
}
export interface CheckStudent {
  id: string; surname: string; otherNames: string; matricNo: string | null; admissionNo: string | null; jambRegNo: string | null; programmeCode: string | null;
  programme: string | null; department: string | null; faculty: string | null; level: number | null; status: string; entrySession: string | null;
}
export interface Finding { code: string; message: string }
export interface Parts { university: string | null; faculty: string | null; programme: string | null; year: string | null; sequence: number | null }
export interface Check {
  ok: boolean; student?: CheckStudent; newNo?: string; parts?: Parts | null;
  configured?: { university: string | null; faculty: string | null; programme: string | null; year: string | null; series: string | null; problem: string | null };
  problems: Finding[]; points: Finding[];
}
export interface Suggestion { label: string; matric_no: string; taken: string | null }
export interface NumberEvent { at: string | null; event: "ISSUED" | "ON_THE_REGISTER" | "CORRECTED"; matric_no: string; previous_no: string | null; ref: string | null; reason: string | null; by_name: string | null; office: string | null }
export type CorrectionState = "PENDING_REVIEW" | "COMPLETED" | "REJECTED" | "CANCELLED";
export interface Correction {
  id: string; ref: string; student_id: string; surname: string; other_names: string; programme: string | null; current_level: number | null;
  old_no: string; new_no: string; current_no: string | null; kind: string; reason: string; approval_ref: string | null; state: CorrectionState;
  check_points: Finding[]; prepared_by: string; prepared_by_name: string | null; prepared_office: string | null; prepared_at: string;
  decided_by_name: string | null; decided_office: string | null; decided_at: string | null; decision_note: string | null;
  cancelled_by_name: string | null; cancelled_at: string | null; cancel_reason: string | null; evidence: number;
}
/** one correction as GET /{id} answers: its evidence the files themselves, the check as it stands while it waits */
export type CorrectionDetail = Omit<Correction, "evidence"> & { check?: Check; mayDecide: boolean; evidence: EvidenceFile[] };
export interface EvidenceFile { id: string; filename: string; content_type: string; size_bytes: number; added_at: string; added_by: string | null }
export interface StudentView { student: CheckStudent; suggestions: Suggestion[]; history: NumberEvent[]; corrections: Correction[] }
export interface Place { code: string; name: string; deptCode: string; department: string; facultyCode: string; faculty: string; category: string }

export const KINDS: [string, string][] = [
  ["LEGACY_MIGRATION", "Legacy migration error"],
  ["FACULTY_CODE", "Wrong faculty code"],
  ["PROGRAMME_CODE", "Wrong programme code"],
  ["YEAR", "Wrong year"],
  ["SERIES", "Wrong series"],
  ["SEQUENCE", "Wrong sequence"],
  ["DUPLICATE", "Duplicate assignment"],
  ["DATA_ENTRY", "Data entry error"],
  ["PROGRAMME_CHANGE", "Approved programme change"],
  ["OTHER", "Another verified error"],
];
export const kindWord = (k: string) => KINDS.find(([c]) => c === k)?.[1] ?? k;

export const STATE: Record<CorrectionState, { label: string; tone: "ok" | "info" | "warn" | "bad" | "grey" }> = {
  PENDING_REVIEW: { label: "Waiting for a decision", tone: "warn" },
  COMPLETED: { label: "Corrected", tone: "ok" },
  REJECTED: { label: "Rejected", tone: "bad" },
  CANCELLED: { label: "Cancelled", tone: "grey" },
};

export const EVENT: Record<NumberEvent["event"], string> = {
  ISSUED: "Issued by the portal",
  ON_THE_REGISTER: "On the register (from the old portal)",
  CORRECTED: "Corrected",
};

/** a number as the register keeps it: upper case, no spaces */
export function normalNo(s: string | null | undefined): string {
  return (s ?? "").replace(/\s+/g, "").toUpperCase();
}

/** the parts of a number, in reading order, the missing ones left out */
export function partsLine(p: Parts | null | undefined): string {
  if (!p) return "";
  return [p.university, p.faculty, p.programme, p.year, p.sequence == null ? null : String(p.sequence)].filter((x) => x != null && x !== "").join(" · ");
}

/** the faculties, the departments of the faculty chosen, the programmes of the department (or faculty) chosen */
export function narrow(places: Place[], faculty: string, dept: string) {
  const uniq = <T,>(xs: T[], key: (x: T) => string) => { const seen = new Set<string>(); return xs.filter((x) => { const k = key(x); if (seen.has(k)) return false; seen.add(k); return true; }); };
  const faculties = uniq(places, (p) => p.facultyCode).map((p) => ({ code: p.facultyCode, name: p.faculty })).sort((a, b) => a.name.localeCompare(b.name));
  const inFac = faculty ? places.filter((p) => p.facultyCode === faculty) : places;
  const departments = uniq(inFac, (p) => p.deptCode).map((p) => ({ code: p.deptCode, name: p.department })).sort((a, b) => a.name.localeCompare(b.name));
  const programmes = (dept ? inFac.filter((p) => p.deptCode === dept) : inFac).map((p) => ({ code: p.code, name: p.name })).sort((a, b) => a.name.localeCompare(b.name));
  return { faculties, departments, programmes };
}

/** what keeps a prepared correction from going: no number, a problem the check found, no kind, a reason too short */
export function prepareBlock(check: Check | null, kind: string, reason: string): string | null {
  if (!check) return "Give the correct number and wait for the check.";
  if (check.problems.length) return check.problems[0].message;
  if (!kind) return "Say what was wrong with the number.";
  if (reason.trim().length < 10) return "Give the reason, ten characters or more.";
  return null;
}

/** a file the evidence upload takes: PDF, JPEG or PNG, up to 5 MB */
export function evidenceProblem(f: { name: string; size: number; type: string }): string | null {
  if (!["application/pdf", "image/jpeg", "image/png"].includes(f.type)) return "Evidence is a PDF, JPEG or PNG file.";
  if (f.size <= 0 || f.size > 5 * 1024 * 1024) return "Evidence is up to 5 MB.";
  return null;
}
