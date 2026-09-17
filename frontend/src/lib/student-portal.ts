/**
 * The student's side of the portal as the API states it (V026): the record,
 * the fees, the registration, the results. Nothing here is typed by the
 * student except the contact details and the choice of courses.
 */

export interface Charge { id: string; item: string; amount: number; ord: number }
export interface PaymentRef {
  id: string; session: string; reference: string; purpose: string; amount: number; generated_at: string; expires_at: string;
  confirmed_at: string | null; channel: string | null; note: string | null; receipt_no: string | null;
}
export interface Fees {
  session: string;
  charges: Charge[];
  due: number;
  paid: number;
  balance: number;
  instalmentsPaid: number;
  paidInFull: boolean;
  hasArrears: boolean;
  clearsRegistration: boolean | null;
  schemeProblem: string | null;
  references: PaymentRef[];
  sessions: string[];
  reference?: string;
}
export interface Semester { session: string; semester: number; units: number; gpa: number | null; cgpa: number | null; published_count: number; registered_count: number;
  cur: number; cue: number; wgp: number; tcr: number; tce: number; twgp: number; lcgpa: number | null }
export interface Carryover { course_code: string; title: string; units: number; failed_in: string }
export interface Entry { offeringId: string; courseCode: string; title: string; units: number; entryType: string; status: string; kind?: string; lecturer?: string | null; courseSemester?: number }
export interface Registration { id: string; status: string; level: number; submitted_at: string | null; approved_at: string | null; units: number; entries: Entry[] }
export interface MenuItem {
  offering_id: string; course_code: string; title: string; units: number; kind: string; basis: string; owner_dept: string;
  carryover: boolean; failed_in: string | null; lecturer: string | null;
}
export interface RegistrationView {
  session: string; semester: number; level: number; limit: { min_units: number; max_units: number };
  menu: MenuItem[]; registration: Registration | null; fees: Fees; status: string; addDropOpen?: boolean;
  /** whether THIS semester's school fees are cleared (registration for it is gated on that) */
  clears?: boolean;
  /** the highest open semester of the session; the student may also register any earlier one */
  openSemester?: number;
  /** the semesters of this session already registered (submitted or beyond) */
  registeredSemesters?: number[];
  /** true when this is the SIWES / industrial-training semester (only the SIWES course, no carryovers) */
  siwes?: boolean;
}
export interface ResultRow {
  session: string; semester: number; course_code: string; title: string; units: number; entry_type: string; stage: string;
  published: boolean; published_at: string | null; senate_minute: string | null;
  ca: number | null; exam: number | null; total: number | null; grade: string | null; points: number | null; outcome: string | null;
}
export interface Results {
  name: string; matricNo: string; programme: string; level: number; rows: ResultRow[]; semesters: Semester[];
  cgpa: number | null; standing: string | null; carryovers: Carryover[]; clearsResults: boolean | null;
}
export interface Notice { id: string; channel: string; recipient: string; subject: string; body: string; created_at: string; state: string; sent_at: string | null }
export interface Me {
  id: string; name: string; surname: string; otherNames: string; matricNo: string | null; admissionNo: string | null;
  programmeCode: string; programme: string; faculty: string; department: string; entryMode: string; entrySession: string;
  entryLevel: number; level: number; status: string; curriculumVersion: string | null; session: string;
  contact: { phone: string | null; email: string | null; address: string | null; reach_email: string | null; reach_phone: string | null };
  passportDocumentId: string | null;
  fees: Fees; gpa: Semester[]; cgpa: number | null; standing: string | null; carryovers: Carryover[];
  registration: Registration | null; notices: Notice[]; graduation?: Graduation | null;
}
export interface ClearanceUnit { unit: string; label: string; state: string; item: string | null; decided_at: string | null; clears_against: string; holds_for: string; office_code: string | null }
export interface Graduation {
  finalist: boolean; final_level: number; session: string | null; audited: boolean; cgpa: number | null; award: string | null; unmet: string | null;
  senate_state: string | null; senate_minute: string | null; class_of_degree: string | null; status: string; cleared: boolean; units_holding: number;
  certificate_no: string | null; certificate_status: string | null; convocation: string | null; printed_on: string | null; collected_on: string | null;
  held_reason: string | null; verification_code: string | null; issued_on: string | null;
  name?: string; matricNo?: string | null; programme?: string; level?: number; clearance?: ClearanceUnit[];
}
export interface Receipt extends PaymentRef { name: string; matricNo: string; programme: string; level: number }

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
export interface DocketPaper { offering_id: string; course_code: string; title: string; units: number; held_on: string | null; starts_at: string | null; ends_at: string | null; venue: string | null; sheet_stage: string | null }
export interface Docket { session: string; clearsExamination: boolean | null; schemeProblem: string | null; examSessions: { id: string; session: string; semester: number; kind: string; exams_from: string; exams_to: string; state: string; papers: DocketPaper[] }[] }
export interface Slot { weekday: number; starts_at: string; ends_at: string; course_code: string; title: string; kind: string; venue: string; lecturer: string | null; carryover: boolean }
export interface AttendanceRow { course_code: string; title: string; attended: number; held: number; rate: number | null }
export interface Timetable { session: string; semester: number; slots: Slot[]; attendance: AttendanceRow[] }
export interface Card { matricNo: string | null; cards: { id: string; card_no: string; issued_at: string; valid_to: string; state: string; ended_at: string | null; ended_reason: string | null }[]; clearsIdCard: boolean | null }
export interface TranscriptRow { id: string; ref: string; destination: string; destination_name: string | null; mode: string; copies: number; requested_at: string; paid_at: string | null; stage: string; produced_at: string | null; released_at: string | null; open_reference: string | null }
export interface Transcripts { fee: number; requests: TranscriptRow[]; ref?: string; reference?: string }

export const WEEKDAY = ["", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];

/** the desks a sheet passes, as the results chain names them, for "where it is" */
export const STAGE_LABEL: Record<string, [string, string]> = {
  NO_SHEET: ["No sheet yet", "The examination session has not been opened for this offering"],
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
