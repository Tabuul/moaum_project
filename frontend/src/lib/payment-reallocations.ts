/**
 * Bursary payment reallocation and correction (V649): the words and shapes the correction screens share. Every figure, state and
 * refusal is the server's (finance.payment_reallocation_check, finance.decide_payment_reallocation); these only say them.
 */

export type ReallocStatus = "PENDING_APPROVAL" | "RETURNED" | "COMPLETED" | "REJECTED" | "CANCELLED" | "FAILED" | "REVERSED";

export type ReasonCode = "WRONG_PURPOSE" | "WRONG_SESSION" | "WRONG_SEMESTER" | "WRONG_LEVEL" | "LEGACY_MIGRATION" | "RECONCILIATION" | "OTHER";

export const REASON_WORDS: Record<ReasonCode, string> = {
  WRONG_PURPOSE: "Student selected the wrong payment purpose",
  WRONG_SESSION: "Payment was allocated to the wrong academic session",
  WRONG_SEMESTER: "Payment was allocated to the wrong semester",
  WRONG_LEVEL: "Payment was allocated to the wrong level",
  LEGACY_MIGRATION: "Old-portal migration allocated the payment incorrectly",
  RECONCILIATION: "Bursary reconciliation correction",
  OTHER: "Other",
};

export const REASON_CODES = Object.keys(REASON_WORDS) as ReasonCode[];

export interface Destination { code: string; label: string; supported: boolean; how: string }

export interface Period { session: string; state?: string | null; level?: number | null; semesters?: string | null; fees_stated?: boolean | null }

/** the semesters a session has, from the server's "{1,2}" */
export function periodSemesters(p: Period | undefined): number[] {
  if (!p?.semesters) return [];
  return p.semesters.replace(/[{}]/g, "").split(",").map((x) => Number(x.trim())).filter((n) => Number.isInteger(n) && n > 0);
}

export interface Account {
  code: string; kind: "SESSION_ACCOUNT" | "SINGLE_FEE"; stated: boolean; fee: number; paid: number; balance: number;
  clearsRegistration?: boolean | null; clearsExamination?: boolean | null; required?: boolean; shown?: boolean; entitled?: boolean; held?: boolean;
}

export interface CheckStudent {
  id: string; matricNo?: string | null; admissionNo?: string | null; jambRegNo?: string | null; name: string; status?: string | null; level?: number | null;
  entryMode?: string | null; studyMode?: string | null; programmeType?: string | null; programmeCode?: string | null; programme?: string | null;
  deptCode?: string | null; department?: string | null; facultyCode?: string | null; faculty?: string | null;
}

export interface CheckPayment {
  id: string; reference: string; amount: number; session: string; purpose: string; channel?: string | null; receiptNo?: string | null;
  confirmedAt?: string | null; generatedAt?: string | null; legacy?: boolean; legacyPayref?: string | null;
}

export interface CheckSource { code: string; label?: string | null; purpose: string; session: string; semester?: number | null; level?: number | null; account?: Account | null; paidAfter?: number | null }

export type Outcome = "FULLY_PAID" | "PART_PAID" | "OVERPAID";

export interface CheckDestination {
  code: string; label?: string | null; purpose: string; session: string; semester?: number | null; level?: number | null; account?: Account | null;
  fee?: number | null; paidBefore?: number | null; applied: number; paidAfter?: number | null; balance?: number | null; surplus?: number | null; outcome?: Outcome | null;
}

export interface ReallocCheck {
  ok: boolean; refusals: string[]; payment?: CheckPayment; student?: CheckStudent; source?: CheckSource; destination?: CheckDestination | null;
}

export interface FoundPayment {
  id: string; reference: string; amount: number; session: string; purpose: string; purpose_code: string; channel?: string | null; receipt_no?: string | null;
  generated_at?: string | null; confirmed_at?: string | null; student_id: string; matric_no?: string | null; admission_no?: string | null; name: string;
  eligible: boolean; refusals: string[];
}

export interface ReallocRow {
  id: string; realloc_ref: string; kind: "REALLOCATION" | "REVERSAL"; reference: string; amount: number;
  from_purpose: string; from_purpose_code: string; from_session: string; from_semester?: number | null; from_level?: number | null;
  to_purpose: string; to_purpose_code: string; to_session: string; to_semester?: number | null; to_level?: number | null;
  destination_fee?: number | null; balance_after?: number | null; surplus?: number | null; legacy: boolean; status: ReallocStatus;
  reason_code: ReasonCode; reason: string; flags?: string | null; matric_no?: string | null; name: string;
  initiated_at: string; initiated_by?: string | null; initiated_office: string; decided_at?: string | null; decided_by?: string | null;
  executed_at?: string | null; initiated_by_me?: boolean;
}

