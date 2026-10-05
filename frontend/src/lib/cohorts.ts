/** Student cohorts (V331): the shapes /api/v1/cohorts returns, and the words the screens use for them. */

export interface CohortRow {
  id: string; surname: string; other_names: string; matric_no: string | null; admission_no: string | null; jamb_reg_no: string | null; sex: string | null;
  programme_code: string; programme: string; dept_code: string; department: string; faculty_code: string; faculty: string;
  jamb_year: number | null; matric_year: number | null; entry_session: string | null; effective_cohort: string | null; cohort_source: string | null;
  entry_level: number | null; final_level: number | null; duration_years: number | null;
  current_session: string | null; current_level: number | null; computed_level: number | null; expected_completion: string | null;
  deferred_sessions: number; elapsed_sessions: number | null; spillover_years: number; spillover_state: string;
  registered_current: boolean; enrolled_current: boolean; last_session: string | null;
  graduation_state: string | null; graduation_session: string | null;
  existing_status: string; classification: string; proposed_status: string; rule: string; confidence: string; issues: string; computed_at: string;
}
export interface CohortList { rows: CohortRow[]; total: number; page: number; size: number }
export interface CohortSummary {
  totals: {
    students: number; current: number; graduated: number; spillover: number; spillover_limit: number; eligible: number; expected_to_complete: number;
    requires_review: number; review: number; historical: number; deferred: number; withdrawn: number; discontinued: number; proposals: number; proposals_validated: number;
    computed_from: string | null; computed_to: string | null; current_session: string | null;
  };
  byClassification: { key: string; n: number }[];
  byCohort: { key: string; jamb_year: number | null; n: number; current: number; graduated: number; spillover: number }[];
  byFaculty: { key: string; n: number; current: number; graduated: number; spillover: number; review: number }[];
  byLevel: { key: number; n: number }[];
  bySpillover: { key: string; n: number }[];
  byIssue: { key: string; n: number }[];
  policy: { max_spillover_years: number; updated_at: string };
}
export interface CohortStudent extends CohortRow {
  statusHistory: { from_status: string; to_status: string; instrument: string | null; effective_on: string; expires_on: string | null; reason: string | null }[];
  enrolments: { session: string; level: number; mode: string; enrolled_at: string }[];
  registrations: { session: string; semester: number; level: number; status: string; submitted_at: string | null; approved_at: string | null }[];
  graduands: { session: string; cgpa: number | null; award: string | null; unmet: string | null; senate_state: string; senate_minute: string | null }[];
  deferments: { reference: string; kind: string; session: string; semester: number | null; state: string; return_session: string | null; return_semester: number | null; extension_semesters: number | null }[];
  programmeChanges: { session: string; from_programme_code: string; from_programme: string; to_programme_code: string; to_programme: string; state: string; decided_at: string | null; kind: string | null }[];
  decisions: { id: string; previous_status: string; proposed_status: string | null; final_status: string; classification: string | null; previous_cohort: string | null; effective_cohort: string | null; rule: string | null; reason: string; officer: string | null; actor_office: string | null; batch_ref: string | null; decided_at: string }[];
  matricHistory: { matric_no: string; issued_at: string; reason: string | null }[];
  outstanding: { course_code: string; title: string; units: number; failed_in: string }[];
  override: { effective_cohort: string; reason: string; set_by: string | null; set_at: string } | null;
  sessions: { name: string; state: string; merged_into: string | null }[];
}
export interface CohortSettings {
  policy: { max_spillover_years: number; updated_at: string; updated_by: string | null };
  sessions: { name: string; state: string; starts_on: string; ends_on: string; merged_into: string | null; merged_reason: string | null; merged_minute: string | null; merged_on: string | null; merged_by: string | null; entrants: number; cohort_size: number }[];
  programmes: { code: string; name: string; category: string | null; archived: boolean | null; faculty: string | null; department: string | null; final_level: number | null; duration_years: number | null; pg_award: string | null; final_level_note: string | null; rule_level: number | null; active_students: number }[];
  awards: { award: string; programmes: number; configured: number; min_years: number | null; max_years: number | null; active_students: number }[];
}

