/**
 * School fees payment swap (V527): the words and shapes the swap screens share. Every figure, state and refusal is the server's
 * (finance.payment_swap_check, finance.decide_payment_swap); these only say them.
 */

export type SwapStatus = "PENDING_APPROVAL" | "COMPLETED" | "REJECTED" | "CANCELLED" | "FAILED" | "REVERSED";

export interface SwapAccount { due: number; paid: number; balance: number; clearsRegistration?: boolean | null; clearsExamination?: boolean | null }

/** a clearance as said: null (the API omits it) where no clearance scheme is in force */
export function clearsWord(v: boolean | null | undefined): string {
  return v == null ? "No clearance scheme" : v ? "Yes" : "No";
}

export interface SwapProfile {
  id: string; name: string; matric_no?: string | null; admission_no?: string | null; jamb_reg_no?: string | null; current_level?: number | null;
  status?: string | null; merged?: boolean; programme?: string | null; department?: string | null; faculty?: string | null; entry_session?: string | null;
}

export interface SwapPayment {
  id: string; reference: string; amount: number; session: string; purpose: string; channel?: string | null; receiptNo?: string | null;
  confirmedAt?: string | null; generatedAt?: string | null; note?: string | null; legacy?: boolean; legacyPayref?: string | null;
}

export interface SwapCheck {
  ok: boolean; refusals: string[]; payment?: SwapPayment; from?: { id: string; matricNo?: string | null; name: string };
  to?: { id: string; matricNo?: string | null; name: string } | null;
  fromProfile?: SwapProfile; fromAccount?: SwapAccount; toProfile?: SwapProfile; toAccount?: SwapAccount;
}

export interface FoundPayment {
  id: string; reference: string; amount: number; session: string; purpose: string; channel?: string | null; receipt_no?: string | null;
  confirmed_at?: string | null; student_id: string; matric_no?: string | null; name: string; eligible: boolean; refusals: string[];
}

export interface FoundStudent {
  id: string; name: string; matric_no?: string | null; jamb_reg_no?: string | null; admission_no?: string | null; current_level?: number | null;
  status?: string | null; programme?: string | null; merged?: boolean;
}

export interface SwapRow {
  id: string; swap_ref: string; kind: "SWAP" | "REVERSAL"; reference: string; amount: number; session: string; purpose: string;
  payment_confirmed_at?: string | null; legacy: boolean; status: SwapStatus; reason: string; flags?: string | null;
  from_matric?: string | null; from_name: string; to_matric?: string | null; to_name: string;
  initiated_at: string; initiated_by?: string | null; initiated_office: string; decided_at?: string | null; decided_by?: string | null;
  executed_at?: string | null; initiated_by_me?: boolean;
}

export interface SwapList { total: number; page: number; size: number; rows: SwapRow[]; counts: { status: SwapStatus; n: number }[] }

export interface SwapEvent { action: string; note?: string | null; at: string; actor_office?: string | null; actor?: string | null; student?: string | null }

export interface SwapDetail {
  swap: SwapRow & {
    payment_id: string; evidence?: string | null; decision_note?: string | null; failure?: string | null; channel?: string | null; receipt_no?: string | null;
    initiated_name?: string | null; decided_name?: string | null; decided_office?: string | null; reverses_ref?: string | null; reversed_by_ref?: string | null;
    credited_now?: string | null; before_state?: { from: SwapAccount; to: SwapAccount; sessionReceived: number } | null;
    after_state?: { from: SwapAccount; to: SwapAccount; sessionReceived: number } | null; flags?: string[] | string | null;
  };
  from: SwapProfile; to: SwapProfile; fromAccount: SwapAccount; toAccount: SwapAccount; refusalsNow?: string[];
  events: SwapEvent[]; evidence: { id: string; filename: string; content_type: string; size_bytes: number; added_at: string; added_by?: string | null }[];
  paymentHistory: { swap_ref: string; kind: string; status: SwapStatus; initiated_at: string; executed_at?: string | null; from_matric?: string | null; to_matric?: string | null }[];
  result?: { status: string; failure?: string; flags?: string[] };
}

export interface SwapFilters { status: string; q: string; session: string; from: string; to: string }

export const EMPTY_SWAP_FILTERS: SwapFilters = { status: "", q: "", session: "", from: "", to: "" };

export const STATUS_WORDS: Record<SwapStatus, [kind: "ok" | "info" | "bad" | "grey" | "warn", word: string]> = {
  PENDING_APPROVAL: ["warn", "Pending approval"],
  COMPLETED: ["ok", "Completed"],
  REJECTED: ["grey", "Rejected"],
  CANCELLED: ["grey", "Cancelled"],
  FAILED: ["bad", "Failed"],
  REVERSED: ["info", "Reversed"],
};

export const SWAP_STATUSES = Object.keys(STATUS_WORDS) as SwapStatus[];

