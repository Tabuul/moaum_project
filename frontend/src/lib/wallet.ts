/** The funding wallet and the Bursary's desk, as the API states them (V033, V079). */
export interface WalletEntry { origin?: string | null; legacy_reference?: string | null; legacy_paid_at?: string | null; id: string; at: string; session: string; kind: string; amount: number; reference: string | null; note: string | null; source_code: string | null; source_name: string | null; nature: string | null; balance: number }
export interface FundStatus { session: string; number: string; state: string; reason: string | null; correctable: boolean; loaded_at: string }
export interface Eligibility { eligible: boolean; balance: number; cleared: boolean; arrears: boolean; pending: boolean; reason: string; nelfund_refundable?: number; self_refundable?: number; grant_held?: number; nelfund_after_settlement?: boolean; refund_natures?: string }
export interface Withdrawal { id: string; session: string; amount: number; source_code?: string | null; bank_name: string; account_no: string; account_name: string; state: string; reason: string | null; requested_at: string; decided_at: string | null; paid_at: string | null; paid_ref: string | null }
/** V327: the wallet by source — what was credited, applied, reversed, refunded, held for a pending refund, and what is available */
export interface SourceBalance { source_code: string; source_name: string; nature: string; credited: number; applied: number; reversed: number; refunded: number; held: number; available: number }
/** V327: whether a top-up is allowed and the whole calculation behind the answer */
export interface TopupEligibility {
  allowed: boolean; reason: "ALLOWED" | "NO_SHORTFALL" | "FEES_SETTLED" | "NO_CHARGE_STATED" | "WINDOW_CLOSED" | "STUDENT_INACTIVE" | "NO_SUCH_STUDENT";
  due: number; paid: number; outstanding: number; wallet_available: number; nelfund_available: number; other_available: number; self_available: number;
  shortfall: number; max_topup: number; window_state: string; over_shortfall_allowed: boolean; open_reference: string | null;
}
export interface StudentWallet {
  session: string; balance: number; statement: WalletEntry[];
  position: { due: number; paid: number; balance: number; instalments_paid: number; paid_in_full: boolean; has_arrears: boolean };
  status: FundStatus | null;
  eligibility: Eligibility;
  withdrawal: Withdrawal | null;
  balances: SourceBalance[];
  sessionBalances: SourceBalance[];
  topup: TopupEligibility;
}
/** V327: the Bursary's figures over the funded population of a session */
export interface NelfundFigures {
  received: number; students_funded: number; nelfund_credited: number; nelfund_applied: number; nelfund_remaining: number; nelfund_refundable: number; students_refundable: number;
  refunds_pending: number; refunds_pending_amount: number; refunds_approved: number; refunds_paid: number; refunds_paid_amount: number; refunds_rejected: number;
  legacy_posted: number; legacy_posted_rows: number; legacy_review_rows: number; legacy_review_amount: number;
  students_shortfall: number; shortfall_amount: number; students_topup: number; students_paid_before_fund: number; grants_credited: number; self_credited: number;
}
export interface WalletPolicy { apply_order: string; topup_over_shortfall: boolean; refund_natures: string; updated_at: string | null; updated_office: string | null }
export interface NelfundStudentRow {
  student_id: string; name: string; number: string; programme_code: string; programme: string; faculty_code: string | null; dept_code: string | null; level: number; status: string;
  nelfund_credited: number; nelfund_applied: number; nelfund_available: number; nelfund_refundable: number; other_credited: number; self_credited: number;
  due: number; paid: number; outstanding: number; shortfall: number; topup_allowed: boolean; topup_reason: string;
  refund_state: string | null; refund_amount: number | null; legacy_posted: number; nelfund_after_settlement: boolean;
}
export type NelfundFilter = "ALL" | "SHORTFALL" | "TOPUP" | "REFUNDABLE" | "PAID_BEFORE_FUND" | "REFUND_PENDING" | "LEGACY" | "OUTSTANDING";
export const NELFUND_FILTERS: [NelfundFilter, string][] = [
  ["ALL", "Everyone funded"], ["SHORTFALL", "With a shortfall"], ["TOPUP", "Top-up allowed"], ["REFUNDABLE", "NELFUND refundable"],
  ["PAID_BEFORE_FUND", "Paid before the Fund"], ["REFUND_PENDING", "Refund pending"], ["LEGACY", "From the old portal"], ["OUTSTANDING", "Fees outstanding"],
];
/** the one sentence behind a top-up decision, in the student's words */
export function topupWord(t: TopupEligibility, session: string): string {
  switch (t.reason) {
    case "ALLOWED": return `Your verified funding does not fully cover your ${session} school fees.`;
    case "NO_SHORTFALL": return `Your funding covers what is outstanding for ${session}; apply it, no top-up is required.`;
    case "FEES_SETTLED": return `Your ${session} school fees are settled; a top-up is not required.`;
    case "NO_CHARGE_STATED": return `No charge is stated for ${session} yet, so there is nothing to top up for.`;
    case "WINDOW_CLOSED": return `School fees payment is ${t.window_state.toLowerCase()} for ${session}; a top-up waits for the window.`;
    case "STUDENT_INACTIVE": return "A top-up is for a student in study.";
    default: return "A top-up is not required.";
  }
}
export interface FundingSource { code: string; name: string; nature: string; sponsor: string | null; account: string | null; active: boolean; note: string | null; sort: number }
export interface QueueWithdrawal { id: string; student_id: string; matric_no: string | null; student_name: string; session: string; amount: number; bank_name: string; account_no: string; account_name: string; state: string; reason: string | null; requested_at: string; decided_at: string | null; paid_at: string | null; paid_ref: string | null }
export interface Batch { id: string; ref: string; received_on: string; amount: number; rows_read: number; note: string | null; loaded_at: string; matched: number; unmatched: number; reversed: number }
export interface UnmatchedRow { id: string; matric_no: string; name_on_remit: string | null; amount: number; why: string | null; owner: string | null; batch_ref: string; received_on: string; student_name: string | null; student_status: string | null }
export interface NelfundDesk {
  session: string;
  tiles: { received: number; batches: number; allocated: number; unallocated: number; unmatched_rows: number; reversed: number; students: number };
  batches: Batch[]; unmatched: UnmatchedRow[];
  status: { applied: number; approved: number; not_approved: number; pending: number; correctable: number };
  refusals: { reason: string; students: number; correctable: boolean }[];
  sources: FundingSource[];
  withdrawals: QueueWithdrawal[];
}
export interface FundingReport {
  session: string;
  bySource: { code: string; name: string; nature: string; sponsor: string | null; account: string | null; students: number; credited: number }[];
  cashflow: { credited: number; topped_up: number; applied: number; reversed: number; withdrawn: number; held: number; loans_in: number; grants_in: number; self_in: number; settled_to_fees: number; applied_matches: boolean };
}