export const CLASS: Record<string, [string, "grey" | "info" | "ok" | "bad" | "warn"]> = {
  ACTIVE: ["Current", "ok"], GRADUATED: ["Graduated", "info"], SPILLOVER: ["Spillover", "warn"], SPILLOVER_LIMIT_REACHED: ["Spillover limit reached", "bad"],
  GRADUATION_ELIGIBLE: ["Graduation eligible", "ok"], REQUIRES_REVIEW: ["Requires review", "bad"], ADMITTED: ["Admitted", "grey"], DEFERRED: ["Deferred", "warn"],
  WITHDRAWN: ["Withdrawn", "grey"], VOLUNTARY_WITHDRAWAL: ["Voluntary withdrawal", "grey"], EXPELLED: ["Expelled", "grey"], DECEASED: ["Deceased", "grey"],
  TRANSFERRED_OUT: ["Transferred out", "grey"], RUSTICATED: ["Rusticated", "grey"], SUSPENDED: ["Suspended", "grey"], DORMANT: ["Dormant", "grey"],
};
export const SPILL: Record<string, string> = { NORMAL: "Within programme", SPILLOVER_YEAR_1: "Spillover year 1", SPILLOVER_YEAR_2: "Spillover year 2", SPILLOVER_YEAR_3: "Spillover year 3", SPILLOVER_LIMIT_REACHED: "Spillover limit reached", NOT_APPLICABLE: "—" };
export const CONF: Record<string, [string, "grey" | "info" | "ok" | "bad" | "warn"]> = { VALIDATED: ["Validated", "ok"], LIKELY: ["Likely", "info"], REVIEW: ["Review", "bad"] };
export const RULE: Record<string, string> = {
  R1: "Award approved by Senate", R2: "The official status stands", R3: "Registered or enrolled in the current session, within the programme's length",
  R3L: "Within the programme's length; not yet registered in the current session", R4: "Beyond the programme's length with the record incomplete",
  R4L: "Beyond the policy's spillover limit", R5: "Audited graduand with nothing unmet, awaiting Senate", R6: "The record is too thin to judge", COHORT: "Cohort corrected on evidence",
};
export const ISSUE: Record<string, string> = {
  MISSING_ENTRY_SESSION: "No admission session on the record", ENTRY_SESSION_INVALID: "Admission session not in the form 2021/2022", ENTRY_SESSION_AHEAD: "Admission session later than the current session", MISSING_MATRIC: "No matriculation number",
  MISSING_JAMB: "No JAMB number", DURATION_NOT_CONFIGURED: "Programme length not configured", DUPLICATE_MATRIC: "Matriculation number shared with another record",
  LEVEL_CONFLICT: "Level on the record differs from the cohort's", NO_CURRENT_REGISTRATION: "No registration in the current session", NO_REGISTRATION_HISTORY: "No registration or enrolment on record at all",
  GRADUATED_WITHOUT_APPROVAL: "Marked graduated without an approved award", APPROVED_NOT_GRADUATED: "Award approved by Senate but still active", DEFERRED_WITHOUT_LIVE_DEFERMENT: "Deferred with no deferment in force",
  SPILLOVER_LIMIT_REACHED: "Beyond the spillover limit", BEYOND_PROGRAMME_LENGTH: "Beyond the programme's length",
};
export const STATUSES = ["ADMITTED", "ACTIVE", "PROBATION", "DEFERRED", "SUSPENDED", "RUSTICATED", "WITHDRAWN", "VOLUNTARY_WITHDRAWAL", "EXPELLED", "TRANSFERRED_OUT", "GRADUATED", "DECEASED", "DORMANT"];
export const classWord = (c: string) => CLASS[c]?.[0] ?? c.charAt(0) + c.slice(1).toLowerCase().replace(/_/g, " ");
export const statusWord = (s: string) => s.charAt(0) + s.slice(1).toLowerCase().replace(/_/g, " ");
export const fullName = (r: { surname: string; other_names: string }) => `${r.surname.toUpperCase()}, ${r.other_names}`;
export const issuesOf = (s: string | null | undefined) => (s ? s.split(",").filter(Boolean) : []);
