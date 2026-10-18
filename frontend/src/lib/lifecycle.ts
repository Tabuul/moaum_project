/** Student lifecycle reconciliation (V558): the shapes /api/v1/cohorts/lifecycle returns and the words the screen uses for them.
 *  The recommendation comes from the cohort engine and the completion check; nothing here works one out. */

type Kind = "grey" | "info" | "ok" | "bad" | "warn";

export interface LifeRow {
  id: string; surname: string; other_names: string; matric_no: string | null; admission_no: string | null; sex: string | null; entry_mode: string | null;
  programme_code: string; programme: string; dept_code: string; department: string; faculty_code: string; faculty: string;
  entry_session: string | null; effective_cohort: string | null; cohort_source: string | null; matric_year: number | null;
  duration_years: number | null; duration_source: string | null; final_level: number | null; current_level: number | null; computed_level: number | null;
  expected_completion: string | null; current_session: string | null; deferred_sessions: number; spillover_years: number;
  registered_current: boolean; enrolled_current: boolean; last_session: string | null; existing_status: string;
  recommendation: string; candidate_basis: string | null; confidence: string; confidence_reasons: string | null; explanation: string; actionable: boolean;
  completion: string | null; outstanding_courses: string | null; awaiting_courses: string | null; completion_checked_at: string | null;
  review_state: string; review_note: string | null; reviewed_by: string | null; reviewed_at: string | null; batch_ref: string | null; reconciled_at: string | null;
  computed_at: string;
}
export interface LifeList { rows: LifeRow[]; total: number; page: number; size: number }
export interface LifeCount { recommendation: string; n: number }
export interface LifeSummary {
  total: number;
  byRecommendation: (LifeCount & { high: number; medium: number; low: number; pending: number; under_review: number; verified: number; rejected: number;
    requires_correction: number; reconciled: number; final_year: number; completed_beyond: number })[];
  byCompletion: { completion: string; n: number }[];
  byCohort: (LifeCount & { cohort: string | null })[];
  byFaculty: (LifeCount & { code: string; name: string })[];
  byDepartment: (LifeCount & { code: string; name: string; faculty: string })[];
  byProgramme: (LifeCount & { code: string; name: string; department: string })[];
  pool: number; checked: number; checkedFrom: string | null; checkedTo: string | null; computedFrom: string | null; computedTo: string | null;
  currentSession: string | null; maxSpilloverYears: number; batches: number;
}
export interface Reconciliation {
  id: string; batch_ref: string; student_id: string; surname: string; other_names: string; matric_no: string | null; programme: string; department: string; faculty: string;
  effective_session: string; recommendation: string; confidence: string; outcome: string; previous_status: string; new_status: string;
  previous_level: number | null; new_level: number | null; effective_cohort: string | null; expected_completion: string | null; spillover_years: number;
  completion: string | null; explanation: string; reason: string; graduand_added: boolean; graduand_unmet: string | null;
  reconciled_by: string | null; actor_office: string | null; reconciled_at: string; corrected_at: string | null; corrected_by: string | null;
  correction_reason: string | null; level_restored: boolean | null;
}
export interface LifeStudent extends LifeRow { reconciliations: Reconciliation[] }
export interface Batch {
  batch_ref: string; description: string; effective_session: string; scope: string | null; reconciled: number; skipped: number; corrected: number;
  created_by: string | null; actor_office: string | null; created_at: string; closed_at: string | null; in_scope?: number;
  spillover_confirmed?: number; kept_at_limit?: number; status_changed?: number; graduation_list?: number; corrected_in_scope?: number;
}
export interface Preview {
  chosen: number; eligible: number; studentIds: string[]; byRecommendation: Record<string, number>; byConfidence: Record<string, number>;
  statusMoves: Record<string, number>; levelsRaised: number; toGraduationList: number; alreadyOnGraduationList: number; excluded: Record<string, number>;
  limitOutcome: string | null; currentSession: string | null;
}
export interface Skipped { id: string; surname?: string; other_names?: string; matric_no?: string | null; code: string; message: string }

/** the recommendations, in the order the screen shows them: word, colour, what it means */
export const REC: Record<string, [string, Kind, string]> = {
  GRADUATION_CANDIDATE: ["Graduation candidate", "info", "In the final year, or beyond the programme's length with every registered course passed and published"],
  SPILLOVER_YEAR_1: ["Spillover year 1", "warn", "One session beyond the programme's length"],
  SPILLOVER_YEAR_2: ["Spillover year 2", "warn", "Two sessions beyond the programme's length"],
  MAXIMUM_SPILLOVER_REACHED: ["Maximum spillover reached", "bad", "Beyond the spillover limit — the Registry decides"],
  REQUIRES_REVIEW: ["Requires review", "bad", "No course registration on record, or a conflict in the record"],
  DATA_INCOMPLETE: ["Data incomplete", "bad", "The entry session or the programme's length is missing"],
  ON_GRADUATION_LIST: ["On the graduation list", "ok", "Audited with nothing unmet, awaiting the Senate"],
  WITHIN_NORMAL_DURATION: ["Within normal duration", "grey", "Still within the programme's length"],
};
/** the figures the screen leads with, each a way into its students */
export const LEAD = ["GRADUATION_CANDIDATE", "SPILLOVER_YEAR_1", "SPILLOVER_YEAR_2", "MAXIMUM_SPILLOVER_REACHED"];
export const FOLLOW = ["REQUIRES_REVIEW", "DATA_INCOMPLETE", "ON_GRADUATION_LIST", "WITHIN_NORMAL_DURATION"];

