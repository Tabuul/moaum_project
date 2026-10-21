/**
 * The student's side of the portal as the API states it (V026): the record,
 * the fees, the registration, the results. Nothing here is typed by the
 * student except the contact details and the choice of courses.
 */

import type { StudentOverpayment } from "@/lib/overpayment";
import type { GstEpsEligibility } from "@/lib/gst";

export interface Charge { id: string; item: string; amount: number; ord: number }
export interface PaymentRef {
  id: string; session: string; reference: string; purpose: string; amount: number; generated_at: string; expires_at: string;
  confirmed_at: string | null; channel: string | null; note: string | null; receipt_no: string | null;
  /** V409: the payment's classification on the one ledger, and the gateway's own reference */
  programme_type?: string | null; programme_type_label?: string | null; purpose_code?: string | null; purpose_label?: string | null;
  source_module?: string | null; responsible_office?: string | null; responsible_office_label?: string | null; ledger_semester?: number | null; gateway_reference?: string | null;
}
/** a portal window's state now (V288): open, scheduled, closed or expired; phase NORMAL or LATE */
export interface PortalWindow { configured: boolean; state: "OPEN" | "SCHEDULED" | "CLOSED" | "EXPIRED"; phase: "NORMAL" | "LATE" | "NONE"; opens_at: string | null; closes_at: string | null; late_until: string | null; late_fee_enabled: boolean; reason: string | null;
  /** V466: the closure message the Director of ICT wrote for school fees payment (null for other windows) */
  message?: string | null }
export interface Fees {
  session: string;
  /** V361: whether the Bursary has stated a school fee for the student this session (a ₦0 line on purpose counts) */
  stated?: boolean;
  /** V451: the open semesters whose school fees are not yet stated for the student, while another semester's are */
  unstatedSemesters?: number[];
  window?: PortalWindow;
  charges: Charge[];
  due: number;
  paid: number;
  balance: number;
  /** still owed toward the first semester (whole-session items included); 0 once first semester is cleared */
  firstSemesterOutstanding: number;
  /** still owed toward the second semester, after the first is met; 0 once the session is cleared */
  secondSemesterOutstanding: number;
  instalmentsPaid: number;
  paidInFull: boolean;
  hasArrears: boolean;
  clearsRegistration: boolean | null;
  /** V616: in spillover — charged a semester's school fees only when a course is registered in it */
  spilloverBySemester?: boolean;
  schemeProblem: string | null;
  references: PaymentRef[];
  sessions: string[];
  reference?: string;
  /** V519: what the Bursary decided for school fees paid beyond a session's charge (carried into the next session, or refunded) */
  overpayments?: StudentOverpayment[];
}
export interface Semester { session: string; semester: number; units: number; gpa: number | null; cgpa: number | null; published_count: number; registered_count: number;
  cur: number; cue: number; wgp: number; tcr: number; tce: number; twgp: number; lcgpa: number | null;
  /** the level the student was at in that semester (V330), not today's */
  level?: number }
export interface Carryover { course_code: string; title: string; units: number; failed_in: string }
export interface Entry { offeringId: string; courseCode: string; title: string; units: number; entryType: string; status: string; kind?: string; basis?: string; lecturer?: string | null; courseSemester?: number;
  /** V504: the category the University orders by (registration.entry_category), what a course the student added beside the
   *  recommended list was added as, and whether the student added it */
  category?: import("./course-order").CourseCategory; addedAs?: string | null; studentAdded?: boolean }
export interface Registration { id: string; status: string; level: number; submitted_at: string | null; approved_at: string | null; units: number; entries: Entry[]; returned_comment?: string | null;
  /** V491: how it was approved — HOD, AUTO (by the rule), or null for an earlier approval */
  approval_mode?: "HOD" | "AUTO" | null }
