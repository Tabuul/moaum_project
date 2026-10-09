/**
 * CCE — the Centre for Continuing Education (V379): the shapes the CCE desk and the CCE application read, the words they show,
 * and the headings JAMB's CCE list is read by. A CCE student is an ordinary student on a part-time route with a session of its
 * own; every rule here is the server's, and these pages show what it returns.
 */
export { jcall as ccall, fileBase64, readSheet, naira, when, WEEKDAYS } from "./jupeb";

export type Kind = "grey" | "info" | "ok" | "bad" | "warn";

/** the CCE desk's screens, one a path under /cce (the server page checks the path against them) */
export const CCE_TABS = ["dashboard", "upload", "imports", "candidates", "applications", "processing", "admission-list", "students", "programmes", "session",
  "reports", "history", "fees", "calendar", "classes", "timetable", "registrations", "attendance", "school-fees"] as const;
export type CceTab = (typeof CCE_TABS)[number];

export interface Mapping {
  route: string; name: string; study_mode: string; centre: string | null; entry_level: number; default_duration_years: number;
  undergraduate_session: string | null; route_session: string | null; route_session_state: string | null; session_offset: number;
  overridden: boolean; override_reason: string | null; relationship: string | null; effective_from: string | null;
  configured_by_name: string | null; configured_office: string | null; configured_at: string | null;
}
export interface SessionRow { session: string; state: string; listed?: number }
export interface FeeRule { stated: boolean; application_fee: number; portal_charge: number; acceptance_fee: number; carried_from: string | null }
export interface Overview {
  session: string; office: string | null; mapping: Mapping; sessions: SessionRow[]; stats: Record<string, number>;
  window: { state: string; opens_at: string | null; closes_at: string | null }; fees: FeeRule | null; programmesOffered: number;
  byProgramme: { programme_code: string; programme: string; faculty: string | null; listed: number; applied: number; admitted: number; students: number }[];
}
export interface Paged<T> { session: string; total: number; page: number; size: number; rows: T[] }
export interface Batch {
  id: string; session: string; filename: string; rows_read: number; counts: Record<string, number>; state: "PREVIEW" | "COMMITTED" | "DISCARDED";
  uploaded_at: string; uploaded_office: string; uploaded_by_name: string | null; committed_at: string | null; committed_by_name: string | null;
  applied: Record<string, number> | null; discarded_at: string | null; discard_reason: string | null;
}
export interface BatchRow {
  row_no: number; jamb_reg_no: string | null; surname: string | null; first_name: string | null; middle_name: string | null; date_of_birth: string | null;
  sex: string | null; phone: string | null; email: string | null; state_of_origin: string | null; lga: string | null; programme_code: string | null;
  programme: string | null; classification: string; issues: string[]; notes: string[]; changes: Record<string, { from: string | null; to: string | null }> | null;
}
export interface CandidateRow {
  id: string; jamb_reg_no: string; name: string; date_of_birth: string; sex: string | null; phone: string | null; email: string | null;
  state_of_origin: string | null; lga: string | null; programme_code: string; programme: string; department: string | null; faculty: string | null;
  status: string; standing_reason: string | null; application_id: string | null; application_no: string | null; review_state: string | null;
  admission_no: string | null; matric_no: string | null; created_at: string;
}
export interface AppRow {
  id: string; application_no: string; jamb_reg_no: string; name: string; sex: string | null; date_of_birth: string; programme_code: string; programme: string;
  department: string | null; faculty: string | null; state: string; submitted_at: string | null; review_started_at: string | null; recommended_at: string | null;
  decided_at: string | null; decided_office: string | null; published_at: string | null; request_note: string | null; decision_note: string | null;
  fee_confirmed_at: string | null; accepted_at: string | null; email: string; phone: string; admission_no: string | null; matric_no: string | null;
  student_id: string | null; created_at: string; documents_pending: number;
}
export interface Olevel { sitting: number; exam_body: string; exam_number: string; exam_year: number; subject: string; grade: string }
export interface DeskDoc {
  id: string; kind: string; filename: string; content_type: string; bytes: number; uploaded_at: string; status: "PENDING" | "ACCEPTED" | "REJECTED";
  reviewed_at: string | null; review_note: string | null; reviewed_by_name: string | null;
}
export interface AppDetail extends AppRow {
  listed: { session: string; jamb_reg_no: string; surname: string; first_name: string; middle_name: string | null; date_of_birth: string; sex: string | null; phone: string | null;
            email: string | null; state_of_origin: string | null; lga: string | null; nationality: string | null; olevel_note: string | null; remarks: string | null;
            extra: string | null; standing: string; list_file: string; listed_at: string | null };
  biodata: { field: string; value: string }[]; olevel: Olevel[]; compulsory: { subject: string; credit: boolean }[]; documents: DeskDoc[];
  review: { state: string; programme_confirmed_at: string | null; submitted_at: string | null; review_started_at: string | null; request_note: string | null;
            requested_at: string | null; recommended_at: string | null; recommendation_note: string | null; decided_at: string | null; decided_office: string | null;
            decision_note: string | null; published_at: string | null; recommended_by: string | null; recommended_by_name: string | null; decided_by_name: string | null };
  events: { at: string; action: string; from_state: string | null; to_state: string | null; note: string | null; office: string | null; actor_name: string | null }[];
  problems: { step: string; field: string; message: string }[];
  payments: { kind: string; reference: string; amount: number; generated_at: string; confirmed_at: string | null; channel: string | null; receipt_no: string | null }[];
  me: string | null;
}
export interface StudentRow {
  id: string; matric_no: string | null; admission_no: string | null; jamb_reg_no: string | null; name: string; sex: string | null; programme_code: string; programme: string;
  department: string | null; faculty: string | null; entry_session: string; current_level: number; status: string; study_mode: string; duration_years: number | null;
  expected_completion: string | null;
}

