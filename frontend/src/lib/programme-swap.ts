/** Programme swap (V578): a migrated student's current programme, department, faculty and level corrected by an office, the old
 *  placement kept. The shapes /api/v1/programme-swaps returns, the words its codes are shown in, and the rows the report takes. */

export type SwapStatus = "PENDING_APPROVAL" | "COMPLETED" | "REJECTED" | "CANCELLED" | "FAILED";
export type SwapKind = "LEGACY_MIGRATION_CORRECTION" | "PROGRAMME_CORRECTION" | "ACADEMIC_TRANSFER";
export type Classification = "CONFIRMED" | "POSSIBLE" | "REQUIRES_REVIEW" | "NO_MISMATCH";
export type ReviewStatus = "NOT_REVIEWED" | "UNDER_REVIEW" | "CONFIRMED" | "SWAP_REQUIRED" | "SWAPPED" | "NO_ACTION_REQUIRED" | "REQUIRES_DOCUMENTATION";

export const KIND_WORDS: Record<SwapKind, string> = {
  LEGACY_MIGRATION_CORRECTION: "Legacy migration correction",
  PROGRAMME_CORRECTION: "Programme correction",
  ACADEMIC_TRANSFER: "Academic transfer recorded",
};
export const STATUS_WORDS: Record<SwapStatus, string> = {
  PENDING_APPROVAL: "Pending approval", COMPLETED: "Completed", REJECTED: "Rejected", CANCELLED: "Cancelled", FAILED: "Failed",
};
export const CLASS_WORDS: Record<Classification, string> = {
  CONFIRMED: "Confirmed mismatch", POSSIBLE: "Possible mismatch", REQUIRES_REVIEW: "Requires review", NO_MISMATCH: "No mismatch",
};
export const REVIEW_WORDS: Record<ReviewStatus, string> = {
  NOT_REVIEWED: "Not reviewed", UNDER_REVIEW: "Under review", CONFIRMED: "Confirmed", SWAP_REQUIRED: "Swap required", SWAPPED: "Swapped",
  NO_ACTION_REQUIRED: "No action required", REQUIRES_DOCUMENTATION: "Requires documentation",
};
/** the review statuses an officer sets by hand; the swap sets the other two */
export const REVIEW_CHOICES: ReviewStatus[] = ["UNDER_REVIEW", "CONFIRMED", "REQUIRES_DOCUMENTATION", "NO_ACTION_REQUIRED", "NOT_REVIEWED"];

export interface Mismatch {
  student_id: string; surname: string; other_names: string; matric_no: string | null; jamb_reg_no: string | null; status: string; entry_mode: string | null;
  entry_session: string | null; current_level: number | null; programme_code: string; programme: string; dept_code: string | null; department: string | null;
  faculty_code: string | null; faculty: string | null; matric_segment: string | null; programme_segment: string | null; registration_dept: string | null;
  registration_dept_name: string | null; registration_share: number | string | null; admitted_programme: string | null; admitted_programme_name: string | null;
  classification: Classification; suggested_dept: string | null; suggested_programme: string | null; suggested_programme_name: string | null;
  review_status: ReviewStatus; review_note: string | null; reviewed_at: string | null;
}

export interface Swap {
  id: string; swap_ref: string; student_id: string; student: string; matric_no: string | null; jamb_reg_no: string | null; kind: SwapKind;
  change: "PROGRAMME" | "LEVEL" | "PROGRAMME_AND_LEVEL"; status: SwapStatus;
  from_programme: string; from_programme_name: string | null; from_dept: string | null; from_department: string | null; from_faculty: string | null;
  from_faculty_name: string | null; from_level: number | null;
  to_programme: string; to_programme_name: string | null; to_dept: string | null; to_department: string | null; to_faculty: string | null;
  to_faculty_name: string | null; to_level: number;
  effective_session: string; reason: string; review: { code: string; text: string }[]; batch_id: string | null;
  prepared_by: string | null; prepared_office: string; prepared_at: string; decided_by: string | null; decided_office: string | null; decided_at: string | null;
  decision_note: string | null; executed_at: string | null; failure: string | null; impact: RegistrationImpact | null; evidence: number;
}

export interface RegistrationImpact { registrations: number; registered: number; applicable: number; extra: { code: string; title: string; semester: number }[];
  missingCore: { code: string; title: string; semester: number }[] }

export interface Placement { programme: string; programmeName: string; dept: string | null; department: string | null; faculty: string | null; facultyName: string | null;
  level: number | null; category: string | null; levels?: number[] }

export interface CheckResult {
  ok: boolean; refusals: string[]; warnings: { code: string; text: string }[]; change: string; session: string;
  student: { id: string; name: string; matricNo: string | null; jambRegNo: string | null; admissionNo: string | null; status: string; entryMode: string | null;
    studyMode: string | null; entrySession: string | null };
  from: Placement; to: Placement | null; fees: { session: string; current: number | string; new: number | string } | null; registration: RegistrationImpact | null;
  unchanged: string[];
}

