/** Legacy financial reconciliation (V625): the shapes /api/v1/finance/legacy-reconciliation returns, the words its states are shown
 *  in, and the reports' rows (S/N first). Every figure is the server's; nothing here works out a balance or an amount. */
import { num } from "./legacy-wallet";

/** the outstanding fees of a session, student by student, as the reconciliation classifies them */
export type OutstandingState = "OWES" | "CREDIT" | "CREDIT_DECIDED" | "SETTLED" | "NO_FEE_STATED";
export const STATE_WORDS: Record<OutstandingState, [string, "ok" | "bad" | "warn" | "grey" | "info", string]> = {
  OWES: ["Student owes the University", "bad", "A legacy outstanding fee: a liability of the student, never wallet money"],
  CREDIT: ["Credit held for the student", "warn", "Paid above the fees stated: eligible for a wallet-credit request"],
  CREDIT_DECIDED: ["Credit decided", "ok", "Carried into the next session, refunded, or credited to the wallet"],
  SETTLED: ["Settled", "grey", "Paid what the fee setup states"],
  NO_FEE_STATED: ["No fee stated", "info", "The Bursary has not stated the session's fees for the programme and level"],
};
export const DECISION_WORDS: Record<string, string> = { CARRY: "Carried into the next session", REFUND: "Refund raised", WALLET: "Credited to the wallet" };

export interface OutstandingRow {
  student_id: string; number: string; name: string; matric_no: string | null; jamb_reg_no: string | null; admission_no: string | null;
  programme_code: string | null; programme: string | null; dept_code: string | null; department: string | null; faculty_code: string | null; faculty: string | null;
  level: number | null; session: string; due: number | string; paid: number | string; paid_old_s1: number | string; paid_old_s2: number | string; paid_old_session: number | string;
  paid_payment_history: number | string; paid_portal: number | string; old_payments: number; owed: number | string; excess: number | string; state: OutstandingState;
  decision: string | null; carried_in: number | string | null; settled: number | string | null; doubles: number; request_ref: string | null; request_status: RequestStatus | null;
  request_amount: number | string | null; last_reference: string | null; last_paid_at: string | null;
}

/** a legacy credit request: a verified overpayment on its way to the wallet */
export type RequestStatus = "PENDING_BURSAR_APPROVAL" | "RETURNED_FOR_CORRECTION" | "CREDITED" | "REJECTED" | "WITHDRAWN";
export const REQUEST_WORDS: Record<RequestStatus, [string, "ok" | "bad" | "warn" | "grey" | "info"]> = {
  PENDING_BURSAR_APPROVAL: ["Pending Bursar approval", "warn"], RETURNED_FOR_CORRECTION: ["Returned for correction", "bad"],
  CREDITED: ["Approved · credited to the wallet", "ok"], REJECTED: ["Rejected", "bad"], WITHDRAWN: ["Withdrawn", "grey"],
};

export interface CreditRequestRow {
  id: string; ref: string; student_id: string; student: string; matric_no: string | null; jamb_reg_no: string | null; admission_no: string | null;
  programme_code: string | null; programme: string | null; dept_code: string | null; department: string | null; faculty_code: string | null; faculty: string | null;
  session: string; kind: string; due: number | string; paid: number | string; legacy_amount: number | string; confirmed_amount: number | string; adjusted: boolean;
  adjustment_reason: string | null; reason: string; evidence: string; status: RequestStatus; initiated_by: string | null; initiated_office: string; initiated_at: string;
  resubmitted_at: string | null; resubmissions: number; decided_by: string | null; decided_office: string | null; decided_at: string | null; decision_note: string | null;
  withdrawn_by: string | null; withdrawn_at: string | null; withdraw_reason: string | null; wallet_reference: string | null; credited_at: string | null; balance_after: number | string | null;
}

export interface ReconFigures {
  session: string;
  outstanding: { students: number; owes: number; owesAmount: number | string; credit: number; creditAmount: number | string; decided: number; decidedAmount: number | string;
    carried: number; refunded: number; toWallet: number; settled: number; noFee: number };
  requests: { pending: number; pendingAmount: number | string; returned: number; returnedAmount: number | string; credited: number; creditedAmount: number | string;
    rejected: number; rejectedAmount: number | string; withdrawn: number; adjusted: number; pendingSession: number };
  wallet: { students: number; computed: number; computedAmount: number | string; verified: number; verifiedAmount: number | string; returned: number; returnedAmount: number | string;
    posted: number; postedAmount: number | string; review: number; rejected: number; frozen: number; noBalance: number; applied: number | string };
  overpaidCredited: { amount: number | string; applied: number | string };
}

