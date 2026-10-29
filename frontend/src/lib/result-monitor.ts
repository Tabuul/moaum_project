/**
 * V700: result monitoring for the Director of ICT — the words, the rules and the export rows of the result viewer, the
 * exceptions, the uploads and the corrections (ResultMonitorController). The server decides; this only says it.
 */

/** where a result record stands (assessment.result_state) */
export type ResultState = "AWAITING" | "MISSING" | "ENTRY" | "VERIFICATION" | "APPROVAL" | "PUBLISHED";
export const RESULT_STATES: ResultState[] = ["AWAITING", "ENTRY", "VERIFICATION", "APPROVAL", "PUBLISHED", "MISSING"];

export const STATE_WORD: Record<ResultState, string> = {
  AWAITING: "Result not available",
  MISSING: "Missing on a submitted sheet",
  ENTRY: "Uploaded, not submitted",
  VERIFICATION: "Pending verification",
  APPROVAL: "Pending approval",
  PUBLISHED: "Published",
};

export const STATE_TONE: Record<ResultState, "grey" | "info" | "ok" | "bad" | "warn"> = {
  AWAITING: "grey", MISSING: "bad", ENTRY: "info", VERIFICATION: "warn", APPROVAL: "warn", PUBLISHED: "ok",
};

/** a sheet's stage in words (the chain's desks, Sheets.STAGE_NAME) */
export const STAGE_WORD: Record<string, string> = {
  NO_SHEET: "No sheet yet", ENTRY: "Entry", VERIFICATION: "Verification", DEPT_BOARD: "Departmental Board", FACULTY_SCRUTINY: "Faculty scrutiny",
  FACULTY_COMPILATION: "Faculty compilation", FACULTY_BOARD: "Faculty Board", RECORDS: "Exams & Records", SENATE: "Senate", PUBLISHED: "Published",
};
export const stageWord = (s: string | null | undefined) => (s ? STAGE_WORD[s] ?? s : "—");

export const OUTCOME_WORD: Record<string, string> = {
  GRADED: "Graded", ABSENT: "Absent", WITHHELD: "Withheld", INCOMPLETE: "Incomplete", MALPRACTICE: "Malpractice", EXEMPTED: "Exempted",
};

/** what needs a look (assessment.result_exceptions) */
export type ExceptionKind =
  | "RESULT_WITHOUT_REGISTRATION" | "DUPLICATE_RESULT" | "MISSING_SCORE" | "INVALID_SCORE" | "COURSE_ABOVE_LEVEL"
  | "COURSE_OTHER_SEMESTER" | "COURSE_OUTSIDE_PROGRAMME" | "PASSED_STILL_CARRIED" | "RESULT_HELD_NO_STUDENT";
export const EXCEPTION_KINDS: ExceptionKind[] = [
  "RESULT_WITHOUT_REGISTRATION", "DUPLICATE_RESULT", "MISSING_SCORE", "INVALID_SCORE", "COURSE_ABOVE_LEVEL",
  "COURSE_OTHER_SEMESTER", "COURSE_OUTSIDE_PROGRAMME", "PASSED_STILL_CARRIED", "RESULT_HELD_NO_STUDENT",
];
export const KIND_WORD: Record<ExceptionKind, string> = {
  RESULT_WITHOUT_REGISTRATION: "Result without a registration",
  DUPLICATE_RESULT: "Same course twice",
  MISSING_SCORE: "Missing score",
  INVALID_SCORE: "Invalid score",
  COURSE_ABOVE_LEVEL: "Course above the level",
  COURSE_OTHER_SEMESTER: "Course of the other semester",
  COURSE_OUTSIDE_PROGRAMME: "Course outside the programme",
  PASSED_STILL_CARRIED: "Passed, still a carry-over",
  RESULT_HELD_NO_STUDENT: "Uploaded for an unknown number",
};
export const KIND_NOTE: Record<ExceptionKind, string> = {
  RESULT_WITHOUT_REGISTRATION: "A mark for a course the student has no approved registration of in the session.",
  DUPLICATE_RESULT: "Marks for one course on two classes — its BSU-/MOAU- twin, or a second course under the code.",
  MISSING_SCORE: "A registered student with no mark on a sheet already past entry. Not a fail: the result is not there.",
  INVALID_SCORE: "A mark entered on the portal above the course's CA, or its examination, maximum.",
  COURSE_ABOVE_LEVEL: "A course of a higher level than the registration, with a mark.",
  COURSE_OTHER_SEMESTER: "A course taught in the other semester, with a mark in this one.",
  COURSE_OUTSIDE_PROGRAMME: "A course with a mark the programme neither registered under its structure nor binds, and not taken off its broadsheet.",
  PASSED_STILL_CARRIED: "A carry-over registered for a course already passed on a published result.",
  RESULT_HELD_NO_STUDENT: "An uploaded result held for a matriculation number no student on the portal holds.",
};

