/** V715: postgraduate record management — what /api/v1/pg/records answers, and the words the pages use */

export type PgPermission =
  | "EDIT_PG_RECORD" | "VIEW_PG_APPLICANTS" | "VIEW_PG_STUDENTS" | "EDIT_PG_APPLICANT" | "EDIT_PG_STUDENT" | "EDIT_PG_BIODATA"
  | "EDIT_PG_ADMISSION" | "EDIT_PG_PROGRAMME" | "EDIT_PG_ACADEMIC_PLACEMENT" | "EDIT_PG_STAGE" | "EDIT_PG_STATUS" | "EDIT_PG_DOCUMENTS"
  | "VIEW_PG_CHANGE_HISTORY" | "EXPORT_PG_RECORDS"
  | "EDIT_PG_ADMISSION_DECISION" | "EDIT_PG_MATRICULATION" | "EDIT_PG_FINANCIAL_RECORD" | "EDIT_PG_PUBLISHED_RESULT" | "EDIT_PG_GRADUATION";

export interface RecordRow {
  kind: "APPLICANT" | "STUDENT"; application_id: string | null; student_id: string | null; name: string; application_no: string | null;
  legacy_no: string | null; matric_no: string | null; admission_no: string | null; jamb_reg_no: string | null; email: string | null; phone: string | null;
  programme_code: string; programme: string; dept_code: string | null; department: string | null; faculty_code: string | null; faculty: string | null;
  award: string | null; session: string | null; level: number | null; stage: string | null; status: string; at: string | null;
}

export interface RecordLists {
  sessions: { name: string; state: string }[];
  faculties: { code: string; name: string }[];
  departments: { code: string; name: string; faculty_code: string }[];
  programmes: { code: string; name: string; dept_code: string | null; faculty_code: string | null; award: string | null }[];
  awards: string[];
  applicationStates: string[];
  studentStatuses: string[];
}

export interface SearchAnswer { permissions: PgPermission[]; rows: RecordRow[]; narrowed: boolean; lists: RecordLists }

export interface EditApplication {
  id: string; application_no: string; session: string; state: string; entry_level: number; programme_code: string; programme: string;
  dept_code: string | null; department: string | null; faculty_code: string | null; faculty: string | null; award: string | null; research: boolean;
  specialisation_id: string | null; specialisation: string | null;
  applicant_id: string; surname: string; other_names: string; sex: string | null; date_of_birth: string | null; state_of_origin: string | null;
  lga: string | null; nationality: string | null; contact_address: string | null; email: string; phone: string | null;
  last_signed_in_at: string | null; must_change_password: boolean;
  prior_institution: string | null; prior_award: string | null; prior_class: string | null; prior_cgpa: number | string | null; prior_year: number | null;
  proposal_title: string | null;
  fee_confirmed_at: string | null; submitted_at: string | null; created_at: string | null; dept_decided_at: string | null; dept_note: string | null;
  fac_decided_at: string | null; fac_note: string | null; spgs_decided_at: string | null; spgs_note: string | null; accepted_at: string | null;
  admitted_at: string | null; student_id: string | null; checking_confirmed_at: string | null; acceptance_confirmed_at: string | null;
  return_note: string | null; returned_at: string | null; returned_to: string | null;
  legacy_application_no: string | null; decided_on_old_portal: boolean | null; migrated_at: string | null;
  documents_state: string | null; documents_required: number | null; documents_uploaded: number | null; documents_missing: string[] | null;
}

export interface PriorDegree {
  id?: string; kind: string; institution: string; award: string; field: string | null; class_of_degree: string | null; cgpa: number | string | null; year: number | null;
}

export interface HistoryRow {
  at: string; reference: string | null; change_type: string; severity: string; section: string; field: string; old_value: string | null;
  new_value: string | null; reason: string | null; by_name: string | null; office: string | null; source: string;
}

export interface EditPage {
  application: EditApplication;
  version: string;
  permissions: PgPermission[];
  priorDegrees: PriorDegree[];
  referees: { id: string; name: string; email: string | null; phone: string | null; institution: string | null; position: string | null; submitted_at: string | null; verdict: string | null }[];
  documents: { id: string; kind: string; filename: string; content_type: string; uploaded_at: string }[];
  legacyDocuments: { kind: string; label: string; legacy_ref: string | null; attached_at: string | null }[];
  screeningRequired: boolean;
  screening: { state: string; venue: string | null; scheduled_for: string | null; remarks: string | null; reason: string | null; decided_at: string | null; officer_office: string | null; source: string | null; officer: string | null } | null;
  fees: { kind: string; reference: string; amount: number | string; generated_at: string; expires_at: string | null; confirmed_at: string | null; channel: string | null }[];
  legacyFees: { kind: string; legacy_reference: string; amount: number | string; paid_on: string | null; state: string; decision_note: string | null }[];
  student: { id: string; admission_no: string | null; matric_no: string | null; status: string; current_level: number; entry_session: string | null; programme_code: string; programme: string | null; stage: string | null } | null;
  edits: HistoryRow[];
  lists: RecordLists;
  specialisations: { id: string; code: string; name: string }[];
  priorKinds: string[];
}