export interface ReallocList { total: number; page: number; size: number; rows: ReallocRow[]; counts: { status: ReallocStatus; n: number }[] }

export interface ReallocEvent { action: string; note?: string | null; at: string; actor_office?: string | null; actor?: string | null }

export interface ReallocDetail {
  reallocation: ReallocRow & {
    payment_id: string; evidence?: string | null; decision_note?: string | null; failure?: string | null; channel?: string | null; receipt_no?: string | null;
    payment_confirmed_at?: string | null; initiated_name?: string | null; decided_name?: string | null; decided_office?: string | null;
    returned_name?: string | null; returned_at?: string | null; returned_note?: string | null; reverses_ref?: string | null; reversed_by_ref?: string | null;
    purpose_now?: string | null; session_now?: string | null; journal_no?: number | null; paid_before?: number | null; submitted_at?: string | null;
    before_state?: { source?: Account | null; destination?: Account | null; received: number } | null;
    after_state?: { source?: Account | null; destination?: Account | null; received: number } | null; flags?: string[] | string | null;
  };
  student?: CheckStudent; source?: CheckSource; destination?: CheckDestination | null; refusalsNow?: string[];
  events: ReallocEvent[]; evidence: { id: string; filename: string; content_type: string; size_bytes: number; added_at: string; added_by?: string | null }[];
  paymentHistory: { ref: string; kind: string; status: string; from_what?: string | null; to_what?: string | null; initiated_at: string; executed_at?: string | null }[];
  result?: { status: string; failure?: string; flags?: string[]; balance?: number | null; surplus?: number | null };
}

export interface ReallocFilters { status: string; q: string; session: string; purpose: string; from: string; to: string }

export const EMPTY_REALLOC_FILTERS: ReallocFilters = { status: "", q: "", session: "", purpose: "", from: "", to: "" };

export const STATUS_WORDS: Record<ReallocStatus, [kind: "ok" | "info" | "bad" | "grey" | "warn", word: string]> = {
  PENDING_APPROVAL: ["warn", "Pending approval"],
  RETURNED: ["info", "Returned for correction"],
  COMPLETED: ["ok", "Completed"],
  REJECTED: ["grey", "Rejected"],
  CANCELLED: ["grey", "Cancelled"],
  FAILED: ["bad", "Failed"],
  REVERSED: ["info", "Reversed"],
};

export const REALLOC_STATUSES = Object.keys(STATUS_WORDS) as ReallocStatus[];

export const OUTCOME_WORDS: Record<Outcome, [kind: "ok" | "warn" | "info", word: string]> = {
  FULLY_PAID: ["ok", "Fully paid"],
  PART_PAID: ["warn", "Balance to pay"],
  OVERPAID: ["info", "Surplus"],
};

export const EVENT_WORDS: Record<string, string> = {
  REALLOCATION_INITIATED: "Correction initiated",
  REALLOCATION_RESUBMITTED: "Changed and sent again",
  REALLOCATION_RETURNED: "Returned for correction",
  REALLOCATION_EVIDENCE_ADDED: "Evidence added",
  REALLOCATION_APPROVED: "Approved",
  REALLOCATION_REJECTED: "Rejected",
  REALLOCATION_CANCELLED: "Cancelled",
  REALLOCATION_EXECUTION_STARTED: "Execution started",
  PAYMENT_ALLOCATION_REMOVED: "Payment removed from the purpose it was applied to",
  PAYMENT_ALLOCATION_CREATED: "Payment applied to the purpose it was meant for",
  LEDGER_RECLASSIFIED: "Ledger reclassified (no new cash)",
  REALLOCATION_COMPLETED: "Correction completed",
  REALLOCATION_FAILED: "Correction failed",
  REALLOCATION_REVERSED: "Correction reversed",
};

export const FLAG_WORDS: Record<string, string> = {
  BALANCE_TO_PAY: "A balance is left on the obligation; the student pays it through the normal payment page",
  DESTINATION_OVERPAID: "The payment is more than the obligation — a surplus for the Bursary to carry forward or refund (Refunds & Credits)",
  SOURCE_REGISTRATION_UNCLEARED: "The student has a course registration in the session the payment left that their school fees no longer clear — for the Bursary to follow up",
  SOURCE_GST_UNPAID: "The student owes the GST fee of the session the payment left and no longer has it paid — for the Bursary to follow up",
};

