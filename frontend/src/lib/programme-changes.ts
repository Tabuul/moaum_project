/** Programme Changes (V297): the register's rows as the API gives them — every applicant now on a programme other than the one
 *  applied for — and the words, filters and export the screen reads them with. The API leaves out a field that is null, so every
 *  optional field here is read with == null, never === null. Pure: the screen and the tests share it. */
import { money } from "./format.ts";

export type ChangeStage = "BEFORE_DECISION" | "APPLICANT_REQUEST" | "SCREENING" | "CORRECTION";
export type Route = "CHANGE" | "CORRECTION" | "TRANSFER" | "CLOSED";
export type Tone = "grey" | "info" | "ok" | "bad" | "warn";

export interface RegisterRow {
  application_id: string; application_no: string; jamb_reg_no: string; surname: string; other_names: string; entry_mode: string;
  applied_code?: string | null; applied_programme?: string | null; applied_faculty?: string | null; applied_department?: string | null;
  current_code?: string | null; current_programme: string; current_faculty?: string | null; current_department?: string | null;
  moved?: boolean | null; changes: number; change_id: string; kind: "CHANGE" | "CORRECTION"; stage: ChangeStage;
  reason_code?: string | null; reason?: string | null; note?: string | null;
  requested_by_kind?: string | null; recommended_office?: string | null; recommended_by?: string | null; requested_at?: string | null;
  decided_at?: string | null; decided_by?: string | null; decided_office?: string | null; decision_note?: string | null;
  override?: boolean | null; override_reason?: string | null; eligibility?: string | null; stage_then?: string | null; stage_now?: string | null;
  fee_session?: string | null; fees_paid?: number | null; fees_due_before?: number | null; fees_due_after?: number | null; paid_now?: number | null; due_now?: number | null;
  registrations_returned?: number | null; courses_dropped?: number | null; matric_rows_dropped?: number | null; letter_reissued?: boolean | null; forms_reissued?: boolean | null;
  history?: string | null;
}

export interface PendingRow {
  id: string; application_id: string; kind: "CHANGE" | "CORRECTION"; from_programme: string; from_programme_code?: string | null; to_programme: string; to_programme_code: string;
  reason_code?: string | null; reason?: string | null; note?: string | null; requested_by_kind: string; recommended_office?: string | null; requested_at: string;
  override?: boolean | null; override_reason?: string | null; eligibility_at_request?: string | null; admission_stage?: string | null; screening_state_at_request?: string | null;
  application_no: string; surname: string; other_names: string; jamb_reg_no: string; entry_mode: string; recommended_by?: string | null; mine?: boolean | null;
}

export interface ReasonOpt { code: string; label: string; ord: number; requires_note: boolean }
export interface ProgrammeOpt { code: string; name: string; faculty?: string | null; department?: string | null }
export interface SessionOpt { name: string; applications: number; changed: number }
export interface RegisterPage { session: string; rows: RegisterRow[]; pending: PendingRow[]; reasons: ReasonOpt[]; programmes: ProgrammeOpt[]; sessions: SessionOpt[] }
export interface FindRow {
  id: string; application_no: string; jamb_reg_no: string; surname: string; other_names: string; programme: string; entry_mode: string;
  decision?: string | null; decision_released_at?: string | null; route: Route; stage: string; detail: string;
}
export interface Preview {
  applicationId: string; applicationNo: string; jambRegNo: string; name: string; entryMode: string; session: string;
  route: Route; stage: string; detail: string;
  current: { code?: string | null; name: string; faculty?: string | null; department?: string | null };
  student?: { id: string; admissionNo?: string | null; matricNo?: string | null } | null;
  registrations?: { session: string; semester: number; status: string; courses: number }[];
  matricRows?: number; letterIssued?: boolean; formsIssued?: boolean;
  openRequest?: { id: string; kind: string; to: string; requestedAt: string } | null;
  fees?: { session: string; paid: number; dueNow: number; balanceNow: number; excessNow: number; dueAfter?: number; balanceAfter?: number; excessAfter?: number } | null;
  target?: { code: string; name: string; faculty?: string | null; department?: string | null; archived?: boolean; result: string; reasons?: string[] } | null;
}
export interface HistoryItem {
  id: string; kind: string; stage: ChangeStage; from: string; to: string; reason?: string | null; note?: string | null; recommendedOffice?: string | null;
  requestedAt?: string | null; decidedAt?: string | null; decidedOffice?: string | null; override?: boolean | null; overrideReason?: string | null;
}

export const STAGE_WORD: Record<ChangeStage, [string, Tone]> = {
  BEFORE_DECISION: ["Before the decision", "grey"],
  APPLICANT_REQUEST: ["Applicant’s request", "info"],
  SCREENING: ["At screening", "info"],
  CORRECTION: ["Admission correction", "warn"],
};
export const ROUTE_WORD: Record<Route, [string, Tone]> = {
  CHANGE: ["Ordinary change", "info"],
  CORRECTION: ["Admission correction", "warn"],
  TRANSFER: ["Inter-departmental transfer", "grey"],
  CLOSED: ["No admission to correct", "grey"],
};
const ADMISSION_WORD: Record<string, string> = {
  AWAITING_DECISION: "Awaiting the decision", NOT_OFFERED: "Not offered", DECLINED: "Offer declined", OFFERED: "Offered, not yet accepted",
  ACCEPTED: "Accepted", SCREENED: "Screened successful", ON_REGISTER: "On the register", SCHOOL_FEES_PAID: "School fees paid",
  COURSES_REGISTERED: "Courses registered", MATRICULATED: "Matriculated",
};
const OFFICE_WORD: Record<string, string> = {
  academic: "Academic Office", registrar: "Registrar", dregistrar: "Deputy Registrar", vc: "Vice-Chancellor’s office", dvc: "DVC’s office", super: "Super Administrator",
};