/** what an uploaded row would do */
export const CLASS_LABEL: Record<string, [string, Kind]> = {
  NEW: ["New", "ok"], EXISTING: ["Unchanged", "grey"], UPDATED: ["Updated", "info"], DUPLICATE: ["Duplicate in the file", "warn"],
  REQUIRES_REVIEW: ["Requires review", "warn"], INVALID: ["Invalid", "bad"],
};
export const CLASSES = ["NEW", "UPDATED", "EXISTING", "DUPLICATE", "REQUIRES_REVIEW", "INVALID"];

/** where a listed person stands */
export const STATUS_LABEL: Record<string, [string, Kind]> = {
  IMPORTED: ["Imported — programme not admitting", "grey"], ELIGIBLE_TO_APPLY: ["Eligible to apply", "info"], APPLICATION_STARTED: ["Application started", "info"],
  APPLICATION_SUBMITTED: ["Application submitted", "info"], UNDER_REVIEW: ["Under review", "warn"], ADMITTED: ["Admitted", "ok"],
  NOT_ADMITTED: ["Not admitted", "bad"], REJECTED: ["Rejected", "bad"], WITHDRAWN: ["Withdrawn from the list", "grey"],
};
export const STATUSES = ["ELIGIBLE_TO_APPLY", "IMPORTED", "APPLICATION_STARTED", "APPLICATION_SUBMITTED", "UNDER_REVIEW", "ADMITTED", "NOT_ADMITTED", "REJECTED", "WITHDRAWN"];