export interface MenuItem {
  offering_id: string; course_code: string; title: string; units: number; kind: string; basis: string; owner_dept: string;
  carryover: boolean; failed_in: string | null; lecturer: string | null;
  /** a course of an approved deferment, due since the return (V264): fixed on the form like a carry-over, never a failure */
  deferred?: boolean; deferred_from?: string | null;
  /** V314: a GST/EPS course the unpaid GST fee locks, and the reason */
  gstLocked?: boolean; gstGate?: string | null;
  /** V482: the prerequisites not yet passed; locked where the Academic Office enforces prerequisites */
  prerequisitesUnmet?: string; prerequisiteLocked?: boolean;
}
/** GST & EPS (V314): the fee the Bursar stated for the student and whether a confirmed payment covers it */
export interface GstEntitlement {
  required: boolean; stated: boolean; fee: number; covers_eps: boolean; paid: number; entitled: boolean;
  state: "PAID" | "NOT_PAID" | "PENDING" | "NOT_STATED" | "NOT_REQUIRED" | "EXEMPT" | string;
  reference: string | null; receipt_no: string | null; paid_at: string | null; open_reference: string | null; open_amount: number | null; open_expires_at: string | null;
  /** V323: where the payment that entitles the student came from, and the old portal's own reference when it was reconciled */
  source?: "CURRENT_PORTAL" | "LEGACY_PORTAL" | null; channel?: string | null; legacy_reference?: string | null;
  /** V366: whether a GST or an EPS course requires the fee, why, and a payment no course requires (the Bursary reviews it) */
  gst_required?: boolean; eps_required?: boolean; reason?: string | null; gst_reason?: string | null; eps_reason?: string | null; review?: boolean;
}
export interface GstCourseView {
  code: string; title: string; units: number; level: number; semester: number; general_office: "GST" | "EPS" | string; offering_id: string | null;
  registered: boolean; registration_status: string | null; result_stage: string | null;
  /** V366: where the course comes from (the programme's course at the level, a carryover, the registration), whether it is owed this session, and where it stands */
  source?: "COURSE_OFFERING" | "CARRYOVER" | "REGISTERED" | string; counts?: boolean; status?: string; semesters?: string | null;
  failed_in?: string | null; last_grade?: string | null; passed_in?: string | null;
}
/** what /api/v1/me/gst answers (V314) */
export interface GstView {
  session: string; entitlement: GstEntitlement; setting: { required_for_gst_eps: boolean; required_for_all: boolean; covers_eps: boolean };
  /** V366: the student's GST and EPS requirement for the session, with its reasons */
  eligibility?: GstEpsEligibility | null;
  references: { reference: string; receipt_no: string | null; amount: number; session: string; purpose: string; generated_at: string; expires_at: string; confirmed_at: string | null; channel: string | null }[];
  courses: GstCourseView[]; reference?: string;
}
export interface RegistrationView {
  session: string; semester: number; level: number; limit: { min_units: number; max_units: number; curriculum?: string | null; basis?: "CURRICULUM" | "LEVEL" | "CCE" | "SIWES" }; probation?: Probation | null;
  menu: MenuItem[]; registration: Registration | null; fees: Fees; status: string; addDropOpen?: boolean;
  /** V602: a graduated record's register view — why it is closed; the menu and the carry-overs are then empty */
  closed?: { code: string; words: string; remedy: string } | null;
  /** V597: the kind of load the saved registration carries — the minimum binds NORMAL only (see lib/registration-load) */
  loadKind?: import("./registration-load").LoadKind | null;
  /** V615: the cohort engine's spillover state (SPILLOVER_YEAR_1 …): a student in spillover is not held to the minimum */
  spilloverState?: string | null;
  /** V491: how the semester's registration is approved, whether the student may reset it (and why not), what holds it for review */
  approval?: import("./registration-approval").ApprovalRule;
  reset?: import("./registration-approval").ResetState;
  reviewReason?: string | null;
  /** V491: the submission's answer — 'approved' when it was approved on submission */
  result?: unknown;
  /** V402/V413: the code family the student's cohort registers (BSU or MOAU), null while the rule is unstated */
  codeFamily?: "BSU" | "MOAU" | null;
  /** V482: ADVISORY (prerequisites shown) or ENFORCED (the engine refuses a course whose prerequisite is not passed) */
  prerequisiteMode?: "ADVISORY" | "ENFORCED" | string;
  /** V483: a postgraduate student's specialisation ("MON — Monetary Economics"), null when none is set */
  specialisation?: string | null;
  /** V314: the GST fee's word on this student */
  gst?: GstEntitlement;
  /** V287: the semester's door — open, closed, not yet open, or open early to the session's fresh students */
  window?: { state?: string | null; registration_opens?: string | null; registration_closes?: string | null; fresh_registration_from?: string | null; gate: string | null; open: boolean; fresh: boolean; portal?: PortalWindow;
    /** V380: a student of the Centre for Continuing Education: the door is the CCE calendar and the CCE window */
    cce?: boolean;
    /** V389: a postgraduate student: the door is the School's calendar and the postgraduate window */
    pg?: boolean };
  /** whether THIS semester's school fees are cleared (registration for it is gated on that) */
  clears?: boolean;
  /** the highest open semester of the session; the student may also register any earlier one */
  openSemester?: number;
  /** the semesters of this session already registered (submitted or beyond) */
  registeredSemesters?: number[];
  /** true when this is the SIWES / industrial-training semester (only the SIWES course, no carryovers) */
  siwes?: boolean;
  /** V504: the carry-overs as the published results state them, each with its class this semester or the semester it runs in */
  outstanding?: OutstandingCourse[];
  /** V504: the rule on adding courses beside the recommended list */
  flex?: FlexRule;
}
/** V504: a carry-over (a published F or recorded absence not since passed — no result is never one) */
export interface OutstandingCourse {
  course_code: string; title: string; units: number; failed_in: string; course_level: number | null; course_semester: number | null;
  offering_id: string | null; on_registration: boolean; runs_in: string | null;
}
/** V504: whether students add other courses (ON), how wide, and whether a higher level's course may be added (OFF) */
export interface FlexRule { allow_other_courses: boolean; other_scope: "PROGRAMME" | "DEPARTMENT" | "FACULTY" | string; allow_higher_levels: boolean }
/** V504: a course the Add Other Course search found, judged by the engine for the student and semester */
export interface FoundCourse {
  offering_id: string | null; course_code: string; title: string; units: number; kind: string; level: number; course_semester: number;
  dept_code: string | null; department: string | null; faculty_code: string | null;
  category: import("./course-order").CourseCategory | null; added_as: string | null; why: string | null; refusal: string | null;
  on_registration: boolean; recommended: boolean | null;
  /** V512: a GST/EPS course the student could add, held while the GST fee they owe is not paid (the gate's words) */
  gstHeld?: string | null;
}
export interface CourseSearch { session: string; semester: number; page: number; size: number; total: number; results: FoundCourse[];
  /** V507: YOUR_COURSES (no code, title, department or faculty: the student's own courses) or SEARCH (every course) */
  listed: "YOUR_COURSES" | "SEARCH"; flex: FlexRule }
