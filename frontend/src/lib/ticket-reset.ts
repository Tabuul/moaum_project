/** V582: password resets from support tickets — the shapes the API answers with, the words for where a ticket stands, the
 *  selection the desk keeps (ticket ids only, never a student). Node-tested. */

/** where a ticket stands for a reset from tickets (the queue's reset_state) */
export type ResetState = "ELIGIBLE" | "FAILED_BEFORE" | "IN_OPERATION" | "RESET_DONE" | "SETTLED" | "NOT_STUDENT" | "NO_STUDENT";

export const RESET_STATE: Record<ResetState, { label: string; tone: "ok" | "info" | "warn" | "bad" | "grey"; selectable: boolean }> = {
  ELIGIBLE: { label: "Eligible for password reset", tone: "ok", selectable: true },
  FAILED_BEFORE: { label: "Eligible — an earlier reset failed", tone: "warn", selectable: true },
  IN_OPERATION: { label: "In a password reset", tone: "info", selectable: false },
  RESET_DONE: { label: "Password reset completed", tone: "ok", selectable: false },
  SETTLED: { label: "Not eligible — resolved or closed", tone: "grey", selectable: false },
  NOT_STUDENT: { label: "Not eligible — not a student's", tone: "grey", selectable: false },
  /** V594: asked from the sign-in page with a number no student holds (or about another portal) */
  NO_STUDENT: { label: "Not eligible — no student holds the number given", tone: "grey", selectable: false },
};

/** a ticket the desk may tick for a reset; a row of another category has no state and is never ticked */
export const selectable = (state: string | null | undefined) => !!state && !!RESET_STATE[state as ResetState]?.selectable;

export interface CheckRow {
  ticket_id: string; number: string | null; category_code: string | null; category: string | null; ticket_status: string | null; subject: string | null;
  created_at: string | null; student_id: string | null; full_name: string | null; matric_no: string | null; faculty: string | null; department: string | null;
  programme: string | null; current_level: number | null; eligible: boolean; code: string; student_status: string | null; words: string;
}
export interface Validation {
  selected: number; eligible: number; students: number; consolidated: number; alreadyDone: number; notEligible: number;
  grouped: { student_id: string; full_name: string | null; matric_no: string | null; tickets: string[] }[];
  rows: CheckRow[]; policy: { enabled: boolean; unlock_by_default: boolean; approval_over: number | null }; resolution: string;
}
export interface OpTicket {
  ticket_id: string; number: string; subject: string; category: string; ticket_status: string; student_id: string | null; full_name: string | null; matric_no: string | null;
  status: "PENDING" | "RESOLVED" | "UNRESOLVED" | "FAILED"; student_result: string; reason: string | null; processed_at: string | null; part: string;
}
export interface Operation {
  id: string; reference: string; status: string; total: number; succeeded: number; failed: number; reason: string; resolution: string | null;
  created_at: string; started_at: string | null; completed_at: string | null; performed_by: string | null; approval_over: number | null; processed: number;
  tickets: OpTicket[]; ticketCount: number; students: number; consolidated: number; resolved: number; failedTickets: number; pendingTickets: number;
}
export interface Summary {
  may: boolean;
  figures: {
    open: number; unassigned: number; inProgress: number; students: number; inOperation: number; failed: number; overdue: number; resetToday: number;
    /** V594: the requests from the sign-in page, and those whose number no student holds */
    public?: number; unmatched?: number;
  };
  categories: { code: string; name: string }[];
}

/** the operation is still running (the screen keeps reading its progress) */
export const running = (status: string | null | undefined) => status === "PENDING" || status === "PROCESSING";

export const OP_STATUS: Record<string, [string, "ok" | "info" | "warn" | "bad" | "grey"]> = {
  AWAITING_APPROVAL: ["Waiting for a Head's approval", "warn"], PENDING: ["Starting", "info"], PROCESSING: ["Resetting", "info"],
  COMPLETED: ["Completed", "ok"], COMPLETED_WITH_EXCEPTIONS: ["Completed with exceptions", "warn"], FAILED: ["Failed", "bad"],
  CANCELLED: ["Cancelled", "grey"], REJECTED: ["Not approved", "bad"],
};

export const TICKET_RESULT: Record<OpTicket["status"], [string, "ok" | "info" | "warn" | "bad" | "grey"]> = {
  PENDING: ["Waiting", "info"], RESOLVED: ["Reset — ticket resolved", "ok"], UNRESOLVED: ["Reset — ticket settled already", "ok"], FAILED: ["Not reset", "bad"],
};

/** the selection: ticked or unticked; every selectable row of the page ticked; the server's ids for every filtered eligible ticket */
export function toggle(sel: Set<string>, id: string, on: boolean): Set<string> {
  const n = new Set(sel);
  if (on) n.add(id); else n.delete(id);
  return n;
}
export function tickPage(sel: Set<string>, rows: { id: string; reset_state?: string | null }[], on: boolean): Set<string> {
  const n = new Set(sel);
  for (const r of rows) if (selectable(r.reset_state)) { if (on) n.add(r.id); else n.delete(r.id); }
  return n;
}

/** progress in words: "37 / 100 students · 35 reset · 2 not reset" */
export function progressWords(op: Pick<Operation, "processed" | "students" | "succeeded" | "failed">): string {
  return `${op.processed} / ${op.students} student${op.students === 1 ? "" : "s"} · ${op.succeeded} reset · ${op.failed} not reset`;
}
