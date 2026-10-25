/** V651: postgraduate academic management — stages, cycles, progression, extension, restart — as /api/v1/pg/academic answers */

export type Recommendation = "NORMAL_PROGRESS" | "EXTENSION_REQUIRED" | "EXTENSION" | "MAXIMUM_PERIOD_REACHED" | "RESTART_REQUIRED" | "COMPLETED" | "CLOSED"
  | "UNKNOWN" | "NOT_STARTED";
export type CycleStatus = "ACTIVE" | "COMPLETED" | "GRADUATED" | "MAXIMUM_PERIOD_EXHAUSTED" | "CLOSED" | "NOT_RECORDED";
export type RestartState = "REQUESTED" | "UNDER_REVIEW" | "APPROVED" | "REJECTED" | "CANCELLED";
type Tone = "ok" | "warn" | "bad" | "grey" | "info";

export interface Qualification { code: string; label: string; level: number; normal_years: number; extension_years: number; restart_allowed: boolean; updated_at: string }
export interface Stage {
  code: string; qualification: string; label: string; short_label: string; sequence: number; year_number: number | null; extension_number: number | null;
  is_extension: boolean; semesters: number[]; active: boolean; level: number; next_label: string | null;
}
export interface Config {
  session: string | null; qualifications: Qualification[]; stages: Stage[]; permissions: string[]; office: string; boundDept: string | null;
  boundFaculty: string | null; sessions: string[];
}

export interface StageCount {
  qualification: string; stage_code: string | null; stage_label: string; sequence: number; is_extension: boolean; students: number; male: number; female: number;
  fresh: number; returning: number; official: number; registered: number; paid: number;
}

export interface StageRow {
  student_id: string; cycle_id: string | null; cycle_no: number; qualification: string | null; programme_code: string; start_session: string | null;
  cycle_status: CycleStatus; stage_code: string | null; stage_label: string | null; stage_seq: number | null; stages: number | null; is_extension: boolean;
  official: boolean; category: "FRESH" | "RETURNING" | null; beyond: boolean; recommendation: Recommendation;
  matric_no: string | null; admission_no: string | null; surname: string; other_names: string; sex: string | null; current_level: number | null;
  entry_session: string | null; status: string; programme: string; department: string | null; registered: boolean; paid: boolean; open_restart: string | null;
}
export interface StudentsPage { session: string; total: number; page: number; size: number; rows: StageRow[] }

export interface Outcome { student_id: string; outcome: string; stage_code?: string | null; stage_label?: string | null; message?: string | null }
export interface Outcomes { outcomes: Record<string, number>; rows: Outcome[]; skipped?: number; byStatus?: Record<string, number> }

export interface RestartRow {
  reference: string; state: RestartState; start_session: string; reason: string; requested_office: string | null; requested_at: string; dept_note: string | null;
  dept_at: string | null; decision_note: string | null; decided_at: string | null; student_id: string; matric_no: string | null; surname: string; other_names: string;
  programme: string; department: string | null; cycle_no: number; qualification: string; new_cycle_no: number | null; mine: boolean;
}

export interface ScanRow {
  student_id: string; qualification: string | null; programme_code: string; current_level: number | null; entry_session: string | null; status: string;
  stage_code: string | null; stage_label: string | null; category: string | null; beyond: boolean; recommendation: Recommendation; confidence: "HIGH" | "MEDIUM" | "LOW";
  notes: string[]; matric_no: string | null; surname: string; other_names: string; programme: string;
}
export interface Scan { session: string; total: number; byConfidence: Record<string, number>; byRecommendation: Record<string, number>; matching: number; rows: ScanRow[] }

export interface QualityRow { issue: string; detail: string; student_id: string; matric_no: string | null; surname: string; other_names: string; programme: string; department: string | null }
export interface Quality { session: string; byIssue: Record<string, number>; matching: number; rows: QualityRow[] }

export interface History {
  pg: boolean; session: string;
  current: (Omit<StageRow, "matric_no" | "admission_no" | "surname" | "other_names" | "sex" | "current_level" | "entry_session" | "status" | "programme" | "department" | "registered" | "paid" | "open_restart">) | null;
  cycles: {
    id: string; cycle_no: number; qualification: string; qualification_label: string; programme_code: string; programme: string; start_session: string; status: CycleStatus;
    status_reason: string | null; status_at: string | null; source: string; created_at: string; restart_of: string | null;
    stages: { session: string; stage_code: string; label: string; is_extension: boolean; source: string; reason: string | null; decided_office: string | null; at: string; decided_by_name: string | null }[];
  }[];
  restarts: { reference: string; state: RestartState; start_session: string; reason: string; requested_office: string | null; requested_at: string; dept_note: string | null; decision_note: string | null; cycle_no: number; new_cycle_no: number | null }[];
  payments: { reference: string; session: string; amount: number | string; paid: boolean; cycle_no: number | null; stage_code: string | null; stage_label: string | null; category: string | null; official: boolean }[];
}