/** why a correction is asked for (assessment.correction_request.reason_kind) */
export type ReasonKind =
  | "LECTURER_UPLOAD_ERROR" | "DATA_ENTRY_ERROR" | "INCORRECT_SCORE" | "MISSING_SCORE" | "WRONG_STUDENT" | "WRONG_COURSE"
  | "WRONG_SESSION" | "WRONG_SEMESTER" | "WRONG_PROGRAMME" | "APPROVED_ACADEMIC_CORRECTION" | "MIGRATION_CORRECTION" | "OTHER";
export const REASON_KINDS: ReasonKind[] = [
  "INCORRECT_SCORE", "MISSING_SCORE", "LECTURER_UPLOAD_ERROR", "DATA_ENTRY_ERROR", "WRONG_STUDENT", "WRONG_COURSE", "WRONG_SESSION",
  "WRONG_SEMESTER", "WRONG_PROGRAMME", "APPROVED_ACADEMIC_CORRECTION", "MIGRATION_CORRECTION", "OTHER",
];
export const REASON_WORD: Record<ReasonKind, string> = {
  LECTURER_UPLOAD_ERROR: "Lecturer upload error", DATA_ENTRY_ERROR: "Data entry error", INCORRECT_SCORE: "Incorrect score",
  MISSING_SCORE: "Missing score", WRONG_STUDENT: "Wrong student", WRONG_COURSE: "Wrong course", WRONG_SESSION: "Wrong session",
  WRONG_SEMESTER: "Wrong semester", WRONG_PROGRAMME: "Wrong programme", APPROVED_ACADEMIC_CORRECTION: "Approved academic correction",
  MIGRATION_CORRECTION: "Migration correction", OTHER: "Other",
};
/** the reasons whose correction is a mark the desk enters (the others are put right by removing or moving the result) */
export const NEEDS_MARKS: ReasonKind[] = ["INCORRECT_SCORE", "MISSING_SCORE", "DATA_ENTRY_ERROR", "LECTURER_UPLOAD_ERROR"];

export const REQUEST_STATE_WORD: Record<string, string> = {
  OPEN: "With the desk of entry", IN_AMENDMENT: "In an amendment", RESOLVED: "Corrected", DECLINED: "Declined", WITHDRAWN: "Withdrawn",
};
export const REQUEST_STATE_TONE: Record<string, "grey" | "info" | "ok" | "bad" | "warn"> = {
  OPEN: "warn", IN_AMENDMENT: "info", RESOLVED: "ok", DECLINED: "bad", WITHDRAWN: "grey",
};
export const requestOpen = (state: string | null | undefined) => state === "OPEN" || state === "IN_AMENDMENT";

/** a mark in words: "CA 25 · Exam 40 · 65 (B)", "Absent", or "No mark" */
export function markWords(m: { ca?: number | null; exam?: number | null; total?: number | null; grade?: string | null; outcome?: string | null } | null | undefined): string {
  if (!m || (m.ca == null && m.exam == null && m.total == null && !m.outcome)) return "No mark";
  if (m.outcome && m.outcome !== "GRADED") return OUTCOME_WORD[m.outcome] ?? m.outcome;
  const parts: string[] = [];
  if (m.ca != null) parts.push(`CA ${m.ca}`);
  if (m.exam != null) parts.push(`Exam ${m.exam}`);
  const total = m.total ?? (m.ca != null && m.exam != null ? m.ca + m.exam : null);
  if (total != null) parts.push(`${total}${m.grade ? ` (${m.grade})` : ""}`);
  return parts.join(" · ") || "No mark";
}

