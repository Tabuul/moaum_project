/**
 * A student's password reset at the ICT Support Desk (V346, V485): the account's state as the desk reads it, the three methods,
 * and the words the desk shows for each outcome. Nothing here holds, shows or stores a password — the reset to the default
 * credential writes nothing about the matriculation number, and a temporary password is shown once by the server's answer.
 */

/** the reset's methods, as the API names them */
export type ResetMethod = "DEFAULT" | "LINK" | "TEMPORARY";

export interface ResetPolicy {
  enabled: boolean;
  unlock_by_default: boolean;
  /** OPTIONAL or REQUIRED */
  ticket: string;
  /** V526: null is no limit (the default) */
  hourly: number | null;
  statuses: string[];
  /** V528: the day's count of one agent's resets at which the Head is told; absent is never (the default) */
  alert_daily?: number | null;
  /** V563: the number of students above which a bulk reset waits for a Head's approval; absent is never */
  bulk_approval_over?: number | null;
}

/** V528: one agent's student password resets, for the Head's oversight (helpdesk.reset_counts) */
export interface AgentResets {
  agent_id: string;
  name: string;
  /** today and the last seven days, Lagos days */
  today: number;
  week: number;
  last_at: string | null;
  /** V563: the students reset in bulk resets today and in the last seven days, and those operations today — apart from the single
   *  resets the alert counts */
  bulk_today?: number;
  bulk_week?: number;
  bulk_ops_today?: number;
}

export interface ResetsByAgent {
  /** absent: no one is told */
  alert_daily?: number | null;
  agents: AgentResets[];
}

/** V528: whether an agent's count today has reached the figure at which the Head is told */
export function pastAlert(a: AgentResets, alertDaily: number | null | undefined): boolean {
  return alertDaily != null && alertDaily > 0 && a.today >= alertDaily;
}

/** V528: an agent's daily average over the last seven days, to one decimal place */
export function weekAverage(a: AgentResets): string {
  return (Math.round((a.week / 7) * 10) / 10).toFixed(1);
}

/** iam.student_reset_check, with the desk's own additions — never a hash, never a password */
export interface ResetState {
  student_id: string;
  full_name: string;
  matric_no: string | null;
  admission_no: string | null;
  jamb_reg_no: string | null;
  faculty: string | null;
  department: string | null;
  programme: string | null;
  current_level: number | null;
  status: string;
  has_account: boolean;
  must_change: boolean;
  temporary: boolean;
  locked: boolean;
  last_signed_in_at: string | null;
  support_reset_at: string | null;
  eligible: boolean;
  refusal: string | null;
  refusalWords?: string;
  username: string | null;
  /** NO_ACCOUNT, CHANGE_REQUIRED or NORMAL */
  passwordStatus: string;
  mayReset: boolean;
  policy: ResetPolicy;
}

/** a reset's reason is written in words, as a fee reversal's is */
export const RESET_REASON_MIN = 10;

export function reasonOk(reason: string): boolean {
  return reason.trim().length >= RESET_REASON_MIN;
}

export const METHOD_WORD: Record<string, string> = {
  DEFAULT_CREDENTIAL: "Default student credential",
  RESET_LINK: "Reset link to the student's email or phone",
  TEMPORARY_PASSWORD: "Temporary password at the desk",
};

export const PASSWORD_STATUS_WORD: Record<string, [string, "ok" | "info" | "grey" | "warn" | "bad"]> = {
  NORMAL: ["Normal", "ok"],
  CHANGE_REQUIRED: ["Password reset required", "warn"],
  NO_ACCOUNT: ["No portal account yet", "grey"],
};

/** the account's state in a few words: locked, no account, active */
export function accountWord(s: Pick<ResetState, "has_account" | "locked" | "status">): [string, "ok" | "info" | "grey" | "warn" | "bad"] {
  if (s.locked) return ["LOCKED (failed sign-ins)", "bad"];
  if (!s.has_account) return ["NOT YET OPENED", "grey"];
  return [s.status === "ACTIVE" ? "ACTIVE" : s.status, s.status === "ACTIVE" ? "ok" : "info"];
}

/** which methods the desk offers: the default credential where the record allows it, the link always, a temporary password on a ticket */
export function methodsFor(s: Pick<ResetState, "eligible">, hasTicket: boolean): { method: ResetMethod; enabled: boolean; why: string | null }[] {
  return [
    { method: "DEFAULT", enabled: s.eligible, why: s.eligible ? null : "Not available for this student" },
    { method: "LINK", enabled: true, why: null },
    { method: "TEMPORARY", enabled: hasTicket, why: hasTicket ? null : "Issued only on the student's ticket" },
  ];
}

export interface ResetProblem { status: number; code?: string; title?: string; detail?: string }

/** the codes whose words are the portal's own, written for the desk: the record, the policy, the desk's rules */
const OWN_REASON = /^(RESET_|SUPPORT_|HELPDESK_|AUTH_)[A-Z_]+$/;

/** the desk's words for a reset that did not go through — the server's own reason where it gave one, never a stack trace */
export function failureWords(p: ResetProblem | null | undefined): string {
  if (!p) return "PASSWORD RESET COULD NOT BE COMPLETED. PLEASE TRY AGAIN OR CONTACT THE ICT DIRECTOR.";
  if (p.status === 404) return "STUDENT ACCOUNT NOT FOUND.";
  if (p.status === 401 || p.status === 403 || p.code === "SUPPORT_CAPABILITY") return "YOU ARE NOT AUTHORIZED TO RESET THIS STUDENT'S PASSWORD.";
  // only the portal's own reasons are shown in its words; anything else (a database or server fault) is said plainly
  if (p.code && OWN_REASON.test(p.code) && p.detail) return p.detail;
  if (p.status === 400) return "SAY WHY THE PASSWORD IS RESET, IN TEN CHARACTERS OR MORE.";
  return "PASSWORD RESET COULD NOT BE COMPLETED. PLEASE TRY AGAIN OR CONTACT THE ICT DIRECTOR.";
}

/** the body the reset is sent with: the method, the reason, the ticket where there is one, and the unlock choice */
export function resetBody(method: ResetMethod, reason: string, ticket: string | null, unlock: boolean): Record<string, unknown> {
  return { method, reason: reason.trim(), ticket: ticket || null, ...(method === "DEFAULT" ? { unlock } : {}) };
}