export interface ResultRow {
  session: string; semester: number; course_code: string; title: string; units: number; entry_type: string; stage: string;
  published: boolean; published_at: string | null; senate_minute: string | null;
  ca: number | null; exam: number | null; total: number | null; grade: string | null; points: number | null; outcome: string | null;
  lecturer?: string | null;
  /** the level the student was at in that semester (V330) */
  level?: number;
}
export interface Results {
  name: string; matricNo: string; programme: string; level: number; rows: ResultRow[]; semesters: Semester[];
  cgpa: number | null; standing: string | null; carryovers: Carryover[]; clearsResults: boolean | null;
}
export interface Notice { id: string; channel: string; recipient: string; subject: string; body: string; created_at: string; state: string; sent_at: string | null }
export interface AcademicContext {
  session: string; context: "CURRENT" | "PREPARING" | "NONE" | string; session_state: string | null; current_session: string | null; transitions_on: string | null;
  steps: { admission: boolean; acceptance: boolean; screening: boolean; schoolFees: boolean; account: boolean; courseRegistration: boolean; matriculation: boolean };
  ready: boolean; status: "READY_FOR_RESUMPTION" | "FRESH_STUDENT_PREPARING" | "CURRENT_SESSION" | string;
  /** V379: the route and study mode; for a CCE student the Centre, the CCE session beside undergraduate's, the duration and the expected completion */
  route?: string | null; studyMode?: string | null; centre?: string | null; cceSession?: string | null; undergraduateSession?: string | null;
  durationYears?: number | null; expectedCompletion?: string | null;
}
export interface Me {
  id: string; name: string; surname: string; otherNames: string; matricNo: string | null; admissionNo: string | null;
  programmeCode: string; programme: string; faculty: string; department: string; entryMode: string; entrySession: string;
  entryLevel: number; level: number; status: string; curriculumVersion: string | null; session: string;
  /** V603: the dashboard the student lands on (COLLEGE or UNIVERSITY); V606: whether the College's own student area is theirs (MBBS) */
  dashboard?: string; collegeArea?: boolean;
  /** where the student stands (V331): the cohort that carries them, the expected completion, the spillover — the entry session stays history */
  jambYear?: number | null; effectiveCohort?: string | null; cohortSource?: "ENTRY" | "MERGED" | "OVERRIDE" | string | null; durationYears?: number | null;
  expectedCompletion?: string | null; spilloverState?: string | null; spilloverYears?: number | null; classification?: string | null;
  /** the JAMB number an entrant signs in with until the matriculation number is issued, the sign-in they use now, and where they stand on the admission lifecycle (V282) */
  jambRegNo?: string | null; loginId?: string | null; lifecycle?: string | null;
  contact: { phone: string | null; email: string | null; address: string | null; reach_email: string | null; reach_phone: string | null };
  passportDocumentId: string | null;
  /** whether a passport photo exists in any store (document, or JAMB/attachment) — use with /api/v1/me/passport */
  hasPhoto?: boolean;
  fees: Fees; gpa: Semester[]; cgpa: number | null; standing: string | null; carryovers: Carryover[];
  /** V288: the dashboard's indicators */
  windows?: { schoolFees: PortalWindow; courseRegistration: PortalWindow };
  /** V289: the session the student stands in and why — CURRENT, or PREPARING for an entrant of a session still planned — with the pre-resumption steps */
  academic?: AcademicContext;
  registration: Registration | null; notices: Notice[]; graduation?: Graduation | null;
  /** the standing the record pronounces (V244, V246): probation, or advice to withdraw, by Senate's rule on the latest semester's CGPA */
  probation?: Probation | null;
}
export interface Probation {
  /** V421: NOT_AVAILABLE before any complete published semester — a missing result is never good or bad standing */
  standing: "PROBATION" | "ADVISED_TO_WITHDRAW" | "GOOD" | "NOT_AVAILABLE" | string; cgpa: number | null; pronounced_session: string | null; pronounced_semester: number | null;
  pronounced_level: number | null; probation_max_units: number | null;
  /** V421: the University's probation threshold (a CGPA below it), and the latest ended semester's result status */
  threshold?: number | null;
  result_status?: "NOT_AVAILABLE" | "UNDER_VERIFICATION" | "PROCESSING" | "INCOMPLETE" | "HELD" | "PUBLISHED" | null;
  result_session?: string | null; result_semester?: number | null; result_message?: string | null;
}
export interface ClearanceUnit { unit: string; label: string; state: string; item: string | null; decided_at: string | null; clears_against: string; holds_for: string; office_code: string | null }
export interface Graduation {
  finalist: boolean; final_level: number; session: string | null; audited: boolean; cgpa: number | null; award: string | null; unmet: string | null;
  senate_state: string | null; senate_minute: string | null; class_of_degree: string | null; status: string; cleared: boolean; units_holding: number;
  certificate_no: string | null; certificate_status: string | null; convocation: string | null; printed_on: string | null; collected_on: string | null;
  held_reason: string | null; verification_code: string | null; issued_on: string | null;
  name?: string; matricNo?: string | null; programme?: string; level?: number; clearance?: ClearanceUnit[];
}
export interface Receipt extends PaymentRef { name: string; matricNo: string; programme: string; level: number; term?: string | null; /** V360: signed by the API */ checkCode?: string | null }