/** the Centre's review of an application */
export const REVIEW_LABEL: Record<string, [string, Kind]> = {
  DRAFT: ["Draft (the applicant's)", "grey"], SUBMITTED: ["Submitted", "info"], UNDER_REVIEW: ["Under review", "warn"],
  DOCUMENTS_PENDING: ["Documents asked for", "warn"], VERIFICATION_REQUIRED: ["Verification asked for", "warn"], RECOMMENDED: ["Recommended", "info"],
  APPROVED: ["Approved — awaiting publication", "ok"], ADMITTED: ["Admitted (published)", "ok"], NOT_ADMITTED: ["Not admitted", "bad"], REJECTED: ["Rejected", "bad"],
};
export const REVIEW_STATES = ["SUBMITTED", "UNDER_REVIEW", "DOCUMENTS_PENDING", "VERIFICATION_REQUIRED", "RECOMMENDED", "APPROVED", "ADMITTED", "NOT_ADMITTED", "REJECTED", "DRAFT"];
/** the queue of admission processing: what the Centre and the Academic Office still have to act on */
export const PROCESSING_STATES = ["SUBMITTED", "UNDER_REVIEW", "DOCUMENTS_PENDING", "VERIFICATION_REQUIRED", "RECOMMENDED", "APPROVED"];

export const ACTION_LABEL: Record<string, string> = {
  REGISTERED: "Account opened from the CCE list", SUBMITTED: "Submitted", PROVIDED: "Sent back with what was asked", START: "Taken up for review",
  REQUEST_DOCUMENTS: "Documents asked for", REQUIRE_VERIFICATION: "Verification asked for", RESUME: "Taken back under review", RECOMMEND: "Recommended",
  APPROVE: "Approved", NOT_ADMIT: "Not admitted", REJECT: "Rejected", REOPEN: "Reopened", PUBLISHED: "Published", DOCUMENT_ACCEPTED: "Document accepted",
  DOCUMENT_REJECTED: "Document rejected",
};

export const DOC_LABEL: Record<string, string> = {
  PASSPORT: "Passport photograph", OLEVEL_STATEMENT: "O'Level result (first sitting)", OLEVEL_STATEMENT_2: "O'Level result (second sitting)",
  BIRTH_CERT: "Birth certificate or declaration of age", LGA_ID: "Local government identification", OTHER: "Other document",
};

/** the CCE list's columns: the template's heading, the field it fills, whether a row needs it, an example */
export const TEMPLATE_COLUMNS: [string, string, boolean, string][] = [
  ["S/N", "sn", false, "1"],
  ["JAMB Number", "jamb_reg_no", true, "202512345678CC"],
  ["Surname", "surname", true, "IORLIAM"],
  ["First Name", "first_name", true, "Doosuur"],
  ["Middle Name", "middle_name", false, "Mimi"],
  ["Date of Birth", "date_of_birth", true, "1990-04-17"],
  ["Gender", "sex", false, "F"],
  ["Phone Number", "phone", false, "08031234567"],
  ["Email", "email", false, "doosuur@example.com"],
  ["State of Origin", "state_of_origin", false, "Benue"],
  ["LGA", "lga", false, "Gboko"],
  ["Nationality", "nationality", false, "Nigeria"],
  ["Programme", "programme", false, "B.Sc. COMPUTER SCIENCE"],
  ["Programme Code", "programme_code", true, "C00023"],
  ["Department", "department", false, "Mathematics and Computer Science"],
  ["Faculty", "faculty", false, "Science"],
  ["O'Level Information", "olevel", false, "WAEC 2008: Eng C5, Maths C4, Bio B3, Chem C6, Phy C5"],
  ["O'Level Sitting", "olevel_sitting", false, "1"],
  ["Admission Session", "admission_session", false, "2025/2026"],
  ["Study Mode", "study_mode", false, "PART_TIME"],
  ["Admission Route", "admission_route", false, "CCE"],
  ["Source", "source", false, "JAMB"],
  ["Remarks", "remarks", false, ""],
];

