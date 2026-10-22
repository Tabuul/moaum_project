/**
 * V638: students outside the maximum academic period graduated by status reconciliation — the words the screen says for the figures,
 * the confirmation, the timeline of one student and the batches. The cohort engine counts and the database decides; this only says it.
 */
export type Kind = "ok" | "warn" | "bad" | "info" | "grey";

export interface RecFigures {
  active: number; current: number; sp1: number; sp2: number; outsideMaximum: number; eligible: number; eligibleHigh: number; eligibleMedium: number;
  requiresReview: number; graduationCandidates: number; dataIncomplete: number; graduated: number; graduatedByReconciliation: number;
  graduatedAutomatically: number; maxSpilloverYears: number; autoGraduation: boolean; currentSession: string | null; lastAutomaticRun: string | null;
}

/** a student outside the maximum period as people.graduation_candidates gives them */
export interface Candidate {
  student_id: string; matric_no: string | null; jamb_reg_no: string | null; surname: string; other_names: string; status: string;
  programme_code: string | null; programme: string | null; dept_code: string | null; department: string | null; faculty_code: string | null; faculty: string | null;
  entry_session: string | null; matric_year: number | null; effective_cohort: string | null; cohort_source: string | null; entry_level: number | null;
  duration_years: number | null; duration_source: string | null; final_level: number | null; current_level: number | null; computed_level: number | null;
  current_session: string | null; deferred_sessions: number; live_deferment: boolean; expected_completion: string | null; sp1_session: string | null;
  sp2_session: string | null; max_spillover_years: number; maximum_session: string | null; spillover_years: number; spillover_state: string | null;
  registered_current: boolean; enrolled_current: boolean; last_session: string | null; completion: string | null; programme_moves: number;
  pending_moves: string | null; issues: string[] | null; confidence: "HIGH" | "MEDIUM" | "LOW"; confidence_reasons: string | null; recommendation: string;
  verdict?: "ELIGIBLE" | "REVIEW";
}

export interface Preview { identified: number; eligible: number; review: number; high: number; medium: number; low: number; includeMedium: boolean; rows: Candidate[] }

export interface RecBatch {
  batch_ref: string; description: string; mode: "MANUAL" | "AUTOMATIC"; effective_session: string; scope: string | null; min_confidence: string;
  selected: number; eligible: number; review: number; graduated: number; skipped: number; refused: number; corrected: number; created_by: string | null;
  actor_office: string; created_at: string; executed_at: string | null; closed_at: string | null; in_scope?: number; graduated_in_scope?: number; rows?: RecRow[];
}

export interface RecRow {
  student_id: string; surname: string; other_names: string; matric_no: string | null; status: string; programme_code: string | null; programme: string | null;
  confidence: string; verdict: "ELIGIBLE" | "REVIEW"; reasons: string | null; outcome: "GRADUATED" | "SKIPPED" | "REFUSED" | null; note: string | null;
  decided_at: string | null; graduation_session: string | null; graduation_date: string | null; date_confirmed: boolean | null; corrected_at: string | null;
}

export interface Reconciliation {
  id: string; batch_ref: string; mode: string; previous_status: string; new_status: string; entry_session: string | null; effective_cohort: string | null;
  duration_years: number | null; final_level: number | null; deferred_sessions: number; expected_completion: string | null; max_spillover_years: number;
  maximum_session: string | null; current_session: string; spillover_years: number; confidence: string; confidence_reasons: string | null;
  graduation_session: string | null; graduation_date: string | null; date_confirmed: boolean; date_confirmed_by: string | null; date_note: string | null;
  clearance: string | null; reason: string; reconciled_by: string | null; actor_office: string; reconciled_at: string; corrected_at: string | null;
  corrected_by: string | null; correction_reason: string | null;
}

export interface StudentReview {
  student: { id: string; surname: string; other_names: string; matric_no: string | null; status: string; programme: string | null; department: string | null; faculty: string | null };
  candidate: Candidate | null;
  position: { expected_completion: string | null; spillover_years: number; spillover_state: string; rule: string; classification: string; confidence: string; issues: string[] } | null;
  reconciliations: Reconciliation[];
  statusHistory: { from_status: string | null; to_status: string; instrument: string | null; effective_on: string | null; reason: string | null }[];
  registrations: { session: string; semester: number; level: number; status: string }[];
  deferments: { reference: string; kind: string; session: string; semester: number | null; state: string }[];
  programmeHistory: { at: string | null; session: string | null; kind: string; programme: string | null; level: number | null; from_programme: string | null }[];
}

export interface RecSetting { auto_graduation: boolean; max_spillover_years: number; updated_at: string | null; updated_by: string | null; last_automatic_run: string | null }