export const RECOMMENDATION_WORDS: Record<Recommendation, [string, Tone]> = {
  NORMAL_PROGRESS: ["Normal progress", "ok"], EXTENSION_REQUIRED: ["Extension required", "warn"], EXTENSION: ["Extension", "warn"],
  MAXIMUM_PERIOD_REACHED: ["Maximum period reached", "bad"], RESTART_REQUIRED: ["Restart required", "bad"], COMPLETED: ["Completed", "grey"],
  CLOSED: ["Closed", "grey"], UNKNOWN: ["Cannot be read", "bad"], NOT_STARTED: ["Not yet begun", "grey"],
};

export const CYCLE_WORDS: Record<CycleStatus, [string, Tone]> = {
  ACTIVE: ["Active", "ok"], COMPLETED: ["Completed", "grey"], GRADUATED: ["Graduated", "grey"], MAXIMUM_PERIOD_EXHAUSTED: ["Maximum period exhausted", "bad"],
  CLOSED: ["Closed", "grey"], NOT_RECORDED: ["Not yet recorded", "warn"],
};

export const RESTART_WORDS: Record<RestartState, [string, Tone]> = {
  REQUESTED: ["Awaiting the department", "warn"], UNDER_REVIEW: ["Awaiting the PG School", "warn"], APPROVED: ["Approved — new cycle", "ok"],
  REJECTED: ["Rejected", "bad"], CANCELLED: ["Withdrawn", "grey"],
};

export const ISSUE_WORDS: Record<string, string> = {
  NO_QUALIFICATION: "No qualification", LEVEL_MISMATCH: "Level not the qualification's", NO_ADMISSION_SESSION: "No admission session", NO_CYCLE: "No cycle recorded",
  BEYOND_MAXIMUM: "Past the maximum period", RESTART_REQUIRED: "Restart required", NO_STAGE_RECORDED: "Stage calculated, not recorded",
};

export const OUTCOME_WORDS: Record<string, string> = {
  PROGRESSED: "progressed", EXTENDED: "extended", ALREADY: "recorded already", NEEDS_APPROVAL: "need the Dean's approval (extension)", MAXIMUM: "past the maximum period",
  NO_CYCLE: "with no cycle recorded yet", SKIPPED: "skipped", REFUSED: "refused", CLOSED: "closed as exhausted", RECORDED: "recorded",
  SKIPPED_LOW_CONFIDENCE: "skipped (low confidence)",
};

/** "800 B — Year 2" for a stage, "Past the maximum period" when there is none and the cycle is beyond it */
export function stageText(r: { stage_label: string | null; beyond: boolean; recommendation: Recommendation }): string {
  if (r.stage_label) return r.stage_label;
  if (r.beyond) return "Past the maximum period";
  return RECOMMENDATION_WORDS[r.recommendation]?.[0] ?? "—";
}

/** "12 progressed, 3 need the Dean's approval (extension)" */
export function outcomeText(o: Record<string, number>): string {
  const parts = Object.entries(o).map(([k, n]) => `${n.toLocaleString()} ${OUTCOME_WORDS[k] ?? k.toLowerCase()}`);
  return parts.length ? parts.join(", ") : "Nothing to do";
}

export const can = (cfg: Pick<Config, "permissions"> | null, p: string) => !!cfg && cfg.permissions.includes(p);

/** "PG-RST/2026/000001" → "2026/000001", the path the API takes */
export const restartPath = (ref: string) => ref.replace(/^PG-RST\//, "");

/** the level of a postgraduate programme from its name, as people.pg_level_of reads it: Ph.D. 900, PGD 700, every other 800 */
export function pgLevelOfName(name: string): 700 | 800 | 900 {
  const n = name.toUpperCase();
  if (/^\s*(PH\.?\s?D|DOCTOR OF PHILOSOPHY)/.test(n)) return 900;
  if (/^\s*(P\.?\s?G\.?\s?D|POST\s?-?GRADUATE DIPLOMA)/.test(n)) return 700;
  return 800;
}