export interface Programme { code: string; name: string; category: string; levels: number[] }
export interface Department { code: string; name: string; programmes: Programme[] }
export interface Faculty { code: string; name: string; departments: Department[] }

/** the refusal's words: the code's text without the code */
export function refusalWords(r: string): string {
  return r.replace(/^[A-Z][A-Z0-9_]{3,60}: /, "");
}

/** what the swap changes, in words: the faculty, the department, the programme, the level — only what differs */
export function changeWords(s: Pick<Swap, "from_programme" | "to_programme" | "from_dept" | "to_dept" | "from_faculty" | "to_faculty" | "from_level" | "to_level">): string {
  const parts: string[] = [];
  if (s.from_faculty !== s.to_faculty) parts.push("faculty");
  if (s.from_dept !== s.to_dept) parts.push("department");
  if (s.from_programme !== s.to_programme) parts.push("programme");
  if (s.from_level !== s.to_level) parts.push(`level ${s.from_level ?? "—"} → ${s.to_level}`);
  return parts.length ? parts.join(", ") : "nothing";
}

/** why a record is flagged, from its signals, in words */
export function signalWords(m: Pick<Mismatch, "matric_segment" | "programme_segment" | "registration_dept" | "registration_dept_name" | "registration_share" | "admitted_programme" | "admitted_programme_name" | "programme_code" | "dept_code">): string[] {
  const out: string[] = [];
  if (m.matric_segment && m.programme_segment && m.matric_segment !== m.programme_segment) {
    out.push(`Matriculation number names ${m.matric_segment}; the programme's students carry ${m.programme_segment}`);
  }
  if (m.registration_dept && m.registration_dept !== m.dept_code) {
    const share = m.registration_share == null ? "" : ` (${Math.round(Number(m.registration_share) * 100)}% of the courses)`;
    out.push(`Latest registration is mostly ${m.registration_dept_name ?? m.registration_dept} courses${share}`);
  }
  if (m.admitted_programme && m.admitted_programme !== m.programme_code) {
    out.push(`Admitted to ${m.admitted_programme_name ?? m.admitted_programme}`);
  }
  return out;
}

const day = (v: unknown) => (v ? new Date(String(v)).toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }) : "");

/** the report's columns, S/N first */
export const REPORT_HEADERS = ["S/N", "Student", "Matriculation number", "JAMB number", "Old faculty", "Old department", "Old programme", "Old level",
  "New faculty", "New department", "New programme", "New level", "Effective session", "Change type", "Reason", "Status", "Prepared by", "Approved by", "Date"];

export function reportRows(rows: Swap[]): (string | number)[][] {
  return rows.map((s, i) => [i + 1, s.student, s.matric_no ?? "", s.jamb_reg_no ?? "", s.from_faculty_name ?? s.from_faculty ?? "", s.from_department ?? s.from_dept ?? "",
    s.from_programme_name ?? s.from_programme, s.from_level ?? "", s.to_faculty_name ?? s.to_faculty ?? "", s.to_department ?? s.to_dept ?? "",
    s.to_programme_name ?? s.to_programme, s.to_level, s.effective_session, KIND_WORDS[s.kind] ?? s.kind, s.reason, STATUS_WORDS[s.status] ?? s.status,
    s.prepared_by ?? "", s.status === "COMPLETED" ? s.decided_by ?? "" : "", day(s.executed_at ?? s.decided_at ?? s.prepared_at)]);
}

/** the mismatch list's columns, S/N first */
export const MISMATCH_HEADERS = ["S/N", "Student", "Matriculation number", "JAMB number", "Faculty", "Department", "Programme", "Level", "Classification",
  "Why", "Suggested department", "Suggested programme", "Review", "Note"];

export function mismatchRows(rows: Mismatch[]): (string | number)[][] {
  return rows.map((m, i) => [i + 1, `${m.surname}, ${m.other_names}`, m.matric_no ?? "", m.jamb_reg_no ?? "", m.faculty ?? "", m.department ?? "", m.programme,
    m.current_level ?? "", CLASS_WORDS[m.classification] ?? m.classification, signalWords(m).join("; "), m.suggested_dept ?? "",
    m.suggested_programme_name ?? m.suggested_programme ?? "", REVIEW_WORDS[m.review_status] ?? m.review_status, m.review_note ?? ""]);
}

/** the page's address for a filter set, so a list is a link */
export function swapsHref(tab: string, f: Record<string, string>): string {
  const qs = new URLSearchParams();
  if (tab && tab !== "desk") qs.set("tab", tab);
  for (const [k, v] of Object.entries(f)) if (v) qs.set(k, v);
  const q = qs.toString();
  return `/programme-swap${q ? `?${q}` : ""}`;
}