/** one student's legacy picture, as /students/{id} returns it */
export interface StudentPicture {
  student: { id: string; name: string; matric_no: string | null; jamb_reg_no: string | null; admission_no: string | null; programme_code: string | null; programme: string | null;
    dept_code: string | null; department: string | null; faculty_code: string | null; faculty: string | null; current_level: number | null; status: string; entry_session: string | null };
  sessions: { session: string; due: number | string; paid: number | string; owed: number | string; excess: number | string; legacy_payments: number; legacy_amount: number | string;
    decision: string | null; decided_amount: number | string | null; decision_reference: string | null }[];
  payments: { reference: string; session: string; purpose: string; amount: number | string; confirmed_at: string; channel: string; receipt_no: string | null; legacy_payref: string | null; note: string | null }[];
  requests: CreditRequestRow[];
  legacyWallet: Record<string, unknown>;
  walletBalance: number | string;
}

export const naira = (v: unknown) => `₦${num(v).toLocaleString("en-GB", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
export const whenDay = (v: unknown) => (v ? new Date(String(v)).toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }) : "");

export type Tab = "overview" | "outstanding" | "wallet" | "requests" | "history";
export const TABS: { id: Tab; label: string }[] = [
  { id: "overview", label: "Overview" }, { id: "outstanding", label: "Outstanding fees" }, { id: "wallet", label: "E-wallet top-ups" },
  { id: "requests", label: "Wallet credit requests" }, { id: "history", label: "History" },
];

export function reconHref(f: Record<string, string>): string {
  const qs = new URLSearchParams();
  for (const k of ["tab", "session", "state", "status", "q", "fac", "dept"]) if (f[k]) qs.set(k, f[k]);
  const s = qs.toString();
  return `/finance/legacy-reconciliation${s ? `?${s}` : ""}`;
}

/** the outstanding fees report, S/N first (the brief's columns) */
export const OUTSTANDING_HEADERS = ["S/N", "Student", "Matric No.", "JAMB No.", "Application No.", "Faculty", "Department", "Programme", "Legacy session", "Level",
  "Fees due", "Paid", "Paid on the old portal", "Student owes", "Credit held", "Classification", "Decision", "Request", "Doubles", "Last reference", "Last paid"];
export function outstandingRows(rows: OutstandingRow[]): (string | number)[][] {
  return rows.map((r, i) => [i + 1, r.name, r.matric_no ?? "", r.jamb_reg_no ?? "", r.admission_no ?? "", r.faculty ?? r.faculty_code ?? "", r.department ?? r.dept_code ?? "",
    r.programme ?? r.programme_code ?? "", r.session, r.level ?? "", num(r.due), num(r.paid), num(r.paid_old_s1) + num(r.paid_old_s2) + num(r.paid_old_session), num(r.owed), num(r.excess),
    STATE_WORDS[r.state]?.[0] ?? r.state, r.decision ? DECISION_WORDS[r.decision] ?? r.decision : "", r.request_ref ? `${r.request_ref} (${REQUEST_WORDS[r.request_status!]?.[0] ?? r.request_status})` : "",
    r.doubles, r.last_reference ?? "", r.last_paid_at ? whenDay(r.last_paid_at) : ""]);
}

/** the wallet credit requests report, S/N first */
export const REQUEST_HEADERS = ["S/N", "Request", "Student", "Matric No.", "Record type", "Legacy session", "Fees due", "Paid", "Original amount (excess)", "Confirmed amount", "Adjusted",
  "Reason", "Evidence", "Account officer", "Confirmed on", "Resubmitted", "Status", "Bursar", "Decided on", "Decision note", "Wallet reference", "Credited on", "Balance after"];
export function requestRows(rows: CreditRequestRow[]): (string | number)[][] {
  return rows.map((r, i) => [i + 1, r.ref, r.student, r.matric_no ?? r.admission_no ?? "", "Overpaid school fees", r.session, num(r.due), num(r.paid), num(r.legacy_amount),
    num(r.confirmed_amount), r.adjusted ? `Yes: ${r.adjustment_reason ?? ""}` : "No", r.reason, r.evidence, r.initiated_by ?? r.initiated_office, whenDay(r.initiated_at),
    r.resubmissions ? `${r.resubmissions} (${whenDay(r.resubmitted_at)})` : "", REQUEST_WORDS[r.status]?.[0] ?? r.status, r.decided_by ?? "", r.decided_at ? whenDay(r.decided_at) : "",
    r.decision_note ?? r.withdraw_reason ?? "", r.wallet_reference ?? "", r.credited_at ? whenDay(r.credited_at) : "", r.balance_after == null ? "" : num(r.balance_after)]);
}
