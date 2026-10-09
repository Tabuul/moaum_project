/** The CBT examination engine (V322) as the screens read it: the office's examinations, candidates, monitor and results; the
 *  candidate's examinations, attempt and result. The words for every state live here so the screens agree. */

/** V364: EXAMS is the University's examinations office, for every other CBT-enabled course */
export type CbtOffice = "GST" | "EPS" | "EXAMS" | "JUPEB";
export type ExamState = "DRAFT" | "SCHEDULED" | "PUBLISHED" | "CLOSED" | "COMPLETED" | "CANCELLED";
export type LiveState = ExamState | "UPCOMING" | "OPEN" | "ENDED";
export type ResultsState = "PENDING" | "AUTO_SCORED" | "UNDER_REVIEW" | "APPROVED" | "PUBLISHED";
export type AttemptStatus = "NOT_STARTED" | "IN_PROGRESS" | "SUBMITTED" | "TIME_EXPIRED" | "TERMINATED";

export interface CbtExamRow {
  id: string; reference: string; title: string; course_code: string; course_title: string; session: string; semester: number; state: ExamState; results_state: ResultsState;
  live_state: LiveState; starts_at: string | null; ends_at: string | null; duration_minutes: number; selection: "FIXED" | "RANDOM"; total_questions: number;
  security_mode: "STANDARD" | "SECURE"; venue: "REMOTE" | "LAB"; pass_mark: number; published_at: string | null; completed_at: string | null;
  pool_size: number; candidates: number; started: number; writing: number; scored: number;
}
export interface CbtOffering { id: string; course_code: string; title: string; units: number; level: number; semester: number; session: string; questions: number }
/** V365: a JUPEB subject the JUPEB Office may examine by CBT */
export interface JupebSubject { id: string; code: string; title: string; cbt_enabled: boolean; questions: number; registered: number }
export interface CbtExamList { office: CbtOffice; session: string; semester: number | null; archived?: boolean; rows: CbtExamRow[]; sessions: { name: string; state: string }[]; offerings: CbtOffering[]; subjects?: JupebSubject[]; now: string }
export interface CaComponent { id: string; code: string; title: string; max_score: number }

/** V364: the examination's further settings, as the API keeps them */
export type ExamType = "EXAMINATION" | "TEST" | "QUIZ" | "MOCK" | "RESIT";
export type Detector = "TAB" | "BLUR" | "FULLSCREEN" | "COPY" | "PASTE" | "RIGHT_CLICK" | "NETWORK";
export interface ExamSettings {
  exam_type: ExamType; negative_marks: number; allow_back: boolean; allow_review: boolean; fullscreen_required: boolean; detectors: Detector[]; counted_events: string[];
  warn_at: number | null; final_warn_at: number | null; disconnect_minutes: number | null; proctoring: "NONE" | "CAMERA"; score_on_submit: boolean;
  sheet_component: "EXAM" | "CA" | "NONE"; blueprint: "DIFFICULTY" | "TOPIC" | null; archived_at: string | null;
}
export const EXAM_TYPE_WORD: Record<ExamType, string> = { EXAMINATION: "Examination", TEST: "Test", QUIZ: "Quiz", MOCK: "Mock examination", RESIT: "Resit" };
export const DETECTOR_WORD: Record<Detector, string> = {
  TAB: "Leaving the tab", BLUR: "The window losing focus", FULLSCREEN: "Leaving fullscreen", COPY: "Copy and cut", PASTE: "Paste", RIGHT_CLICK: "Right-click", NETWORK: "The connection dropping",
};
/** the events an office may count towards the violation thresholds; the rest are recorded as evidence only */
export const COUNTABLE: [string, string][] = [
  ["TAB_SWITCH", "Left the tab"], ["WINDOW_BLUR", "Window lost focus"], ["FULLSCREEN_EXIT", "Exited fullscreen"], ["COPY_ATTEMPT", "Copy"], ["CUT_ATTEMPT", "Cut"],
  ["PASTE_ATTEMPT", "Paste"], ["RIGHT_CLICK", "Right-click"], ["NETWORK_DISCONNECT", "Connection dropped"], ["EXAM_PAGE_EXIT", "Left the examination page"],
  ["UNUSUAL_NAVIGATION", "Unusual navigation"], ["TIME_MANIPULATION_ATTEMPT", "Device clock moved"], ["FACE_NOT_DETECTED", "No face seen (camera)"],
  ["MULTIPLE_FACES", "More than one face (camera)"], ["FACE_OUT_OF_FRAME", "Face out of frame (camera)"], ["PROLONGED_LOOK_AWAY", "Away from the camera a long while"], ["CAMERA_STOPPED", "Camera stopped"],
];