export function recWord(key: string): string {
  if (REC[key]) return REC[key][0];
  const m = /^SPILLOVER_YEAR_(\d+)$/.exec(key);
  return m ? `Spillover year ${m[1]}` : key.toLowerCase().replace(/_/g, " ");
}
export function recKind(key: string): Kind {
  return REC[key]?.[1] ?? (key.startsWith("SPILLOVER_YEAR_") ? "warn" : "grey");
}
/** only these are reconciled; the rest are reviewed, or corrected on the record */
export function actionable(key: string): boolean {
  return key === "GRADUATION_CANDIDATE" || key === "MAXIMUM_SPILLOVER_REACHED" || /^SPILLOVER_YEAR_\d+$/.test(key);
}

export const STATE: Record<string, [string, Kind]> = {
  PENDING: ["Pending", "grey"], UNDER_REVIEW: ["Under review", "info"], VERIFIED: ["Verified", "ok"], REJECTED: ["Rejected", "bad"],
  REQUIRES_CORRECTION: ["Requires correction", "warn"], RECONCILED: ["Reconciled", "ok"],
};
export const LCONF: Record<string, [string, Kind]> = { HIGH: ["High", "ok"], MEDIUM: ["Medium", "warn"], LOW: ["Low", "bad"] };
export const BASIS: Record<string, string> = { FINAL_YEAR: "Final year", COMPLETED_BEYOND_LENGTH: "Completed, beyond the length" };
export const COMPLETION: Record<string, [string, Kind]> = {
  COMPLETED: ["Completed", "ok"], OUTSTANDING_COURSES: ["Courses outstanding", "bad"], AWAITING_RESULT: ["Result awaited", "warn"],
  FINAL_LEVEL_NOT_REACHED: ["Final level not reached", "warn"], NO_PUBLISHED_RESULT: ["No published result", "grey"], NOT_CHECKED: ["Not yet checked", "grey"],
};
export const OUTCOME: Record<string, string> = {
  SPILLOVER_CONFIRMED: "Spillover confirmed", KEPT_ACTIVE_LIMIT_REACHED: "Kept active, maximum reached", STATUS_CHANGED: "Status changed",
  GRADUATION_LIST: "Put on the graduation list",
};
export const EXCLUDED: Record<string, string> = {
  ALREADY_RECONCILED: "Already reconciled this session", NOT_RECONCILABLE: "Not a recommendation that is reconciled — review it, or correct the record",
  NOT_VERIFIED: "Not yet verified", LIMIT_OUTCOME_NOT_CHOSEN: "At the maximum spillover — choose what the batch does for them",
  NOT_IN_SCOPE_OR_NOT_ACTIVE: "Not active, or outside your scope",
};
/** the officer's choices at the maximum spillover: never made for them */
export const LIMIT_CHOICES: { value: string; outcome: string; status?: string; label: string }[] = [
  { value: "KEEP", outcome: "KEPT_ACTIVE_LIMIT_REACHED", label: "Keep active, flagged as having reached the maximum" },
  { value: "DORMANT", outcome: "STATUS_CHANGED", status: "DORMANT", label: "Make the record dormant" },
  { value: "WITHDRAWN", outcome: "STATUS_CHANGED", status: "WITHDRAWN", label: "Withdraw the student" },
];

export const fmt = (v: number | null | undefined) => Number(v ?? 0).toLocaleString("en-GB");

/** "You are about to reconcile 1,240 student records." */
export function aboutToReconcile(n: number): string {
  return `You are about to reconcile ${fmt(n)} student record${n === 1 ? "" : "s"}.`;
}

/** the steps a batch is sent in */
export function chunks<T>(xs: T[], size: number): T[][] {
  const n = Math.max(1, Math.floor(size));
  const out: T[][] = [];
  for (let i = 0; i < xs.length; i += n) out.push(xs.slice(i, i + n));
  return out;
}

/** RECON/2026/000014 → the path the API files it under, 2026/000014; anything else is refused */
export function batchPath(ref: string): string | null {
  const m = /^RECON\/(\d{4})\/(\d{6})$/.exec(ref.trim());
  return m ? `${m[1]}/${m[2]}` : null;
}

/** a cross-tab of figures — one row a cohort, a faculty, a department or a programme — with a count for each recommendation */
export function crossTab<T extends LifeCount>(rows: T[], keyOf: (r: T) => string): { key: string; first: T; by: Record<string, number>; n: number }[] {
  const out = new Map<string, { key: string; first: T; by: Record<string, number>; n: number }>();
  for (const r of rows) {
    const k = keyOf(r);
    const e = out.get(k) ?? { key: k, first: r, by: {}, n: 0 };
    e.by[r.recommendation] = (e.by[r.recommendation] ?? 0) + Number(r.n);
    e.n += Number(r.n);
    out.set(k, e);
  }
  return [...out.values()];
}

/** the spillover years a cross-tab shows: year 1 and 2 always, and any further year the limit allows that has students */
export function spillColumns(present: string[]): string[] {
  const years = present.filter((k) => /^SPILLOVER_YEAR_\d+$/.test(k)).map((k) => Number(k.slice("SPILLOVER_YEAR_".length)));
  const max = Math.max(2, ...years);
  return Array.from({ length: max }, (_, i) => `SPILLOVER_YEAR_${i + 1}`);
}

/** a reason worth keeping on each student's history: a few words at least, never a single one */
export function reasonOk(reason: string): boolean {
  const r = reason.trim();
  return r.length >= 12 && r.split(/\s+/).length >= 3;
}