/** the headings a CCE list may carry, as readSheet normalises them (lower case, words), to the field each fills */
export const LIST_ALIASES: Record<string, string> = (() => {
  const a: Record<string, string> = {};
  const add = (key: string, ...names: string[]) => names.forEach((n) => { a[n] = key; });
  add("sn", "s n", "sn", "s no", "serial", "serial number", "no");
  add("jamb_reg_no", "jamb number", "jamb no", "jamb reg no", "jamb registration number", "reg no", "registration number", "jamb", "jamb reference", "jamb ref");
  add("surname", "surname", "last name", "family name");
  add("first_name", "first name", "firstname", "given name");
  add("middle_name", "middle name", "middlename");
  add("other_names", "other names", "othernames", "other name");
  add("date_of_birth", "date of birth", "dob", "birth date", "d o b");
  add("sex", "gender", "sex");
  add("phone", "phone number", "phone", "mobile", "gsm", "telephone", "phone no");
  add("email", "email", "e mail", "email address");
  add("state_of_origin", "state of origin", "state");
  add("lga", "lga", "local government", "local government area");
  add("nationality", "nationality", "country");
  add("programme", "programme", "program", "course", "programme name", "course name");
  add("programme_code", "programme code", "program code", "course code", "code");
  add("department", "department", "dept");
  add("faculty", "faculty");
  add("olevel", "o level information", "o level", "olevel", "o level result", "o level results");
  add("olevel_sitting", "o level sitting", "sitting", "olevel sitting", "sittings");
  add("passport", "passport");
  add("admission_session", "admission session", "session");
  add("study_mode", "study mode", "mode", "mode of study");
  add("admission_route", "admission route", "route", "admission type");
  add("source", "source");
  add("remarks", "remarks", "remark", "comment", "comments");
  return a;
})();

/** the SHA-256 of an uploaded file, as hex: the same file committed twice is refused */
export async function sha256Hex(buf: ArrayBuffer): Promise<string> {
  const d = new Uint8Array(await crypto.subtle.digest("SHA-256", buf));
  return Array.from(d, (b) => b.toString(16).padStart(2, "0")).join("");
}