export interface CbtCounts {
  candidates: number; eligible: number; not_started: number; in_progress: number; submitted: number; time_expired: number; terminated: number;
  disconnected: number; warned: number; critical: number; scored: number; live_state: LiveState; now: string;
}
export interface CbtStats {
  candidates: number; started: number; completed: number; submitted: number; time_expired: number; terminated: number; scored: number; not_started: number;
  average: number | null; highest: number | null; lowest: number | null; passed: number; failed: number; void: number;
}
export interface PaperQuestion { id: string; topic: string | null; kind: string; stem: string; difficulty: string; bank_marks: number; paper_marks: number | null; marks: number; ordinal: number; active: boolean; options: number }
export interface CbtExam extends Omit<CbtExamRow, "candidates" | "started" | "writing" | "scored">, ExamSettings {
  office: CbtOffice; offering_id: string; instructions: string | null; randomize_questions: boolean; randomize_options: boolean; attempt_limit: number;
  violation_limit: number; violation_action: "WARN" | "SUBMIT" | "TERMINATE"; second_session: "CONTINUE" | "DENY" | "MONITOR"; partial_credit: boolean; results_approved_at: string | null; results_published_at: string | null;
  created_at: string; created_by_name: string | null; created_office: string | null; closed_at: string | null; cancelled_at: string | null; cancel_reason: string | null;
  units: number; course_level: number; ca_max: number; pool_marks: number; paper_problem: string | null; has_sheet: boolean; sheet_stage: string | null;
  paper: PaperQuestion[]; bank: { topic: string; active: number; total: number; marks: number }[]; counts: CbtCounts; stats: CbtStats;
  results: { versions: number; amendments: number }; now: string;
  /** V364: the blueprint's rows, and the topics the pool holds */
  blueprintRows: { value: string; questions: number }[]; topics: { topic: string; questions: number }[];
  /** V365: a JUPEB examination's subject, and the parts of the JUPEB continuous assessment it may count towards */
  jupeb_subject_id?: string | null; jupeb_ca_component_id?: string | null; caComponents?: CaComponent[];
}

export interface Candidate {
  student_id: string; number: string; surname: string; other_names: string; sex: string | null; faculty_code: string; faculty: string; dept_code: string; department: string;
  programme_code: string; programme: string; level: number; student_status: string; entitled: boolean; eligible: boolean; attempts: number; attempt_id: string | null;
  attempt_status: AttemptStatus; connection: "ONLINE" | "DISCONNECTED" | null; started_at: string | null; ends_at: string | null; submitted_at: string | null;
  time_left: number | null; last_activity_at: string | null; violations: number; answered: number; score: number | null; max_marks: number | null; percentage: number | null;
  grade: string | null; passed: boolean | null; outcome: string | null; updated_at: string | null;
  /** V373: the candidate's sitting and seat, and extra time the office gave them */
  extra_minutes?: number | null; extra_reason?: string | null; sitting_id?: string | null; sitting?: string | null; sitting_venue?: string | null;
  sitting_starts_at?: string | null; seat_no?: number | null;
}
export interface CandidatePage {
  exam: { id: string; title: string; course_code: string; live_state: LiveState; violation_limit: number }; total: number; page: number; size: number; rows: Candidate[];
  options: { faculties: { code: string; name: string }[]; departments: { code: string; name: string; faculty_code: string }[]; programmes: { code: string; name: string; dept_code: string }[]; levels: number[] };
  now: string;
}
export interface Group {
  faculty_code?: string | null; faculty?: string | null; dept_code?: string | null; department?: string | null; programme_code?: string | null; programme?: string | null;
  level?: number | null; grade?: string | null; candidates: number; eligible: number; started: number; completed: number; submitted: number; time_expired: number; terminated: number;
  in_progress: number; not_started: number; disconnected: number; scored: number; average: number | null; highest: number | null; lowest: number | null; passed: number; failed: number; void: number;
}
export interface Analytics { totals: Partial<Group>; byFaculty: Group[]; byDepartment: Group[]; byProgramme: Group[]; byLevel: Group[]; byGrade: Group[]; buckets: { bucket: number; low: number; high: number; n: number }[] }
export interface ResultsPage extends CandidatePage, Analytics { stats: CbtStats }

