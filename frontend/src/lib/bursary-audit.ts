/**
 * The Bursary's audit trail and its users on the Bursar's dashboard: the words for what was done, on which kind of record, and
 * what changed, as the screen and the Excel copy show them. The server reads the trail (/finance/bursary/audit, /users).
 */

export interface BursaryUser {
  person_id: string; name: string; staff_number: string | null; email: string | null; phone: string | null;
  office_code: string; office: string; scope_kind: string; scope_id: string | null; valid_from: string; valid_to: string | null; instrument: string | null;
  in_post: boolean; username: string | null; last_sign_in_at: string | null; locked: boolean | null; must_change: boolean | null;
  changes_30d: number; last_change_at: string | null; failed_sign_ins_30d: number;
}

export interface TrailChange { field: string; before: unknown; after: unknown }

export interface TrailRow {
  at: string; kind: "CHANGE" | "SIGN_IN"; person_id: string; name: string | null; office: string | null; action: string;
  subject_type: string; subject_id: string; reason: string | null; source_ip: string | null;
  changes: TrailChange[] | null; summary: Record<string, unknown>;
}

export interface TrailPage {
  tiles: { changes: number; changes_today: number; sign_ins: number; failed_sign_ins: number; people: number };
  subjects: { subject_type: string; n: number }[];
  total: number; page: number; size: number; rows: TrailRow[];
}

const ACTION: Record<string, string> = {
  INSERT: "Added", UPDATE: "Changed", DELETE: "Removed",
  SIGNED_IN: "Signed in", SIGNED_OUT: "Signed out", BAD_PASSWORD: "Wrong password", LOCKED: "Account locked",
  MUST_CHANGE: "Signed in (password to change)", ENDED: "Session ended", UNKNOWN: "Unknown username",
};

/** the kinds of record the Bursary works on, in words; any other reads from its table name */
const SUBJECT: Record<string, string> = {
  "finance.fee_schedule": "Fee line",
  "finance.payment_reference": "Payment",
  "finance.refund": "Refund",
  "finance.bank_credit": "Bank credit",
  "finance.clearance_scheme": "Clearance scheme",
  "finance.legacy_fee_upload": "Old fees upload",
  "finance.legacy_fee_upload_part": "Old fees upload rows",
  "finance.legacy_item_code": "Old portal item code",
  "finance.legacy_payref": "Old portal payment number",
  "finance.overpayment": "Overpayment decision",
  "finance.payment_swap": "Payment swap",
  "people.student": "Student record",
  "people.cohort_decision": "Level decision",
  "helpdesk.support_action": "Support action",
  sign_in: "Sign-in",
};

export function actionWord(action: string): string {
  return ACTION[action] ?? action.replace(/_/g, " ").toLowerCase().replace(/^./, (c) => c.toUpperCase());
}

export function subjectWord(subject: string): string {
  if (SUBJECT[subject]) return SUBJECT[subject];
  const table = subject.includes(".") ? subject.slice(subject.indexOf(".") + 1) : subject;
  const w = table.replace(/_/g, " ");
  return w.charAt(0).toUpperCase() + w.slice(1);
}

/** a value as the trail shows it: text as it is, numbers and flags plainly, anything longer cut at 60 characters */
export function valueWord(v: unknown): string {
  if (v === null || v === undefined) return "—";
  const s = typeof v === "string" ? v : typeof v === "number" || typeof v === "boolean" ? String(v) : JSON.stringify(v);
  return s.length > 60 ? `${s.slice(0, 57)}…` : s;
}

const field = (k: string) => k.replace(/_/g, " ");

/** what changed on the record ("amount: 100000 → 120000"), or for a record added or removed its key facts ("item: School fees") */
export function changeLines(r: Pick<TrailRow, "kind" | "changes" | "summary">): string[] {
  if (r.kind !== "CHANGE") return [];
  if (r.changes && r.changes.length) return r.changes.map((c) => `${field(c.field)}: ${valueWord(c.before)} → ${valueWord(c.after)}`);
  return Object.entries(r.summary ?? {}).slice(0, 6).map(([k, v]) => `${field(k)}: ${valueWord(v)}`);
}

export const TRAIL_HEADERS = ["When", "Who", "Office", "What", "Record", "Details", "Reason", "From"];

/** a row of the Excel copy, in the order of TRAIL_HEADERS */
export function trailRow(r: TrailRow, officeLabel: (code: string | null) => string, when: (s: string) => string): string[] {
  return [when(r.at), r.name ?? "", r.kind === "SIGN_IN" ? "" : officeLabel(r.office), actionWord(r.action), r.kind === "SIGN_IN" ? "" : subjectWord(r.subject_type),
    changeLines(r).join("; "), r.reason ?? "", r.source_ip ?? ""];
}