export interface RecentRow {
  at: string; reference: string; kind: "APPLICANT" | "STUDENT"; record_id: string; name: string; number: string | null; section: string; field: string;
  old_value: string | null; new_value: string | null; reason: string; severity: string; by_name: string | null; office: string | null;
}

export const words = (code: string | null | undefined) => (code ? code.charAt(0) + code.slice(1).toLowerCase().replace(/_/g, " ") : "—");

export const AWARD_WORD: Record<string, string> = { PHD: "PhD", MPHIL: "MPhil", PGD: "PGD", MSC: "M.Sc.", MA: "M.A.", MED: "M.Ed.", MBA: "MBA", MPA: "MPA", LLM: "LL.M." };
export const awardWord = (a: string | null | undefined) => (a ? AWARD_WORD[a] ?? a : "—");

export const STATE_WORD: Record<string, string> = {
  DRAFT: "Draft", SUBMITTED: "Submitted", RETURNED: "Returned", DEPT_RECOMMENDED: "Department recommended", DEPT_DECLINED: "Department declined",
  FAC_RECOMMENDED: "Faculty recommended", FAC_DECLINED: "Faculty declined", OFFERED: "Offered", NOT_OFFERED: "Not offered", ACCEPTED: "Accepted",
  ADMITTED: "Admitted", ACTIVE: "Active", PROBATION: "Probation", DEFERRED: "Deferred", SUSPENDED: "Suspended", GRADUATED: "Graduated",
  WITHDRAWN: "Withdrawn", DORMANT: "Dormant",
};
export const stateWord = (s: string | null | undefined) => (s ? STATE_WORD[s] ?? words(s) : "—");

export const FIELD_WORD: Record<string, string> = {
  surname: "Surname", other_names: "Other names", sex: "Sex", date_of_birth: "Date of birth", state_of_origin: "State of origin", lga: "Local government area",
  nationality: "Nationality", email: "E-mail address", phone: "Phone number", contact_address: "Contact address", programme_code: "Programme",
  specialisation_id: "Specialisation", session: "Session", prior_institution: "Previous institution", prior_award: "Previous award",
  prior_class: "Class of degree", prior_cgpa: "CGPA", prior_year: "Year of graduation", proposal_title: "Research proposal title", prior_degrees: "Previous degrees",
};
export const fieldWord = (f: string) => FIELD_WORD[f] ?? words(f);

export const PRIOR_KIND_WORD: Record<string, string> = {
  FIRST: "First degree", NCE: "NCE", ND: "National Diploma", HND: "Higher National Diploma", PGD: "Postgraduate Diploma", MASTERS: "Master's", PHD: "PhD", OTHER: "Other",
};

/** the state of the search as the address carries it, so a search is shared and comes back */
export interface Filters { q: string; kind: string; faculty: string; department: string; programme: string; session: string; state: string; award: string }
export const EMPTY_FILTERS: Filters = { q: "", kind: "", faculty: "", department: "", programme: "", session: "", state: "", award: "" };

export function filtersFrom(sp: Record<string, string | string[] | undefined>): Filters {
  const s = (k: keyof Filters) => (typeof sp[k] === "string" ? (sp[k] as string) : "");
  return { q: s("q"), kind: s("kind").toUpperCase(), faculty: s("faculty"), department: s("department"), programme: s("programme"), session: s("session"), state: s("state"), award: s("award") };
}

export function filtersQuery(f: Filters): string {
  const qs = new URLSearchParams();
  (Object.keys(f) as (keyof Filters)[]).forEach((k) => { if (f[k]) qs.set(k, f[k]); });
  return qs.toString();
}

/** where a row is edited: an applicant on the record page, a student on the student edit page (V642) */
export const editHref = (r: RecordRow) => (r.kind === "STUDENT" && r.student_id ? `/students/${r.student_id}/edit` : `/admissions/postgraduate/applications/${r.application_id}/edit`);
export const viewHref = (r: RecordRow) => (r.kind === "STUDENT" && r.student_id ? `/students/${r.student_id}` : `/admissions/postgraduate/applications/${r.application_id}`);