/** the semester a fee receipt is for, parsed from its purpose ("… · semester 1") or reference ("…-S1") */
export function receiptSemester(r: { purpose?: string | null; reference?: string | null }): number | null {
  const m = (r.purpose ?? "").match(/semester\s*([123])/i) ?? (r.reference ?? "").match(/-S([123])\b/i);
  return m ? Number(m[1]) : null;
}

/** the semester named in words, or null when there is none (e.g. an acceptance fee) */
export function semesterLabel(n: number | null): string | null {
  return n === 1 ? "First semester" : n === 2 ? "Second semester" : n === 3 ? "Third semester" : null;
}

/** the term a fee receipt covers: a named semester, or "Full session" when a school-fees payment
 *  names no semester (paid for the whole session), else null (an acceptance/application fee). */
export function receiptTerm(r: { purpose?: string | null; reference?: string | null }): string | null {
  const named = semesterLabel(receiptSemester(r));
  if (named) return named;
  return /school\s*fee/i.test(r.purpose ?? "") ? "Full session" : null;
}

/** the purpose with any trailing "· semester N" removed — the semester is shown as its own field */
export function receiptPurpose(purpose: string | null | undefined): string {
  return (purpose ?? "").replace(/\s*[·,-]?\s*semester\s*[0-9]+\s*$/i, "").trim();
}

