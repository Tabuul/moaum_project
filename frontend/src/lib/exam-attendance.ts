/** V652: examination attendance — the sheet as issued, the class as marked, the handwritten rows, the reconciliation; the words
 *  each code prints as. Read from /api/v1/exams/attendance. */

export interface SheetStudent {
  student: string; matric: string | null; jamb: string | null; name: string; programme: string; programmeCode: string; level: number | null;
  registration: string; carryOver: boolean; eligible: boolean; eligibility: "CARD" | "NO_CARD" | "PERMIT" | "NO_PERMIT";
}

export interface ClassInfo {
  offering_id: string; session: string; semester: number; course_code: string; shown_code: string; course_title: string; units: number;
  level: number | null; kind: string | null; general_office: string | null; course_dept: string | null; course_department: string | null;
  course_faculty: string | null; course_faculty_name: string | null; exam_on: string | null; starts_at: string | null; ends_at: string | null; venue: string | null;
}

export interface Sheet {
  id: string; reference: string; series: string; version: number; students: number; manual_lines: number; list: SheetStudent[];
  scope_fac: string | null; scope_dept: string | null; scope_prog: string | null; faculty: string | null; department: string | null; programme: string | null;
  exam_on: string | null; starts_at: string | null; ends_at: string | null; venue: string | null; reason: string | null;
  generated_office: string | null; generated_at: string; generated_by_name: string | null; latest_reference?: string | null; offering: ClassInfo;
}

export interface SheetRow {
  id: string; reference: string; series: string; version: number; students: number; manual_lines: number; scope_fac: string | null; scope_dept: string | null;
  scope_prog: string | null; reason: string | null; generated_office: string | null; generated_at: string; generated_by_name: string | null;
  faculty: string | null; department: string | null; programme: string | null;
}

export interface MarkRow {
  student_id: string; matric_no: string | null; jamb_no: string | null; full_name: string; sex: string | null; programme_code: string; programme: string;
  dept_code: string; faculty_code: string; level: number | null; registration_status: string; entry_type: string | null; eligible: boolean; eligibility: string;
  attendance: string | null; source: string | null; sheet_reference: string | null; invigilator: string | null; reason: string | null;
  recorded_at: string | null; verified_at: string | null;
}

export interface ManualRow {
  student_id: string; matric_no: string | null; full_name: string; programme: string; level: number | null; attendance: string; source: string;
  sheet_reference: string | null; reason: string | null; recorded_at: string; verified_at: string | null;
}

export interface Marking {
  offering: ClassInfo;
  scope: { fac: string | null; dept: string | null; prog: string | null; faculty?: string | null; department?: string | null; programme?: string | null };
  students: MarkRow[]; manual: ManualRow[]; keeper: boolean;
}

export interface PendingRow {
  id: string; offering_id: string; written_name: string; written_number: string | null; written_programme: string | null; written_level: string | null;
  reason: string | null; sheet_reference: string | null; invigilator: string | null; state: "PENDING" | "MATCHED" | "INVALID"; student_id: string | null;
  decided_at: string | null; decision_note: string | null; entered_office: string | null; entered_at: string; matched_matric: string | null; matched_name: string | null;
}

export interface ReconRow {
  student_id: string; matric_no: string | null; full_name: string; programme: string; level: number | null; registered: boolean; eligible: boolean;
  on_list: boolean; list_version: number | null; status: string | null; source: string | null; finding: string;
}

export interface Reconciliation {
  offering: ClassInfo;
  figures: { registered: number; eligible: number; listed: number; present: number; absent: number; manual: number; pending: number };
  findings: Record<string, number>;
  rows: ReconRow[];
}

export const STATUSES: [string, string][] = [
  ["PRESENT", "Present"], ["ABSENT", "Absent"], ["LATE", "Late"], ["EXCUSED", "Excused"], ["INVALID_ATTENDANCE", "Invalid attendance"],
];

export const STATUS_WORD: Record<string, string> = { ...Object.fromEntries(STATUSES), MANUAL_PRESENT: "Manual present" };

export const FINDINGS: [string, string, "ok" | "warn" | "bad" | "grey", string][] = [
  ["OK", "In order", "ok", "registered, listed and marked"],
  ["NOT_MARKED", "Not marked", "grey", "on the list, no attendance recorded yet"],
  ["REGISTERED_NOT_ON_LIST", "Registered, not on the sheet", "warn", "registered after the sheet was issued — a new version lists them"],
  ["ON_LIST_NOT_REGISTERED", "On the sheet, no longer registered", "warn", "the course was dropped or the registration withdrawn since"],
  ["PRESENT_NOT_REGISTERED", "Present, not registered", "bad", "marked present but no longer registered for the course nor on the latest sheet"],
  ["PRESENT_NOT_ELIGIBLE", "Present without card or permit", "bad", "sat without the examination card, or the GST & EPS permit for a general course"],
  ["MANUAL_NOT_REGISTERED", "Handwritten, not registered", "bad", "wrote their name on the sheet but has no registration for the course"],
];

export const FINDING_WORD: Record<string, string> = Object.fromEntries(FINDINGS.map(([k, w]) => [k, w]));

export const ELIGIBILITY_WORD: Record<string, string> = { CARD: "Card", NO_CARD: "NO CARD", PERMIT: "Permit", NO_PERMIT: "NO PERMIT" };

/** "09:00" from a time as the database writes it */
export const clock = (t: string | null | undefined) => (t ? t.slice(0, 5) : "");

/** "Monday, 9 November 2026" */
export const examDay = (d: string | null | undefined) => {
  if (!d) return "";
  const x = new Date(`${d.slice(0, 10)}T12:00:00Z`);
  return Number.isNaN(x.getTime()) ? d : x.toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long", year: "numeric", timeZone: "UTC" });
};

/** the scope a sheet lists, in words */
export function scopeWords(s: { faculty: string | null; department: string | null; programme: string | null }): string {
  if (s.programme) return s.programme;
  if (s.department) return `Department of ${s.department}`;
  if (s.faculty) return `Faculty of ${s.faculty}`.replace(/^Faculty of Faculty of /, "Faculty of ");
  return "The whole class";
}

/** the marks changed on screen: only a status chosen that differs from what is recorded, or a reason added */
export function changedMarks(rows: MarkRow[], chosen: Record<string, string>, reasons: Record<string, string>): { student: string; status: string; reason?: string }[] {
  const out: { student: string; status: string; reason?: string }[] = [];
  for (const r of rows) {
    const st = chosen[r.student_id];
    if (!st) continue;
    const why = (reasons[r.student_id] ?? "").trim();
    if (st === r.attendance && why === (r.reason ?? "")) continue;
    out.push(why ? { student: r.student_id, status: st, reason: why } : { student: r.student_id, status: st });
  }
  return out;
}