export interface Proposal { reasonKind: ReasonKind | ""; note: string; ca: string; exam: string; outcome: string }
export interface CurrentMark { ca?: number | null; exam?: number | null; outcome?: string | null }

/** what stops a correction request going (the server's CRQ_* rules, said before it is sent); null when it may go */
export function proposalProblem(p: Proposal, current: CurrentMark | null, caMax = 40): string | null {
  if (!p.reasonKind) return "Choose why the result is wrong.";
  if (p.note.trim().length < 10) return "Say what is wrong, in ten characters or more.";
  const hasCa = p.ca.trim() !== "", hasExam = p.exam.trim() !== "";
  if (hasCa !== hasExam) return "Give the CA and the examination mark together.";
  const graded = (p.outcome || "GRADED") === "GRADED";
  if (graded && !hasCa && NEEDS_MARKS.includes(p.reasonKind as ReasonKind)) return "An incorrect or missing score names the marks it should be.";
  if (hasCa) {
    const ca = Number(p.ca), exam = Number(p.exam);
    if (!Number.isInteger(ca) || !Number.isInteger(exam) || ca < 0 || exam < 0) return "Marks are whole numbers from 0.";
    if (ca + exam > 100) return "The CA and the examination come to more than 100.";
    if (ca > caMax || exam > 100 - caMax) return `This course's CA is out of ${caMax} and its examination out of ${100 - caMax}.`;
    if (current && current.ca === ca && current.exam === exam && (current.outcome ?? "GRADED") === (p.outcome || "GRADED")) {
      return "These are the marks on record.";
    }
  }
  return null;
}

/** the proposal as the server takes it (POST /api/v1/results/monitor/corrections) */
export function proposalBody(sheetId: string, studentId: string, p: Proposal) {
  const hasCa = p.ca.trim() !== "";
  return {
    sheetId, studentId, reasonKind: p.reasonKind, note: p.note.trim(),
    ca: hasCa ? Number(p.ca) : null, exam: hasCa ? Number(p.exam) : null, outcome: p.outcome || (hasCa ? "GRADED" : null),
  };
}

/** a query string of the filters given, the empty ones left out */
export function monitorQuery(params: Record<string, string | number | null | undefined>): string {
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) if (v !== null && v !== undefined && String(v).trim() !== "") q.set(k, String(v));
  const s = q.toString();
  return s ? `?${s}` : "";
}

export interface RecordRow {
  studentId: string; offeringId: string; number: string | null; jamb: string | null; surname: string; otherNames: string;
  programmeCode: string; programme: string | null; department: string | null; faculty: string | null; level: number;
  courseCode: string; courseTitle: string | null; units: number; entryType: string; state: ResultState; lecturer: string | null;
  sheetId: string | null; stage: string; ca: number | null; exam: number | null; total: number | null; grade: string | null;
  points: number | null; qualityPoints: number | null; outcome: string | null; sitting: string | null; publishedAt: string | null;
  versions: number; uploadedAt: string | null; lastModified: string | null; imported: boolean | null;
  openRequest: string | null; openAmendment: string | null;
}

export const RECORD_HEADERS = [
  "Student", "Matric No.", "JAMB No.", "Faculty", "Department", "Programme", "Level", "Course Code", "Course Title", "Units",
  "CA", "Exam", "Total", "Grade", "Grade Point", "Quality Point", "Result Status", "Stage", "Lecturer", "Uploaded", "Last Modified",
];

const day = (s: string | null | undefined) => (s ? s.slice(0, 10) : "");

/** one record as an export row (S/N is added by the export) */
export function recordCells(r: RecordRow): (string | number | null)[] {
  return [
    `${r.surname.toUpperCase()}, ${r.otherNames}`, r.number ?? "", r.jamb ?? "", r.faculty ?? "", r.department ?? "", r.programme ?? r.programmeCode,
    r.level, r.courseCode, r.courseTitle ?? "", r.units, r.ca, r.exam, r.total, r.grade ?? (r.outcome && r.outcome !== "GRADED" ? OUTCOME_WORD[r.outcome] ?? r.outcome : ""),
    r.points, r.qualityPoints, STATE_WORD[r.state] ?? r.state, stageWord(r.stage), r.lecturer ?? "", day(r.uploadedAt), day(r.lastModified),
  ];
}