export const stageWord = (s: string | null | undefined): string => (s == null ? "—" : (STAGE_WORD as Record<string, [string, Tone]>)[s]?.[0] ?? s.replace(/_/g, " ").toLowerCase());
export const admissionWord = (s: string | null | undefined): string => (s == null ? "—" : ADMISSION_WORD[s] ?? s.replace(/_/g, " ").toLowerCase());
export const officeWord = (s: string | null | undefined): string => (s == null ? "—" : OFFICE_WORD[s] ?? s);
export const name = (r: { surname: string; other_names: string }) => `${r.surname}, ${r.other_names}`;

/** the day in Lagos, as YYYY-MM-DD, for the date filters */
export function lagosDay(iso: string | null | undefined): string {
  if (iso == null || iso === "") return "";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Africa/Lagos", year: "numeric", month: "2-digit", day: "2-digit" }).format(d);
}

/** the fee position a correction recorded: paid, due on the new programme, and the balance to pay or the excess — "" when it recorded none */
export function feeWord(r: { fees_paid?: number | null; fees_due_after?: number | null }): string {
  if (r.fees_paid == null || r.fees_due_after == null) return "";
  const paid = Number(r.fees_paid), due = Number(r.fees_due_after);
  const tail = due > paid ? `balance ${money(due - paid)}` : paid > due ? `excess ${money(paid - due)}` : "settled";
  return `Paid ${money(paid)} · due ${money(due)} · ${tail}`;
}

/** what the Bursary still has to follow up on a correction today: a balance the student owes, or an excess to credit or refund */
export function feeFollowUp(r: RegisterRow): "BALANCE" | "EXCESS" | null {
  if (r.kind !== "CORRECTION" || r.paid_now == null || r.due_now == null || r.fees_paid == null) return null;
  const paid = Number(r.paid_now), due = Number(r.due_now);
  if (paid > due) return "EXCESS";
  if (due > paid && paid > 0) return "BALANCE";
  return null;
}

export function parseHistory(text: string | null | undefined): HistoryItem[] {
  if (text == null || text === "") return [];
  try {
    const x = JSON.parse(text) as unknown;
    return Array.isArray(x) ? (x as HistoryItem[]) : [];
  } catch {
    return [];
  }
}

export interface RegisterFilter { stage: string; reason: string; faculty: string; applied: string; q: string; from: string; to: string }
export const NO_FILTER: RegisterFilter = { stage: "", reason: "", faculty: "", applied: "", q: "", from: "", to: "" };

export function filterRows(rows: RegisterRow[], f: RegisterFilter): RegisterRow[] {
  const needle = f.q.trim().toLowerCase();
  return rows.filter((r) => {
    if (f.stage && r.stage !== f.stage) return false;
    if (f.reason && r.reason_code !== f.reason) return false;
    if (f.faculty && r.current_faculty !== f.faculty) return false;
    if (f.applied && r.applied_code !== f.applied) return false;
    const day = lagosDay(r.decided_at);
    if (f.from && (!day || day < f.from)) return false;
    if (f.to && (!day || day > f.to)) return false;
    if (needle) {
      const hay = `${r.surname} ${r.other_names} ${r.jamb_reg_no} ${r.application_no} ${r.applied_programme ?? ""} ${r.current_programme} ${r.reason ?? ""} ${r.note ?? ""}`.toLowerCase();
      if (!hay.includes(needle)) return false;
    }
    return true;
  });
}

/** the tiles: how many moved, at which stage, and what still waits */
export function tally(rows: RegisterRow[]) {
  const by = (s: ChangeStage) => rows.filter((r) => r.stage === s).length;
  return {
    applicants: rows.length,
    beforeDecision: by("BEFORE_DECISION") + by("APPLICANT_REQUEST"),
    screening: by("SCREENING"),
    corrections: by("CORRECTION"),
    overrides: rows.filter((r) => r.override === true).length,
    followUp: rows.filter((r) => feeFollowUp(r) != null).length,
  };
}

export const EXPORT_HEAD = ["S/N", "Applicant", "JAMB No.", "Application No.", "Programme Applied For", "Faculty (Applied)", "Programme Now", "Faculty (Now)",
  "Reason", "Note", "Stage", "Recommended By", "Approved By", "Approved On", "Admission Now", "School Fees"];

export function exportBody(rows: RegisterRow[]): (string | number)[][] {
  return rows.map((r, i) => [
    i + 1, name(r), r.jamb_reg_no, r.application_no, r.applied_programme ?? "", r.applied_faculty ?? "", r.current_programme, r.current_faculty ?? "",
    r.reason ?? "", r.note ?? "", stageWord(r.stage),
    r.requested_by_kind === "APPLICANT" ? "The applicant" : [officeWord(r.recommended_office), r.recommended_by ?? ""].filter((x) => x && x !== "—").join(" · "),
    [officeWord(r.decided_office), r.decided_by ?? ""].filter((x) => x && x !== "—").join(" · "),
    lagosDay(r.decided_at), admissionWord(r.stage_now), feeWord(r),
  ]);
}
