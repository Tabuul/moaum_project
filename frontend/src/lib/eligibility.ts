/** Admission eligibility and the course suggestion engine (V266): the shapes the API returns and the words for them. */

export type CheckStatus = "MET" | "NOT_MET" | "UNVERIFIED" | "INFO";
export interface Check { kind: string; label: string; requirement: string; candidate: string; status: CheckStatus; mandatory: boolean }
export type Verdict = "ELIGIBLE" | "ELIGIBLE_SCREENING" | "NOT_ELIGIBLE" | "UNVERIFIED";
export interface ResultRow {
  programme_code: string; programme: string; faculty_code?: string | null; faculty: string | null; department: string | null;
  result: Verdict; checks: string; reasons: string[]; ord?: number;
}
export interface Run {
  id: string; application_id: string; session: string; entry_mode: string; applied_programme_code: string | null; applied_programme: string | null;
  policy_id: string | null; policy_state: string | null; rules_version: number | null; applied_result: Verdict; alternatives: number;
  evaluated_at: string; evaluated_by: string | null; trigger_kind: string; stale: boolean; superseded_at: string | null;
}
export interface ChangeRequest {
  id: string; application_id: string; session: string; from_programme_code: string | null; from_programme: string; to_programme_code: string; to_programme: string;
  eligibility_at_request: string; requested_at: string; requested_by_kind: "APPLICANT" | "OFFICE"; note: string | null; state: "REQUESTED" | "APPROVED" | "REJECTED" | "CANCELLED";
  eligibility_at_decision: string | null; decided_at: string | null; decided_by: string | null; decision_note: string | null; decided_officer?: string | null;
  application_no?: string; surname?: string; other_names?: string; jamb_reg_no?: string; entry_mode?: string;
}
export interface ListRow {
  id: string; application_no: string; submitted_at: string | null; decision: string | null; decision_released_at: string | null;
  surname: string; other_names: string; jamb_reg_no: string; programme: string; entry_mode: string;
  programme_code: string | null; faculty_code: string | null; faculty: string | null; department: string | null;
  run_id: string | null; applied_result: Verdict | null; alternatives: number | null; evaluated_at: string | null; rules_version: number | null; policy_state: string | null; stale: boolean | null;
  reasons: string[] | null; top_alternatives: string | null;
  change_id: string | null; change_to: string | null; change_to_code: string | null; change_state: string | null; change_requested_at: string | null;
}
export interface Stats { evaluated: number; eligible: number; eligible_screening: number; not_eligible: number; unverified: number; with_alternatives: number; without_alternatives: number; change_requests_open: number; not_evaluated: number; stale: number }
export interface Detail {
  application: ListRow; run: Run; applied: ResultRow | null; alternatives: ResultRow[]; changes: ChangeRequest[];
  events?: { action: string; programme_code: string | null; result: string | null; detail: string | null; actor_office: string | null; at: string; actor: string | null }[];
  olevel?: { exam_body: string; exam_year: string | null; exam_number: string | null; subjects: string }[];
  utme?: { aggregate: number | null; subjects: string | null } | null;
  available?: boolean; note?: string; canRequestChange?: boolean;
}

export const VERDICT: Record<Verdict, [string, "ok" | "warn" | "bad" | "grey" | "info"]> = {
  ELIGIBLE: ["ELIGIBLE", "ok"], ELIGIBLE_SCREENING: ["ACADEMICALLY ELIGIBLE — ADDITIONAL SCREENING REQUIRED", "warn"],
  NOT_ELIGIBLE: ["NOT ELIGIBLE", "bad"], UNVERIFIED: ["PENDING VERIFICATION", "info"],
};
export const KIND_WORD: Record<string, string> = {
  POLICY: "Admission settings", PROGRAMME: "Programme", OLEVEL: "O'Level result", OLEVEL_SITTINGS: "O'Level sittings", OLEVEL_COMPULSORY: "Compulsory O'Level credit",
  OLEVEL_REQUIRED: "Required O'Level subject", OLEVEL_CREDITS: "O'Level credits", UTME_COMBINATION: "UTME subject combination", UTME_SCORE: "UTME score",
  DE_COMBINATION: "Direct Entry subjects", SCREENING: "Additional screening",
};
export const GROUPS: [string, string[]][] = [
  ["O'Level requirements", ["OLEVEL", "OLEVEL_SITTINGS", "OLEVEL_COMPULSORY", "OLEVEL_REQUIRED", "OLEVEL_CREDITS"]],
  ["UTME requirements", ["UTME_COMBINATION"]], ["UTME score", ["UTME_SCORE"]], ["Direct Entry requirements", ["DE_COMBINATION"]],
  ["The programme", ["PROGRAMME", "POLICY", "SCREENING"]],
];
export function parseChecks(row: ResultRow | null | undefined): Check[] {
  if (!row) return [];
  try { return JSON.parse(row.checks) as Check[]; } catch { return []; }
}
export const mark = (s: CheckStatus) => (s === "MET" ? "✓" : s === "NOT_MET" ? "✕" : s === "UNVERIFIED" ? "?" : "·");
/** the three headline ticks a suggestion row shows: O'Level, UTME/DE combination, score */
export function headline(checks: Check[]): { olevel: CheckStatus; combination: CheckStatus; score: CheckStatus } {
  const worst = (kinds: string[]): CheckStatus => {
    const cs = checks.filter((c) => kinds.includes(c.kind) && c.status !== "INFO");
    if (!cs.length) return "INFO";
    if (cs.some((c) => c.status === "NOT_MET")) return "NOT_MET";
    if (cs.some((c) => c.status === "UNVERIFIED")) return "UNVERIFIED";
    return "MET";
  };
  return { olevel: worst(["OLEVEL", "OLEVEL_COMPULSORY", "OLEVEL_REQUIRED", "OLEVEL_CREDITS"]), combination: worst(["UTME_COMBINATION", "DE_COMBINATION"]), score: worst(["UTME_SCORE"]) };
}
export const dayOf = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }) : "—");
export const whenAt = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