export interface MonitorRow {
  attempt_id: string; student_id: string; number: string; surname: string; other_names: string; attempt_no: number; attempt_status: AttemptStatus; started_at: string; ends_at: string;
  submitted_at: string | null; last_activity_at: string; violations: number; answered: number; questions: number; score: number | null; max_marks: number; percentage: number | null;
  grade: string | null; passed: boolean | null; outcome: string; updated_at: string; finished_reason: string | null;
}
export interface MonitorEvent { id: string; attempt_id: string; kind: string; violation: boolean; at: string; detail: string | null; number: string; surname: string; other_names: string; severity?: Severity; question_no?: number | null; duration_ms?: number | null }
export type Severity = "INFO" | "LOW" | "MEDIUM" | "HIGH";
export const SEVERITY_WORD: Record<Severity, [string, "ok" | "bad" | "warn" | "grey" | "info"]> = { INFO: ["Info", "grey"], LOW: ["Low", "info"], MEDIUM: ["Medium", "warn"], HIGH: ["High", "bad"] };
export interface Monitor {
  exam: { id: string; reference: string; title: string; course_code: string; live_state: LiveState; state: ExamState; starts_at: string; ends_at: string; duration_minutes: number; violation_limit: number; violation_action: string };
  counts: CbtCounts; rows: MonitorRow[]; events: MonitorEvent[]; cursor: string; now: string;
}
export interface CandidateDetail {
  candidate: Candidate;
  attempts: { id: string; number: number; status: AttemptStatus; started_at: string; ends_at: string; submitted_at: string | null; last_activity_at: string; violations: number; answered: number; questions: number; score: number | null; max_marks: number; percentage: number | null; grade: string | null; passed: boolean | null; outcome: string; ip: string | null; user_agent: string | null; finished_reason: string | null; finished_office: string | null }[];
  events: { attempt_id: string; kind: string; violation: boolean; at: string; detail: string | null; ip: string | null; severity?: Severity; question_no?: number | null; duration_ms?: number | null }[];
  versions: { attempt_id: string; version: number; score: number; max_marks: number; percentage: number; grade: string | null; passed: boolean; outcome: string; reason: string | null; changed_at: string; changed_office: string | null; changed_by: string | null }[];
}
export interface CbtSummary {
  office: CbtOffice; session: string;
  summary: { exams: number; upcoming: number; open: number; completed: number; draft: number; writing: number; scores: number; results_pending: number; results_published: number; candidates: number };
  next: { id: string; reference: string; title: string; course_code: string; starts_at: string | null; ends_at: string | null; state: ExamState; results_state: ResultsState; live_state: LiveState; writing: number }[];
  now: string;
}