/** what the wallet may pay (proto/part37 NLF_COVERS): set by what the Fund covers */
export const COVERS: [string, boolean, string][] = [
  ["Tuition and session charges", true, "The institutional charge approved by Council for the session"],
  ["Approved user charges", true, "Laboratory, library and examination charges on the same invoice"],
  ["Accommodation", false, "Hostel is charged separately and is not an institutional charge"],
  ["Transcripts and certificates", false, "Requested after the fact, and not part of the session charge"],
  ["Late registration penalty", false, "A penalty is not a fee, and the Fund does not carry it"],
  ["Card replacement", false, "Charged to the holder"],
];

/** a CSV or a pasted table into rows of {matricNo, name, amount} / {number, name, state, reason} */
export function parseRows(text: string, headers: string[]): Record<string, string>[] {
  const lines = text.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
  if (!lines.length) return [];
  const split = (l: string) => (l.includes("\t") ? l.split("\t") : l.match(/("([^"]|"")*"|[^,]*)(,|$)/g)?.map((c) => c.replace(/,$/, "").replace(/^"|"$/g, "").replace(/""/g, '"').trim()).filter((_, i, a) => i < a.length - 1 || _ !== "") ?? [l]);
  const first = split(lines[0]).map((h) => h.toLowerCase());
  const hasHeader = headers.some((h) => first.some((c) => c.includes(h)));
  const cols = hasHeader ? first : headers;
  return (hasHeader ? lines.slice(1) : lines).map((l) => {
    const cells = split(l);
    const row: Record<string, string> = {};
    headers.forEach((h, i) => {
      const at = hasHeader ? cols.findIndex((c) => c.includes(h)) : i;
      row[h] = at >= 0 ? (cells[at] ?? "").trim() : "";
    });
    return row;
  });
}