/* ── the services (V027) ── */
export interface Queryable { sheet_id: string; course_code: string; title: string; session: string; semester: number; published_at: string; window_until: string; ca: number | null; exam: number | null; total: number | null; grade: string | null; outcome: string | null }
export interface ResultQuery { id: string; ref: string; part: string; said: string; routed_dept: string; dept_name: string; raised_at: string; state: string; answer: string | null; answered_at: string | null; course_code: string; title: string }
export interface Queries { queryable: Queryable[]; queries: ResultQuery[] }
export interface DocketPaper { offering_id: string; course_code: string; title: string; units: number; held_on: string | null; starts_at: string | null; ends_at: string | null; venue: string | null; sheet_stage: string | null;
  /** V381: why attendance bars the paper — the Centre's policy, where it says so — or null */
  bar?: string | null }
export interface Docket { session: string; clearsExamination: boolean | null; schemeProblem: string | null; examSessions: { id: string; session: string; semester: number; kind: string; exams_from: string; exams_to: string; state: string; papers: DocketPaper[] }[] }
export interface Slot { weekday: number; starts_at: string; ends_at: string; course_code: string; title: string; kind: string; venue: string; lecturer: string | null; carryover: boolean }
export interface AttendanceRow { course_code: string; title: string; attended: number; held: number; rate: number | null;
  /** V380: the register's own counts, for a CCE student (present, absent, late, excused) against the Centre's minimum, when it set one */
  total?: number; present?: number; absent?: number; late?: number; excused?: number; min_percent?: number | null; verdict?: string | null }
export interface Timetable { session: string; semester: number; slots: Slot[]; attendance: AttendanceRow[];
  /** V380: a CCE student's attendance is the register's; attendanceShown false when the Centre's policy keeps it off the portal */
  register?: boolean; attendanceShown?: boolean }
export interface Card { matricNo: string | null; cards: { id: string; card_no: string; issued_at: string; valid_to: string; state: string; ended_at: string | null; ended_reason: string | null }[]; clearsIdCard: boolean | null }
export interface TranscriptRow { id: string; ref: string; destination: string; destination_name: string | null; mode: string; copies: number; requested_at: string; paid_at: string | null; stage: string; produced_at: string | null; released_at: string | null; open_reference: string | null }
export interface Transcripts { fee: number; requests: TranscriptRow[]; ref?: string; reference?: string }

export const WEEKDAY = ["", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];

/** the desks a sheet passes, as the results chain names them, for "where it is" */
export const STAGE_LABEL: Record<string, [string, string]> = {
  NO_SHEET: ["Scores not Uploaded", "The examination session has not been opened for this offering"],
  /* V421: the course's sheet is published but carries no result for you (a registration the old portal's results did not
     cover, or one added after publication): no result — not a failure, not counted in your CGPA */
  NO_RESULT: ["No result recorded", "Not on the published sheet — your department records it"],
  ENTRY: ["With the lecturer", "Marks being entered"],
  VERIFICATION: ["Verification", "Examinations Officer"],
  DEPT_BOARD: ["Departmental board", "Head of Department"],
  FACULTY_SCRUTINY: ["Faculty scrutiny", "Faculty Examinations Officer"],
  FACULTY_COMPILATION: ["Faculty compilation", "Faculty Officer"],
  FACULTY_BOARD: ["Faculty Board", "Dean"],
  RECORDS: ["Exams & Records", "Validation"],
  SENATE: ["Senate", "Awaiting the minute"],
  PUBLISHED: ["Published", "Under a Senate minute"],
};

export const GRADE_COLOUR: Record<string, string> = { A: "var(--green)", B: "var(--chrome)", C: "var(--chrome)", D: "var(--muted)", E: "var(--muted)", F: "var(--red)" };

export function semesterName(n: number): string {
  return n === 1 ? "First" : n === 2 ? "Second" : "Third";
}

/** the portal-wide way to show a semester to a person: "Semester: First" / "Semester: Second" —
 *  never the bare number. Use this for labels, fields and subtitles. */
export function semesterText(n: number): string {
  return `Semester: ${semesterName(n)}`;
}