/* the candidate's side */
/** V373: where and when a candidate sits an examination, and any extra time they were given */
export interface Placement { sitting?: string | null; sitting_venue?: string | null; sitting_starts_at?: string | null; sitting_ends_at?: string | null; seat_no?: number | null; extra_minutes?: number | null }
export type MyExam = {
  exam_id: string; reference: string; office: CbtOffice; course_code: string; course_title: string; title: string; session: string; semester: number; instructions: string | null;
  live_state: LiveState; starts_at: string; ends_at: string; duration_minutes: number; questions: number; security_mode: "STANDARD" | "SECURE"; venue: "REMOTE" | "LAB";
  attempt_limit: number; violation_limit: number; violation_action: string; eligibility: string | null; attempts: number; attempt_id: string | null; attempt_status: AttemptStatus | null;
  attempt_ends_at: string | null; submitted_at: string | null; result_published: boolean; score: number | null; max_marks: number | null; percentage: number | null;
  grade: string | null; passed: boolean | null; pass_mark: number; outcome: string | null; partial_credit?: boolean;
  exam_type?: ExamType; negative_marks?: number; allow_back?: boolean; allow_review?: boolean; fullscreen_required?: boolean; proctoring?: "NONE" | "CAMERA"; score_on_submit?: boolean;
} & Placement;
export interface MyExams { session: string; rows: MyExam[]; now: string }
export interface RoomQuestion { n: number; id: string; kind: "MCQ" | "TRUE_FALSE" | "MULTI"; stem: string; marks: number; options: { i: number; text: string }[] }
export interface Room {
  attempt: { id: string; number: number; status: AttemptStatus; started_at: string; ends_at: string; submitted_at: string | null; answered: number; violations: number; max_marks: number; questions: number;
             camera_consent_at?: string | null; camera_declined_at?: string | null };
  exam: { id: string; reference: string; title: string; course_code: string; course_title: string; session: string; semester: number; duration_minutes: number; randomize_options: boolean; security_mode: string; venue: string; violation_limit: number; violation_action: string; instructions: string | null; live_state: LiveState; partial_credit?: boolean;
          exam_type?: ExamType; negative_marks?: number; allow_back?: boolean; allow_review?: boolean; fullscreen_required?: boolean; detectors?: Detector[]; proctoring?: "NONE" | "CAMERA";
          office?: string; warn_at?: number; final_warn_at?: number; disconnect_minutes?: number | null };
  questions: RoomQuestion[]; answers: Record<string, number[]>; now: string;
  /** V364: the questions marked for review, the screen's save counts, and the candidate named in the header */
  flagged?: string[]; seqs?: Record<string, number>;
  /** the candidate the screen names: name, the number and what it is (Matric No., Admission No., JUPEB No.), a student's level */
  candidate?: { surname: string; other_names: string; number: string; number_label?: string; level?: number | null };
  /** V373: the candidate's sitting and seat, and extra time */
  placement?: Placement;
}

