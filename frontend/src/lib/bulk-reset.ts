/**
 * Bulk password reset (V559, V563): the operation as the API gives it, its states in words, and the few rules the screens apply —
 * which students may be sent the reset link (refused for want of a matriculation number, no link yet), which are tried again (those
 * not reset), whether the operation will wait for a Head's approval, and (V565) a request of more than 1,000 students opened as parts
 * run one after another, read as a whole. No password is ever in any of it.
 */

export type Tone = "grey" | "info" | "ok" | "bad" | "warn";

export interface DeskSummary {
  loginIssues: number; resetsToday: number; bulkToday: number; studentsResetToday: number; failedToday: number;
  /** V563: for a Head, those others asked for; for an agent, their own */
  awaitingApproval?: number;
  /** V563: the number of students above which a bulk reset waits for approval; null, never */
  approvalOver?: number | null;
  mayBulk: boolean; scope: string | null;
}

export interface BulkRow {
  id: string; reference: string; created_at: string; performed_by: string; office: string; reason: string; total: number; succeeded: number; failed: number;
  status: string; completed_at: string | null; tickets: string | null;
  /** V565: the part of a request of more than 1,000 students */
  part?: number | null; parts?: number | null;
}
export interface BulkHistory { total: number; page: number; size: number; rows: BulkRow[]; everyone: boolean }

export interface PreviewRow { student_id: string; full_name: string | null; matric_no: string | null; programme: string | null; current_level: number | null; status: string | null; eligible: boolean; code: string; words: string }
export interface Preview {
  selected: number; eligible: number; notEligible: number; rows: PreviewRow[];
  policy: { ticket: string; unlock_by_default: boolean; approval_over?: number | null };
}

export interface OpItem {
  student_id: string; name: string; number: string | null; programme: string | null; faculty: string | null; level: number | null; status: string;
  failure_code: string | null; failure_words: string | null; ticket_number: string | null; ticket_id?: string | null; processed_at?: string | null;
  /** V563 */
  ticket_resolved_at?: string | null; link_sent_at?: string | null; link_to?: string | null; link_failure?: string | null;
}
export interface Operation {
  id: string; reference: string; status: string; total: number; succeeded: number; failed: number; processed: number; reason: string; performed_by: string;
  office?: string | null; created_at: string; completed_at: string | null; items?: OpItem[]; missing?: number; repeat?: boolean;
  /** V563 */
  resolve_tickets?: boolean; resolution?: string | null; retry_of?: string | null; retry_of_reference?: string | null; approval_over?: number | null;
  decided_by?: string | null; decided_at?: string | null; decision_note?: string | null;
  retries?: { id: string; reference: string; status: string; created_at: string }[]; mayDecide?: boolean; mayAct?: boolean;
  /** V565: a request of more than 1,000 students — this part, and every part with its counts */
  series_id?: string | null; part?: number | null; parts?: number | null; series?: SeriesPart[];
}
export interface SeriesPart { id: string; reference: string; part: number; status: string; total: number; succeeded: number; failed: number; processed: number; completed_at: string | null }

export const STATUS: Record<string, [string, Tone]> = {
  AWAITING_APPROVAL: ["Waiting for approval", "warn"], PENDING: ["Pending", "grey"], PROCESSING: ["Processing", "info"], COMPLETED: ["Completed", "ok"],
  COMPLETED_WITH_EXCEPTIONS: ["Completed with exceptions", "warn"], FAILED: ["Failed", "bad"], CANCELLED: ["Cancelled", "grey"], REJECTED: ["Declined", "bad"],
};

/** the result dialog's title once an operation has ended */
export const DONE: Record<string, string> = {
  COMPLETED: "Password reset completed", COMPLETED_WITH_EXCEPTIONS: "Password reset completed with exceptions", FAILED: "Password reset failed — no student was reset",
  CANCELLED: "Password reset cancelled", REJECTED: "Password reset declined",
};

/** V565: students one request resets at most (the server's limit), and in one operation — a larger request is opened as parts */
export const MAX = 10000;
export const PART = 1000;

/** the parts a request of n students is opened as */
export function partsOf(n: number): number {
  return Math.max(1, Math.ceil(n / PART));
}

/** a request read as a whole: one operation's counts, or the sum of its parts', and whether any part still runs or waits */
export function whole(op: Pick<Operation, "status" | "total" | "succeeded" | "failed" | "processed" | "series">) {
  const parts = op.series?.length ? op.series : [op];
  const sum = (k: "total" | "succeeded" | "failed" | "processed") => parts.reduce((n, p) => n + Number(p[k] ?? 0), 0);
  return {
    total: sum("total"), succeeded: sum("succeeded"), failed: sum("failed"), processed: sum("processed"), parts: parts.length,
    running: parts.some((p) => running(p.status)), waiting: parts.some((p) => p.status === "AWAITING_APPROVAL"),
  };
}

/** what the students read on their resolved login ticket, unless the agent words it otherwise */
export const DEFAULT_RESOLUTION = "Your portal password has been reset by ICT Support. Sign in with your matriculation number as your username and as your password; "
  + "the portal will ask you at once to choose your own password. If you still cannot sign in, reopen this ticket and say what happens.";

/** an operation the server is still working through (its progress is read until it ends) */
export function running(status: string): boolean {
  return status === "PENDING" || status === "PROCESSING";
}

/** whether an operation of n students will wait for a Head's approval */
export function needsApproval(n: number, over: number | null | undefined): boolean {
  return over != null && over > 0 && n > over;
}

/** the students refused for want of a matriculation number, not yet sent the reset link */
export function linkable(items: OpItem[]): OpItem[] {
  return items.filter((i) => i.status === "FAILED" && i.failure_code === "RESET_NO_MATRIC" && !i.link_sent_at);
}

/** the students an operation did not reset, to try again — never those who have since been sent a link instead */
export function notReset(items: OpItem[]): OpItem[] {
  return items.filter((i) => i.status === "FAILED" && !i.link_sent_at);
}

/** the login tickets of the students given, by student, for a retry that files the resets on them again */
export function ticketsOf(items: OpItem[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (const i of items) if (i.ticket_id) out[i.student_id] = i.ticket_id;
  return out;
}

/** one student's result in words, for the screen and the Excel */
export function resultWord(i: OpItem): string {
  if (i.status === "RESET") return "Reset";
  if (i.status === "ALREADY_RESET") return "Already reset";
  if (i.status === "PENDING") return "Waiting";
  return i.link_sent_at ? "Reset link sent" : "Not reset";
}

/** why a student was not reset, and what was done about it since */
export function resultNote(i: OpItem): string {
  const parts: string[] = [];
  if (i.failure_words) parts.push(i.failure_words);
  if (i.link_sent_at) parts.push(`Reset link sent to ${i.link_to ?? "the record's address"}`);
  else if (i.link_failure) parts.push(`No link sent: ${i.link_failure}`);
  if (i.ticket_resolved_at) parts.push("Ticket resolved");
  return parts.join(" · ");
}
