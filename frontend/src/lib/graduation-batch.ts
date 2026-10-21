/**
 * V602: graduation batches — the Academic Office confirms awards on the Senate's minute for chosen students: the preview's verdicts in
 * words, the tally the officer confirms on, the batch reference, and the outcome words. The server decides everything; this only says it.
 */
export type Kind = "ok" | "warn" | "bad" | "info";

export interface Verdict {
  studentId: string; number: string | null; jambNo: string | null; name: string; programmeCode: string | null; programme: string | null;
  faculty: string | null; department: string | null; level: number | null; finalLevel: number | null; durationYears: number | null;
  entrySession: string | null; status: string; verdict: string; confidence: string | null; reason: string | null; completion: string | null;
  spilloverState: string | null; graduandState: string | null; recommendation: string | null; reviewState: string | null;
}

export interface BatchRow {
  student_id: string; number: string; name: string; programme: string | null; level: number; status: string; verdict: string;
  confidence: string | null; reason: string | null; outcome: string | null; graduated_at: string | null; graduand_id: string | null;
}

export interface Batch {
  batch_ref: string; session: string; senate_minute: string; reason: string; scope: string; selected: number; eligible: number; graduated: number;
  rejected: number; review: number; created_at: string; executed_at: string | null; closed_at: string | null; actor_office: string;
  created_by_name?: string; waiting?: number; rows?: BatchRow[];
}

export interface Figures {
  students: number; in_study: number; graduated_all: number; graduated_session: number; candidates: number; candidates_high: number; candidates_low: number;
  sp1: number; sp2: number; maximum: number; requires_review: number; data_incomplete: number; deferred: number; carry_over: number;
  outstanding_result: number; completed: number; listed_met: number; listed_unmet: number; approved: number; referred: number;
  clearance_completed: number; clearance_pending: number; completion_checked_at: string | null; recommendation_computed_at: string | null;
}

export interface Management { session: string; figures: Figures; batches: Batch[] }

/** each verdict: the words, the kind, and whether the batch graduates it */
export const VERDICT: Record<string, [string, Kind]> = {
  ELIGIBLE: ["Eligible", "ok"],
  ALREADY_GRADUATED: ["Already graduated", "info"],
  CARRY_OVER: ["Carry-over owed", "bad"],
  OUTSTANDING_RESULT: ["Result awaited", "warn"],
  NOT_FINAL_LEVEL: ["Final level not reached", "warn"],
  NO_RESULT: ["No published result", "warn"],
  REQUIREMENT_UNMET: ["Requirement unmet", "bad"],
  DEFERRED: ["Deferred", "info"],
  SUSPENDED: ["Suspended", "bad"],
  WITHDRAWN: ["Withdrawn", "bad"],
  DISCONTINUED: ["Discontinued", "bad"],
  NOT_ELIGIBLE_STATUS: ["Not in study", "bad"],
  REFERRED_BY_SENATE: ["Referred by Senate", "bad"],
  DATA_INCOMPLETE: ["Data incomplete", "warn"],
  REQUIRES_REVIEW: ["Requires review", "warn"],
};

export function verdictWord(v: string): string {
  return VERDICT[v]?.[0] ?? v.toLowerCase().replace(/_/g, " ").replace(/^./, (c) => c.toUpperCase());
}

export function verdictKind(v: string): Kind {
  return VERDICT[v]?.[1] ?? "info";
}

export const CONFIDENCE: Record<string, [string, Kind]> = { HIGH: ["High", "ok"], MEDIUM: ["Medium", "warn"], LOW: ["Low", "bad"] };

/** the outcome of the execution for a row, in words */
export function outcomeWord(row: { outcome: string | null; verdict: string; reason: string | null }): [string, Kind] {
  if (row.outcome === "GRADUATED") return ["Graduated", "ok"];
  if (row.outcome === "ALREADY_GRADUATED") return ["Already graduated", "info"];
  if (row.outcome === "REFUSED") return [`Refused — ${row.reason ?? ""}`.trim(), "bad"];
  if (row.verdict === "ELIGIBLE") return ["Waiting", "warn"];
  return [verdictWord(row.verdict), verdictKind(row.verdict)];
}

/** the tally the officer confirms on: how many of each verdict, the eligible first */
export interface Tally { selected: number; eligible: number; review: number; alreadyGraduated: number; notEligible: number; byVerdict: [string, number][] }

export function tally(rows: { verdict: string }[]): Tally {
  const by = new Map<string, number>();
  for (const r of rows) by.set(r.verdict, (by.get(r.verdict) ?? 0) + 1);
  const order = Object.keys(VERDICT);
  const byVerdict = [...by.entries()].sort((a, b) => (order.indexOf(a[0]) === -1 ? 99 : order.indexOf(a[0])) - (order.indexOf(b[0]) === -1 ? 99 : order.indexOf(b[0])));
  const eligible = by.get("ELIGIBLE") ?? 0;
  const review = by.get("REQUIRES_REVIEW") ?? 0;
  const alreadyGraduated = by.get("ALREADY_GRADUATED") ?? 0;
  return { selected: rows.length, eligible, review, alreadyGraduated, notEligible: rows.length - eligible - review - alreadyGraduated, byVerdict };
}

/** the sentence above CONFIRM & GRADUATE */
export function confirmWords(t: Tally, session: string): string {
  const n = t.eligible;
  if (n === 0) return `No student among the ${t.selected} chosen is eligible: nothing will be graduated.`;
  const left = t.selected - n;
  return `You are about to confirm the award of ${n} student${n === 1 ? "" : "s"} for ${session} on the Senate's minute${left ? `; ${left} of the ${t.selected} chosen ${left === 1 ? "is" : "are"} left out (${t.review ? `${t.review} requiring review, ` : ""}${t.alreadyGraduated ? `${t.alreadyGraduated} already graduated, ` : ""}${t.notEligible} not eligible)` : ""}. Each record is revalidated as it is graduated; nothing on it is deleted.`;
}

/** GRAD/2026/000001 → the path parts */
export function batchPath(ref: string): string | null {
  const m = /^GRAD\/(\d{4})\/(\d{6})$/.exec(ref);
  return m ? `${m[1]}/${m[2]}` : null;
}

/** the batch's standing in a word */
export function batchState(b: { closed_at: string | null; executed_at: string | null; waiting?: number; eligible: number }): [string, Kind] {
  if (b.closed_at) return ["Closed", "info"];
  if (b.executed_at && !(b.waiting ?? 0)) return ["Executed", "ok"];
  if ((b.waiting ?? 0) > 0 && (b.waiting ?? 0) < b.eligible) return ["In progress", "warn"];
  return ["Opened", "warn"];
}

export const REPORT_BY: [string, string][] = [
  ["faculty", "Faculty"], ["department", "Department"], ["programme", "Programme"], ["entry", "Year of entry"], ["matric", "Matriculation year"],
  ["session", "Graduation session"], ["spillover", "Spillover state at graduation"],
];
