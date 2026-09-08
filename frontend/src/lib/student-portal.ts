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
export interface Semester { session: string; semester: number; units: number; gpa: number | null; cgpa: number | null; published_count: number; registered_count: number }
export interface Carryover { course_code: string; title: string; units: number; failed_in: string }
export interface Entry { offeringId: string; courseCode: string; title: string; units: number; entryType: string; status: string }
export interface Registration { id: string; status: string; level: number; submitted_at: string | null; approved_at: string | null; units: number; entries: Entry[] }
export interface MenuItem {
  offering_id: string; course_code: string; title: string; units: number; kind: string; basis: string; owner_dept: string;
  carryover: boolean; failed_in: string | null; lecturer: string | null;
}
export interface RegistrationView {
  session: string; semester: number; level: number; limit: { min_units: number; max_units: number };
  menu: MenuItem[]; registration: Registration | null; fees: Fees; status: string;
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
  registration: Registration | null; notices: Notice[];
}
export interface Receipt extends PaymentRef { name: string; matricNo: string; programme: string; level: number }

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