export const REC_CONFIDENCE: Record<string, [string, Kind, string]> = {
  HIGH: ["High", "ok", "complete and consistent: graduated by status reconciliation"],
  MEDIUM: ["Medium", "warn", "migrated with gaps the engine resolves: graduated only when the officer includes them"],
  LOW: ["Low — review", "bad", "conflicting or incomplete: requires review, never graduated in bulk"],
};

export const REC_REPORT_BY: [string, string][] = [
  ["faculty", "Faculty"], ["department", "Department"], ["programme", "Programme"], ["entry", "Admission session"],
  ["session", "Graduation session"], ["spillover", "Spillover state"], ["batch", "Reconciliation batch"],
];

export function fullName(r: { surname: string; other_names: string }): string {
  return `${r.surname}${r.other_names ? ", " + r.other_names : ""}`;
}

export function plural(n: number, one: string, many = `${one}s`): string {
  return `${n.toLocaleString("en-GB")} ${n === 1 ? one : many}`;
}

/** the confirmation the officer reads before anything is written */
export function confirmLines(p: Pick<Preview, "identified" | "eligible" | "review">): string[] {
  return [
    `${plural(p.identified, "student")} identified outside the maximum academic period.`,
    `${p.eligible.toLocaleString("en-GB")} eligible for automatic graduation.`,
    `${p.review.toLocaleString("en-GB")} require${p.review === 1 ? "s" : ""} manual review.`,
  ];
}

/** the reasons the database gave for the confidence, one a line, without the level prefix it carries for sorting */
export function reasonsOf(text: string | null | undefined): string[] {
  if (!text) return [];
  return text.split("; ").map((s) => s.replace(/^(LOW|MEDIUM): /, "").trim()).filter(Boolean);
}

/** the review timeline: what the engine counted, in the order the rule counts it */
export function timeline(c: Candidate | Reconciliation): [string, string][] {
  const length = c.duration_years ? `${c.duration_years} sessions${c.final_level ? ` to ${c.final_level} Level` : ""}` : "not configured";
  const out: [string, string][] = [
    ["Admission session", c.entry_session ?? "—"],
    ["Effective cohort", c.effective_cohort ?? "—"],
    ["Programme length", length],
    ["Approved deferments", String(c.deferred_sessions ?? 0)],
    ["Expected completion", c.expected_completion ?? "—"],
  ];
  if ("sp1_session" in c) {
    out.push(["SP1", c.sp1_session ?? "—"], ["SP2", c.sp2_session ?? "—"]);
  }
  out.push(
    ["Maximum session permitted", `${c.maximum_session ?? "—"} (${plural(c.max_spillover_years, "spillover session")} allowed)`],
    ["Current session", c.current_session ?? "—"],
    ["Sessions beyond the expected completion", String(c.spillover_years)],
  );
  return out;
}

/** the reference's year and sequence, as the API's path has them */
export function recBatchPath(ref: string): string {
  return ref.replace(/^GRAD-RECON\//, "");
}

export function recBatchState(b: Pick<RecBatch, "closed_at" | "executed_at" | "eligible" | "graduated" | "skipped" | "refused">): [string, Kind] {
  if (b.closed_at) return ["Closed", "grey"];
  if (b.executed_at) return ["Executed", "ok"];
  if (b.graduated + b.skipped + b.refused > 0) return ["Running", "info"];
  return b.eligible ? ["Waiting", "warn"] : ["Nothing eligible", "grey"];
}

export function recOutcome(r: Pick<RecRow, "outcome" | "verdict" | "note" | "corrected_at">): [string, Kind] {
  if (r.corrected_at) return ["Corrected", "info"];
  if (r.outcome === "GRADUATED") return ["Graduated", "ok"];
  if (r.outcome === "SKIPPED") return [r.note ?? "Skipped", "grey"];
  if (r.outcome === "REFUSED") return [`Refused — ${r.note ?? ""}`.trim(), "bad"];
  return r.verdict === "ELIGIBLE" ? ["Waiting", "warn"] : ["Left for review", "warn"];
}

/** the list as exported: S/N comes first from the export itself, never an id */
export const LIST_HEADERS = ["Student", "Matriculation number", "Programme", "Department", "Admission session", "Programme length", "Expected completion",
  "Maximum session", "Sessions beyond", "Confidence", "Reasons"];

export function listRow(c: Candidate): (string | number)[] {
  return [fullName(c), c.matric_no ?? "", c.programme ?? c.programme_code ?? "", c.department ?? "", c.entry_session ?? "",
    c.duration_years ?? "", c.expected_completion ?? "", c.maximum_session ?? "", c.spillover_years, REC_CONFIDENCE[c.confidence]?.[0] ?? c.confidence,
    reasonsOf(c.confidence_reasons).join("; ")];
}