export const day = (iso: string | null | undefined) =>
  iso ? new Date(iso.length === 10 ? `${iso}T12:00:00Z` : iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric", timeZone: "Africa/Lagos" }) : "—";

export function labelOf(map: Record<string, [string, Kind]>, key: string | null | undefined): [string, Kind] {
  return key ? map[key] ?? [key.replace(/_/g, " ").toLowerCase(), "grey"] : ["—", "grey"];
}

/* ── phase 2 (V380): the CCE session in operation ─────────────────────────────────────────────────────────────── */

export interface CalendarSemester {
  number: number; id: string | null; state: "NOT_SET" | "NOT_YET_OPEN" | "OPEN" | "CLOSED"; lectures_from: string | null; lectures_to: string | null;
  registration_opens: string | null; registration_closes: string | null; late_registration_closes: string | null; exams_from: string | null; exams_to: string | null;
  note: string | null; updated_at: string | null; updated_office: string | null; updated_by_name: string | null; classes: number; registered: number;
  window_configured: boolean; window_state: string; window_closes: string | null; window_reason: string | null;
}
export interface CalendarView {
  session: string; cceSession: string; undergraduateSession: string | null; sessions: string[]; semesters: CalendarSemester[];
  feesWindow: { configured: boolean; state: string; closes_at: string | null; reason: string | null };
}
export interface Slot { id: string; weekday: number; starts_at: string; ends_at: string; venue: string; kind: string }
export interface CceClass {
  id: string; course_code: string; title: string; units: number; level: number; semester: number; kind: string; dept_code: string; department: string | null;
  faculty: string | null; lecturer_id: string | null; lecturer: string | null; second_examiner_id: string | null; second_examiner: string | null;
  programmes: string | null; registered: number; drafted: number; slots: Slot[]; registers: number;
}
export interface ClassesView { session: string; semester: number | null; cceSession: string; sessions: string[]; programmesOnRoute: number; classes: CceClass[]; opened?: number }
export interface TimetableSlot extends Slot { offering_id: string; course_code: string; title: string; units: number; level: number; dept_code: string; department: string | null; faculty: string | null; lecturer: string | null; programmes: string | null }
export interface Clash { kind: "LECTURER" | "VENUE" | "STUDENTS" | "FULL_TIME_VENUE"; weekday: number; starts_at: string; ends_at: string; first_course: string; second_course: string; detail: string }
export interface Period { id: string; label: string; starts_at: string; ends_at: string; active: boolean; ord: number }
export interface TimetableView { session: string; semester: number; sessions: string[]; slots: TimetableSlot[]; unscheduled: { id: string; course_code: string; title: string; level: number }[]; clashes: Clash[]; periods: Period[] }
export interface RegistrationRow {
  id: string; number: string; name: string; programme_code: string; programme: string; level: number; student_status: string; registration_id: string | null;
  registration: string; submitted_at: string | null; approved_at: string | null; units: number; fees_stated: boolean; fees_cleared: boolean;
}
export interface RegistrationsView { session: string; semester: number; sessions: string[]; counts: Record<string, number>; gate: string | null; rows: RegistrationRow[] }
export interface AttendanceRow {
  student_id: string; number: string; name: string; programme_code: string; programme: string; level: number; faculty: string | null; department: string | null;
  offering_id: string; course_code: string; title: string; semester: number; total: number; present: number; absent: number; late: number; excused: number;
  rate: number | null; min_percent: number | null; verdict: string | null;
}
export interface AttendanceView {
  session: string; semester: number | null; sessions: string[];
  policy: { session: string; min_percent: number | null; warn_band: number | null; min_classes: number; show_students: boolean; updated_at: string } | null;
  rows: AttendanceRow[];
  classes: { id: string; course_code: string; title: string; semester: number; lecturer: string | null; registers: number; locked: number; last_held: string | null; attended: number; counted: number }[];
  faculties: { code: string; name: string }[]; programmes: { code: string; name: string; dept_code: string; faculty_code: string }[];
}
export interface SchoolFeesView {
  session: string; sessions: string[];
  lines: { id: string; item: string; amount: number; level: number | null; semester: number | null; kind: string; indigene: string | null; spillover: boolean; faculty: string | null; programme: string | null }[];
  fullTimeLines: number; window: { configured: boolean; state: string; phase: string; closes_at: string | null; late_until: string | null; reason: string | null };
  students: { students: number; stated: number; paid_in_full: number; part_paid: number; unpaid: number; due: number; paid: number; balance: number };
  payments: { payer: "STUDENT" | "APPLICANT"; purpose: string; payments: number; amount: number }[];
}

/** a registration's place, in words */
export const REG_LABEL: Record<string, [string, Kind]> = {
  NONE: ["Not registered", "grey"], DRAFT: ["Drafting", "info"], RETURNED: ["Returned to the student", "warn"], SUBMITTED: ["Submitted — with the Head of Department", "warn"],
  APPROVED: ["Approved", "ok"], LOCKED: ["Approved (locked)", "ok"],
};
export const CAL_LABEL: Record<string, [string, Kind]> = { NOT_SET: ["Not set", "grey"], NOT_YET_OPEN: ["Not yet open", "info"], OPEN: ["Open", "ok"], CLOSED: ["Closed", "bad"] };
export const ATT_LABEL: Record<string, [string, Kind]> = { PRESENT: ["Present", "ok"], LATE: ["Late", "warn"], ABSENT: ["Absent", "bad"], EXCUSED: ["Excused", "info"] };
export const VERDICT_LABEL: Record<string, [string, Kind]> = { ELIGIBLE: ["Meets the minimum", "ok"], NOT_ELIGIBLE: ["Below the minimum", "bad"], REQUIRES_REVIEW: ["Review: all excused", "warn"] };
export const CLASH_LABEL: Record<string, string> = { LECTURER: "Lecturer in two classes", VENUE: "Venue in two classes", STUDENTS: "Students of one programme and level in two classes", FULL_TIME_VENUE: "Venue on the full-time timetable" };
export const semesterWord = (n: number | null | undefined) => (n === 1 ? "First semester" : n === 2 ? "Second semester" : n === 3 ? "Third semester" : "Every semester");