/** a refusal as the server words it ("REALLOC_GST_SHORT: the GST fee is …"): its code and its words */
export function refusalParts(r: string): { code: string; words: string } {
  const i = r.indexOf(":");
  if (i < 0 || !/^[A-Z_]+$/.test(r.slice(0, i))) return { code: "", words: r.trim() };
  const words = r.slice(i + 1).trim();
  return { code: r.slice(0, i), words: words ? words.charAt(0).toUpperCase() + words.slice(1) : words };
}

const MEANINGLESS = /^(wrong|fix|error|mistake|correction|reallocation|reallocate|test|update)[ .!]*$/i;

/** whether a reason may be sent — the server's own test (twenty characters or more, not a single word such as "wrong"); the
 *  server decides */
export function reasonOk(reason: string): boolean {
  const t = reason.trim();
  return t.length >= 20 && !MEANINGLESS.test(t);
}

/** the list's query string — only what is set */
export function reallocQuery(f: ReallocFilters, extra: Record<string, string | number | boolean | undefined> = {}): string {
  const p = new URLSearchParams();
  (Object.keys(f) as (keyof ReallocFilters)[]).forEach((k) => { const v = f[k].trim(); if (v) p.set(k, v); });
  Object.entries(extra).forEach(([k, v]) => { if (v !== undefined && v !== "" && v !== false) p.set(k, String(v)); });
  return p.toString();
}

/** the filters a page was asked for, each checked */
export function readReallocFilters(p: Record<string, string | string[] | undefined>): ReallocFilters {
  const one = (k: string) => (typeof p[k] === "string" ? (p[k] as string).trim() : "");
  const date = (k: string) => (/^\d{4}-\d{2}-\d{2}$/.test(one(k)) ? one(k) : "");
  const status = one("status").toUpperCase();
  const purpose = one("purpose").toUpperCase();
  return {
    status: (REALLOC_STATUSES as string[]).includes(status) ? status : "",
    q: one("q").slice(0, 80),
    session: /^\d{4}\/\d{4}$/.test(one("session")) ? one("session") : "",
    purpose: /^[A-Z][A-Z_]{1,39}$/.test(purpose) ? purpose : "",
    from: date("from"),
    to: date("to"),
  };
}

/** a period as one phrase: "2026/2027, first semester, 300 Level" */
export function periodWords(session: string, semester?: number | null, level?: number | null): string {
  const sem = semester === 1 ? "first semester" : semester === 2 ? "second semester" : semester === 3 ? "third semester" : null;
  return [session, sem, level ? `${level} Level` : null].filter(Boolean).join(", ");
}

/** the report's columns — S/N is put first by the export itself */
export const REALLOC_HEAD = ["Reallocation ref", "Payment ref", "Student", "Matric no", "Original purpose", "New purpose", "Original session", "New session",
  "Original semester", "New semester", "Original level", "New level", "Amount (₦)", "Destination fee (₦)", "Balance (₦)", "Status", "Initiated by", "Approved by", "Date"];

/** a correction as a row of the report */
export function reallocLine(r: ReallocRow, when: (iso: string | null | undefined) => string): (string | number)[] {
  const sem = (n?: number | null) => (n === 1 ? "First" : n === 2 ? "Second" : n === 3 ? "Third" : "");
  return [
    r.realloc_ref, r.reference, r.name, r.matric_no ?? "", r.from_purpose, r.to_purpose, r.from_session, r.to_session,
    sem(r.from_semester), sem(r.to_semester), r.from_level ?? "", r.to_level ?? "", Number(r.amount),
    r.destination_fee == null ? "" : Number(r.destination_fee), r.balance_after == null ? "" : Number(r.balance_after),
    STATUS_WORDS[r.status]?.[1] ?? r.status, r.initiated_by ?? "", r.decided_by ?? "", when(r.executed_at ?? r.initiated_at),
  ];
}

/** the evidence file a browser may send: PDF, JPEG or PNG, up to 5 MB */
export function evidenceRefusal(file: { type: string; size: number }): string | null {
  if (!["application/pdf", "image/jpeg", "image/png"].includes(file.type)) return "Evidence is a PDF, JPEG or PNG file.";
  if (file.size <= 0) return "The file is empty.";
  if (file.size > 5 * 1024 * 1024) return "Evidence is up to 5 MB.";
  return null;
}