export const EVENT_WORDS: Record<string, string> = {
  PAYMENT_SWAP_INITIATED: "Swap initiated",
  PAYMENT_SWAP_EVIDENCE_ADDED: "Evidence added",
  PAYMENT_SWAP_APPROVED: "Approved",
  PAYMENT_SWAP_REJECTED: "Rejected",
  PAYMENT_SWAP_CANCELLED: "Cancelled",
  PAYMENT_SWAP_EXECUTION_STARTED: "Execution started",
  PAYMENT_ALLOCATION_REMOVED: "Payment removed from the credited student",
  PAYMENT_ALLOCATION_CREATED: "Payment credited to the student it belongs to",
  PAYMENT_SWAP_COMPLETED: "Swap completed",
  PAYMENT_SWAP_FAILED: "Swap failed",
  PAYMENT_SWAP_REVERSED: "Swap reversed",
};

export const FLAG_WORDS: Record<string, string> = {
  FROM_REGISTRATION_UNCLEARED: "The credited student has a course registration this session that their fees no longer clear — for the Bursary to follow up",
  TO_OVERPAID: "The student the payment belongs to has now paid more than this session's fees — an overpayment for the Bursary to carry forward or refund (Refunds & Credits)",
};

/** a refusal as the server words it ("SWAP_SAME_STUDENT: Original and target …"): its code and its words */
export function refusalParts(r: string): { code: string; words: string } {
  const i = r.indexOf(":");
  if (i < 0 || !/^[A-Z_]+$/.test(r.slice(0, i))) return { code: "", words: r.trim() };
  const words = r.slice(i + 1).trim();
  return { code: r.slice(0, i), words: words ? words.charAt(0).toUpperCase() + words.slice(1) : words };
}

const MEANINGLESS = /^(wrong|fix|swap|error|mistake|correction|test)[ .!]*$/i;

/** whether a reason may be sent — the server's own test (twenty characters or more, not a single word such as "wrong"); the
 *  server decides */
export function reasonOk(reason: string): boolean {
  const t = reason.trim();
  return t.length >= 20 && !MEANINGLESS.test(t);
}

/** the list's query string — only what is set */
export function swapQuery(f: SwapFilters, extra: Record<string, string | number | boolean | undefined> = {}): string {
  const p = new URLSearchParams();
  (Object.keys(f) as (keyof SwapFilters)[]).forEach((k) => { const v = f[k].trim(); if (v) p.set(k, v); });
  Object.entries(extra).forEach(([k, v]) => { if (v !== undefined && v !== "" && v !== false) p.set(k, String(v)); });
  return p.toString();
}

/** the filters a page was asked for, each checked */
export function readSwapFilters(p: Record<string, string | string[] | undefined>): SwapFilters {
  const one = (k: string) => (typeof p[k] === "string" ? (p[k] as string).trim() : "");
  const date = (k: string) => (/^\d{4}-\d{2}-\d{2}$/.test(one(k)) ? one(k) : "");
  const status = one("status").toUpperCase();
  return {
    status: (SWAP_STATUSES as string[]).includes(status) ? status : "",
    q: one("q").slice(0, 80),
    session: /^\d{4}\/\d{4}$/.test(one("session")) ? one("session") : "",
    from: date("from"),
    to: date("to"),
  };
}

/** a student as one line: the matriculation number (or the admission number) and the name */
export function studentLine(s: { matric_no?: string | null; admission_no?: string | null; name: string } | null | undefined): string {
  if (!s) return "";
  const n = s.matric_no || s.admission_no;
  return n ? `${n} — ${s.name}` : s.name;
}

export const SWAP_HEAD = ["Swap", "Kind", "Payment reference", "Amount (₦)", "Session", "From (credited)", "To (owner)", "Status", "Initiated by", "Initiated", "Decided by", "Executed", "Reason"];

/** a swap as a row of the report */
export function swapLine(r: SwapRow, when: (iso: string | null | undefined) => string): (string | number)[] {
  return [
    r.swap_ref, r.kind === "REVERSAL" ? "Reversal" : "Swap", r.reference, Number(r.amount), r.session,
    `${r.from_matric ?? ""} ${r.from_name}`.trim(), `${r.to_matric ?? ""} ${r.to_name}`.trim(), STATUS_WORDS[r.status]?.[1] ?? r.status,
    r.initiated_by ?? "", when(r.initiated_at), r.decided_by ?? "", when(r.executed_at), r.reason,
  ];
}

/** the evidence file a browser may send: PDF, JPEG or PNG, up to 5 MB */
export function evidenceRefusal(file: { type: string; size: number }): string | null {
  if (!["application/pdf", "image/jpeg", "image/png"].includes(file.type)) return "Evidence is a PDF, JPEG or PNG file.";
  if (file.size <= 0) return "The file is empty.";
  if (file.size > 5 * 1024 * 1024) return "Evidence is up to 5 MB.";
  return null;
}
