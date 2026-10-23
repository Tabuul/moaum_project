/** V642: the Academic Office student edit page — what GET /api/v1/student/students/{id}/edit answers, and the words the page uses */

export type Permission =
  | "EDIT_STUDENT_ACADEMIC_RECORD" | "EDIT_STUDENT_BIODATA" | "EDIT_STUDENT_ADMISSION" | "EDIT_STUDENT_ACADEMIC_PLACEMENT"
  | "EDIT_STUDENT_PROGRAMME" | "EDIT_STUDENT_DEPARTMENT" | "EDIT_STUDENT_FACULTY" | "EDIT_STUDENT_LEVEL" | "EDIT_STUDENT_SESSION"
  | "EDIT_STUDENT_STATUS" | "EDIT_STUDENT_MATRICULATION" | "EDIT_STUDENT_CLASSIFICATION" | "EDIT_STUDENT_ENROLLMENT"
  | "EDIT_STUDENT_ACADEMIC_HISTORY" | "EDIT_STUDENT_GRADUATION_STATUS" | "EDIT_STUDENT_CARRYOVER" | "EDIT_STUDENT_SPILLOVER"
  | "EDIT_STUDENT_REGISTRATION" | "OVERRIDE_STUDENT_REGISTRATION" | "VIEW_STUDENT_EDIT_HISTORY";

export interface EditStudent {
  id: string; person_id: string | null; surname: string; other_names: string | null; sex: string | null; date_of_birth: string | null;
  matric_no: string | null; matriculated_at: string | null; jamb_reg_no: string | null; admission_no: string | null;
  programme_code: string; programme: string | null; programme_category: string | null; final_level: number | null;
  dept_code: string | null; department: string | null; faculty_code: string | null; faculty: string | null;
  entry_mode: string | null; entry_session: string | null; entry_level: number | null; current_level: number; status: string;
  study_mode: string | null; centre_code: string | null; centre: string | null; curriculum_track: string | null; curriculum_version: string | null;
  programme_type: string | null; programme_type_label: string | null; admission_route: string | null; effective_study_mode: string | null;
  classification_status: string | null; application_no: string | null; admission_list_session: string | null; admitted_programme: string | null;
  admission_status: string | null; admitted_on: string | null; matriculation_run: string | null;
}

export interface Position {
  jamb_year: number | null; matric_year: number | null; entry_session: string | null; effective_cohort: string | null; current_session: string | null;
  current_level: number | null; computed_level: number | null; final_level: number | null; duration_years: number | null; expected_completion: string | null;
  spillover_years: number | null; spillover_state: string | null; graduation_state: string | null; graduation_session: string | null;
  existing_status: string | null; classification: string | null; proposed_status: string | null; rule: string | null; confidence: string | null;
  issues: unknown; last_session: string | null; max_spillover: number | null;
}

export interface LevelOptions {
  levels: number[]; status: string; nextLevel: number | null; entryLevel: number; finalLevel: number; otherLevels: number[]; currentLevel: number;
  postgraduate: boolean; correctRefusal: string | null; progressRefusal: string | null; currentSession: string | null; spilloverState: string | null;
  spilloverChoices?: { year: number; completion: string }[];
}

export interface EditPage {
  student: EditStudent;
  version: string;
  permissions: Permission[];
  contact: { phone: string | null; email: string | null; address: string | null } | null;
  enrolments: { id: string; programme: string | null; programme_type: string | null; status: string; current_level: number; entry_session: string | null; matric_no: string | null }[];
  session: string;
  semester: number;
  position: Position | null;
  levelOptions: LevelOptions;
  carryovers: { course_code: string; title: string; units: number; failed_in: string }[];
  registrations: { session: string; semester: number; level: number; status: string; units: number; courses: number }[];
  statusHistory: { from_status: string | null; to_status: string; instrument: string; effective_on: string; reason: string | null }[];
  programmeHistory: { at: string | null; session: string | null; kind: string; programme_code: string; programme: string; level: number | null; from_programme: string | null; reference: string | null }[];
  finance: Record<string, unknown> | null;
  lists: {
    sessions: { name: string; state: string }[];
    entryModes: string[];
    studyModes: string[];
    centres: { code: string; name: string }[];
    tracks: string[];
    programmeTypes: { code: string; label: string }[];
    faculties: { code: string; name: string }[];
    departments: { code: string; name: string; faculty_code: string }[];
    programmes: { code: string; name: string; dept_code: string | null; faculty_code: string | null; category: string; final_level: number | null }[];
  };
  statuses: string[];
}

export interface HistoryRow {
  at: string | null; reference: string | null; change_type: string; severity: string; section: string; field: string;
  old_value: string | null; new_value: string | null; reason: string | null; by_name: string | null; office: string | null; source: string;
}

export interface SearchHit {
  id: string; name: string; matric_no: string | null; jamb_reg_no: string | null; admission_no: string | null; programme: string | null;
  current_level: number; status: string; programme_type: string | null; application_no: string | null;
}

/** a code read as words: DIRECT_ENTRY → Direct entry */
export const words = (code: string | null | undefined) => (code ? code.charAt(0) + code.slice(1).toLowerCase().replace(/_/g, " ") : "—");

export const SEVERITY: Record<string, ["ok" | "warn" | "bad" | "grey" | "info", string]> = {
  NORMAL: ["grey", "Normal"], IMPORTANT: ["warn", "Important"], CRITICAL: ["bad", "Critical"],
};

export const FIELD_WORD: Record<string, string> = {
  surname: "Surname", other_names: "Other names", sex: "Sex", date_of_birth: "Date of birth", jamb_reg_no: "JAMB registration number",
  admission_no: "Admission number", entry_session: "Admission session", entry_mode: "Entry mode", entry_level: "Entry level",
  study_mode: "Study mode", centre_code: "Centre", curriculum_track: "Curriculum track", current_level: "Level", status: "Academic status",
  programme: "Programme", programme_type: "Programme type", matric_no: "Matriculation number",
};

/** the year a JAMB registration number was issued (its first four digits), when it carries one */
export const jambYear = (reg: string | null | undefined) => (reg && /^(19|20)\d{2}/.test(reg) ? reg.slice(0, 4) : null);
/** the first year of a session: 2021/2022 → 2021 */
export const sessionYear = (s: string | null | undefined) => (s && /^\d{4}\/\d{4}$/.test(s) ? s.slice(0, 4) : null);

/** a reason worth keeping, as the database judges it (people.student_edit_reason_refused): fifteen characters and three words or more */
export function reasonProblem(reason: string): string | null {
  const r = reason.trim();
  if (r.length < 15) return "Say why in fifteen characters or more.";
  const distinct = new Set(r.toLowerCase().split(/[^a-z0-9]+/).filter((w) => w.length > 1));
  if (distinct.size < 3) return "Say what was wrong and where the right value comes from.";
  if (/^(test|testing|abc|abcd|correction|corrections|update|updated|change|changed|edit|edited|fix|fixed|ok|none|na|nil|asdf|qwerty|xyz)+$/.test(r.replace(/[^A-Za-z]+/g, "").toLowerCase())) {
    return "Say what was wrong and where the right value comes from, not only that it was corrected.";
  }
  return null;
}