export const EXAM_WORD: Record<string, [string, "ok" | "bad" | "warn" | "grey" | "info"]> = {
  DRAFT: ["Draft", "grey"], SCHEDULED: ["Scheduled", "info"], PUBLISHED: ["Published", "info"], UPCOMING: ["Upcoming", "info"], OPEN: ["Open now", "ok"], ENDED: ["Window ended", "warn"],
  CLOSED: ["Closed", "warn"], COMPLETED: ["Completed", "ok"], CANCELLED: ["Cancelled", "bad"],
};
export const RESULTS_WORD: Record<string, [string, "ok" | "bad" | "warn" | "grey" | "info"]> = {
  PENDING: ["Scores as they come", "grey"], AUTO_SCORED: ["Auto-scored", "info"], UNDER_REVIEW: ["Under review", "warn"], APPROVED: ["Approved", "info"], PUBLISHED: ["Published", "ok"],
};
export const ATTEMPT_WORD: Record<string, [string, "ok" | "bad" | "warn" | "grey" | "info"]> = {
  NOT_STARTED: ["Not started", "grey"], IN_PROGRESS: ["Writing", "info"], SUBMITTED: ["Submitted", "ok"], TIME_EXPIRED: ["Time expired", "warn"], TERMINATED: ["Terminated", "bad"], DISCONNECTED: ["Disconnected", "warn"],
};
export const EVENT_WORD: Record<string, string> = {
  STARTED: "Started", RESUMED: "Returned to the examination", TAB_SWITCH: "Left the examination tab", WINDOW_BLUR: "Examination window lost focus", FULLSCREEN_EXIT: "Exited fullscreen",
  NETWORK_DISCONNECT: "Connection lost", RECONNECTED: "Reconnected", MULTIPLE_LOGIN: "Opened on another browser or device", SESSION_REPLACED: "Earlier screen replaced",
  COPY_PASTE: "Copy or paste attempted", CONTEXT_MENU: "Context menu attempted", WARNING: "Warning given", FINAL_WARNING: "Final warning given", AUTO_SUBMITTED: "Submitted automatically",
  TERMINATED: "Terminated", SUBMITTED: "Submitted", TIME_EXPIRED: "Time expired", AMENDED: "Result amended",
  WINDOW_FOCUS: "Window focused again", FULLSCREEN_ENTER: "Returned to fullscreen", COPY_ATTEMPT: "Copy attempted", CUT_ATTEMPT: "Cut attempted", PASTE_ATTEMPT: "Paste attempted",
  RIGHT_CLICK: "Right-click attempted", UNUSUAL_NAVIGATION: "Unusual navigation", TIME_MANIPULATION_ATTEMPT: "Device clock moved", EXAM_PAGE_EXIT: "Left the examination page",
  DISCONNECT_TIMEOUT: "Out of contact past the limit", CAMERA_CONSENTED: "Consented to the camera", CAMERA_DECLINED: "Camera not consented or not usable", CAMERA_STOPPED: "Camera stopped",
  FACE_NOT_DETECTED: "No face seen", MULTIPLE_FACES: "More than one face seen", FACE_OUT_OF_FRAME: "Face out of frame", HEAD_POSE_LEFT: "Head turned left", HEAD_POSE_RIGHT: "Head turned right",
  HEAD_POSE_UP: "Head turned up", HEAD_POSE_DOWN: "Head turned down", PROLONGED_LOOK_AWAY: "Away from the camera a long while",
};
export const ELIGIBILITY_WORD: Record<string, string> = {
  CBT_EXAM_NOT_OPEN: "Not open to candidates", CBT_EXAM_CANCELLED: "Cancelled", CBT_EXAM_NOT_STARTED: "Opens later", CBT_EXAM_ENDED: "Window closed", CBT_STUDENT_INACTIVE: "Student record not active",
  CBT_COURSE_NOT_REGISTERED: "Course not registered", GST_PAYMENT_REQUIRED: "GST fee not paid", CBT_PAPER_EMPTY: "Paper not ready", CBT_POOL_TOO_SMALL: "Paper not ready", CBT_PAPER_SIZE: "Paper not ready",
  CBT_ATTEMPT_LIMIT: "Attempts used", CBT_FEES_NOT_CLEARED: "School fees not cleared", CBT_COURSE_NOT_ENABLED: "Not a CBT course", CBT_BLUEPRINT_SHORT: "Paper not ready",
  CBT_BLUEPRINT_TOTAL: "Paper not ready", CBT_BLUEPRINT_EMPTY: "Paper not ready",
  CBT_JUPEB_FEES: "School fee share not paid", CBT_JUPEB_SUBJECT_NOT_REGISTERED: "Subject not registered", CBT_JUPEB_NOT_STUDENT: "Not yet a JUPEB student",
};

export const codeOf = (why: string | null | undefined): string | null => (why ? why.split(":")[0] : null);
export const textOf = (why: string | null | undefined): string => (why ? why.replace(/^[A-Z0-9_]+: /, "") : "");
export const pct1 = (n: number | string | null | undefined) => (n == null ? "—" : `${Number(n).toFixed(1)}%`);
export const num = (n: number | string | null | undefined) => Number(n ?? 0).toLocaleString();
export const whenAt = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
export const clock = (seconds: number) => {
  const s = Math.max(0, Math.floor(seconds));
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = s % 60;
  return (h ? `${h}:` : "") + `${String(m).padStart(2, "0")}:${String(r).padStart(2, "0")}`;
};
/** a candidate's live status, the connection judged from the last activity the browser reported against the server's clock */
export const liveStatus = (status: AttemptStatus, lastActivity: string | null | undefined, serverNow: number): string =>
  status === "IN_PROGRESS" && lastActivity && serverNow - new Date(lastActivity).getTime() > 60_000 ? "DISCONNECTED" : status;
