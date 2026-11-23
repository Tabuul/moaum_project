/** V781: overpaid school fees reconciled from the Bursar's dashboard — the shapes /api/v1/finance/overpaid answers (the kept list's
 *  rows with their state read live, the figures, the credit requests made on the desk), the words a cause, a state, a hold and a
 *  refusal are shown in, what may be selected and decided, the totals of one act over its calls, and the Excel list. Every figure is
 *  the server's: nothing here works out an excess or an amount. Node-tested. */
import { day } from "./format.ts";
import type { CreditRequestRow, RequestStatus } from "./legacy-reconciliation.ts";

type Money = number | string;
type Tone = "ok" | "warn" | "bad" | "grey" | "info";

/** why a student is paid above the charge (finance.overpaid_read): one cause a student and session */
export type OverpaidCause = "PORTAL_TWICE" | "OLD_AND_PORTAL" | "OLD_TWICE" | "PART_PAYMENTS" | "ABOVE_FEE_LINE";

/** the five causes, in the order the figures and the tiles keep */
export const CAUSES: OverpaidCause[] = ["PORTAL_TWICE", "OLD_AND_PORTAL", "OLD_TWICE", "PART_PAYMENTS", "ABOVE_FEE_LINE"];

export const CAUSE_WORDS: Record<OverpaidCause, string> = {
  PORTAL_TWICE: "Paid twice on the portal",
  OLD_AND_PORTAL: "Paid on the old portal and the new",
  OLD_TWICE: "Paid twice on the old portal",
  PART_PAYMENTS: "Several payments above the charge",
  ABOVE_FEE_LINE: "Paid above the fee line",
};

/** a cause in words; a batch of several causes (MIXED), or one the screen does not know, is said as such */
export function causeWord(cause: string | null | undefined): string {
  if (!cause) return "";
  return cause === "MIXED" ? "several causes" : CAUSE_WORDS[cause as OverpaidCause] ?? cause;
}

/** the three causes a repeated payment explains: the only ones requested or refunded as a whole */
export function isPaidTwice(cause: string | null | undefined): boolean {
  return cause === "PORTAL_TWICE" || cause === "OLD_AND_PORTAL" || cause === "OLD_TWICE";
}

/** where a listed row stands (finance.overpaid_desk), read live at each read */
export type OverpaidState = "OVER_DECIDED" | "UNDECIDED" | "CREDIT_REQUESTED" | "CREDIT_RETURNED" | "CREDITED" | "REFUND_RAISED" | "REFUND_APPROVED" | "REFUND_PAID"
  | "REFUND_BY_HAND" | "CARRIED";

export const STATE_WORDS: Record<OverpaidState, [string, Tone]> = {
  OVER_DECIDED: ["Decided above the excess", "bad"],
  UNDECIDED: ["Not decided", "warn"],
  CREDIT_REQUESTED: ["Credit requested", "info"],
  CREDIT_RETURNED: ["Credit returned for correction", "bad"],
  CREDITED: ["Credited to the wallet", "ok"],
  REFUND_RAISED: ["Refund raised", "info"],
  REFUND_APPROVED: ["Refund approved", "info"],
  REFUND_PAID: ["Refund paid", "ok"],
  REFUND_BY_HAND: ["Refunded on Refunds & Credits", "grey"],
  CARRIED: ["Carried into the next session", "ok"],
};

/** the ten states, in the order the desk's filter offers them */
export const STATES = Object.keys(STATE_WORDS) as OverpaidState[];

/** why a listed row cannot be decided yet (finance.overpaid_read): any hold stops the wallet credit, the refund and the carry */
export type OverpaidHold = "PAST_SESSION" | "CLOSED_FOR_FEES" | "BANK_CHECK" | "SAME_PAYMENT" | "REVERSAL" | "UNDER_REVIEW" | "OPEN_CORRECTION" | "SEMESTER_NOT_CHARGED"
  | "SEMESTER_NOT_STATED" | "SPILLOVER_SEMESTER" | "LATE_FEE_POSSIBLE" | "LATE_FEE_LAPSED" | "EXCESS_UNCERTAIN" | "MERGED_RECORD";

/** each hold as it is shown — the sentences of finance.overpaid_hold_word, word for word */
export const HOLD_WORDS: Record<OverpaidHold, string> = {
  PAST_SESSION: "Not this student's current session — its charge is read as the student stands today",
  CLOSED_FOR_FEES: "Graduated: nothing is charged for this session — refund the payment on Refunds & Credits",
  BANK_CHECK: "Waiting for the bank check",
  SAME_PAYMENT: "One payment recorded twice — archive the duplicate",
  REVERSAL: "A PayDirect reversal is on record",
  UNDER_REVIEW: "A payment is archived for review",
  OPEN_CORRECTION: "A payment correction is open",
  SEMESTER_NOT_CHARGED: "A semester of this session is not yet charged",
  SEMESTER_NOT_STATED: "A semester's fees are not yet stated",
  SPILLOVER_SEMESTER: "Spillover: a semester still to be registered",
  LATE_FEE_POSSIBLE: "A late registration fee may still fall",
  LATE_FEE_LAPSED: "A late payment fee was due — it is not an overpayment",
  EXCESS_UNCERTAIN: "The student's own fee account reads a different excess",
  MERGED_RECORD: "A duplicate record — decide on the record kept",
};

/** what clears each hold */
const HOLD_REMEDY: Record<OverpaidHold, string> = {
  PAST_SESSION: "Not here: Historical Fees assesses a past session",
  CLOSED_FOR_FEES: "A refund raised on Refunds & Credits against the payment (it then counts as decided)",
  BANK_CHECK: "The Bursary's verdict on the possible bank double charge",
  SAME_PAYMENT: "The duplicate archived on Archived Payments (allowed while the decided money stays covered)",
  REVERSAL: "The reversed record archived",
  UNDER_REVIEW: "The archive settled",
  OPEN_CORRECTION: "The correction decided",
  SEMESTER_NOT_CHARGED: "The semester opened",
  SEMESTER_NOT_STATED: "The fee line stated, or the semester closed",
  SPILLOVER_SEMESTER: "The registration, or the semester closed",
  LATE_FEE_POSSIBLE: "The registration submitted, or the semester closed",
  LATE_FEE_LAPSED: "Not here: if the Bursary waives the fee, the refund is raised on Refunds & Credits against the payment",
  EXCESS_UNCERTAIN: "A person looks: requested or refunded for that student alone, the server says which figure differs",
  MERGED_RECORD: "Decided on the record kept",
};

/** the fourteen holds */
export const HOLDS = Object.keys(HOLD_WORDS) as OverpaidHold[];

/** a hold in words; one the screen does not know shows its code */
export function holdWord(code: string): string {
  return HOLD_WORDS[code as OverpaidHold] ?? code;
}

/** what clears a hold ("" for one the screen does not know) */
export function holdRemedy(code: string): string {
  return HOLD_REMEDY[code as OverpaidHold] ?? "";
}

/** every hold of a row, in words, as the server joins them (finance.overpaid_hold_words) */
export function holdWords(holds: readonly string[] | null | undefined): string {
  return (holds ?? []).map(holdWord).join("; ");
}

/** why a student's excess is refunded, never credited to a wallet nor carried (finance.overpaid_refund_only) */
export type RefundOnly = "DECEASED" | "GRADUATED" | "WITHDRAWN" | "LEFT" | "AWARD_APPROVED";

export const REFUND_ONLY_WORDS: Record<RefundOnly, string> = {
  DECEASED: "Deceased: refunded to the estate",
  GRADUATED: "Graduated",
  WITHDRAWN: "Withdrawn",
  LEFT: "No longer a student",
  AWARD_APPROVED: "Award approved: no further fees",
};

export function refundOnlyWord(code: string | null | undefined): string {
  return code ? REFUND_ONLY_WORDS[code as RefundOnly] ?? code : "";
}

/** what the read suggests for a row */
export type Suggested = "RECOVER" | "WAIT" | "CHECK_FEE_SETUP" | "REVIEW_PAYMENTS" | "REFUND" | "WALLET";

export const SUGGESTED_WORDS: Record<Suggested, string> = {
  RECOVER: "Recover",
  WAIT: "Wait for the check",
  CHECK_FEE_SETUP: "Check the fee setup",
  REVIEW_PAYMENTS: "Look at the payments",
  REFUND: "Refund",
  WALLET: "Credit to the wallet",
};

/** why a request, a refund or an approval left a student: a short title a code — the sentence itself is the server's, shown as sent */
export const SKIP_TITLES: Record<string, string> = {
  DECIDED: "Already decided",
  HELD: "Held",
  REFUND_ONLY: "Refund only",
  ONE_AT_A_TIME: "One at a time",
  FEE_SETUP_UNCHECKED: "Fee setup not confirmed",
  REQUEST_OPEN: "Request open",
  EXCESS_UNCERTAIN: "Figures differ",
  NOT_OVERPAID: "Not overpaid",
  LEGACY_CREDIT_SAME_OFFICER: "Your own request",
  LEGACY_CREDIT_STATE: "No longer waiting",
  LEGACY_CREDIT_EXCESS_CHANGED: "The excess changed",
  LEGACY_CREDIT_DOUBLE_CHARGE_CHECK: "Bank check",
  OVERPAID_HELD: "Held",
  OVERPAID_WALLET_REFUSED: "Refund only",
  OVERPAID_EXCESS_UNCERTAIN: "Figures differ",
  LEGACY_CREDIT_STUDENT: "Merged record",
};

/** a skip code's title; an unknown code shows the code */
export function skipTitle(code: string | null | undefined): string {
  return code ? SKIP_TITLES[code] ?? code : "";
}

/** one counted payment behind a row: the amount, the channel, the day and the kind — never a reference or a receipt */
export interface OverpaidPayment { amount: Money; channel?: string | null; on?: string | null; kind: "PORTAL" | "OLD" | "CARRIED" | string }

/** a standing decision of a row, the latest first */
export interface OverpaidDecision {
  decision: "CARRY" | "REFUND" | "WALLET" | string; amount: Money; reference?: string | null; refund_state?: string | null; to_session?: string | null;
  decided_at?: string | null;
}

/** the open credit request of a row: waiting for the Bursar, or returned for correction */
export interface OverpaidRequest {
  id: string; ref: string; amount: Money; status: "PENDING_BURSAR_APPROVAL" | "RETURNED_FOR_CORRECTION" | string; batch?: string | null; by?: string | null;
  at?: string | null; mine?: boolean;
  /** the sentence an approval pass left it with, while it waits */
  skip?: string | null;
}

/** one student of the Overpaid school fees desk (GET /finance/overpaid/rows). Not OverpaidRow: lib/old-fees exports that name for the
 *  old panel's row, whose decision_count is a number while this row's decisions is the list. The API leaves out a key that is null. */
export interface OverpaidDeskRow {
  student_id: string; number?: string | null; name: string; programme_code?: string | null; dept_code?: string | null; faculty_code?: string | null;
  /** the level the charge is read at (the level on record), and the level by entry year where the list reads one */
  level?: number | null; cohort_level?: number | null; status?: string | null;
  due: Money; paid: Money; excess: Money;
  /** the standing decisions and the refunds raised by hand, together; what is left to decide; what was decided beyond the excess */
  decided?: Money | null; refunded_by_hand?: Money | null; remaining: Money; over_decided?: Money | null;
  cause?: OverpaidCause | null;
  /** a paid-twice cause whose repeat makes up the excess exactly, on records the bank reported: decided with others; any other row
   *  is decided one student a call with the fee setup confirmed */
  bulk: boolean; repeat_amount?: Money | null; n_payments?: number | null; payments?: OverpaidPayment[] | null; holds?: string[] | null;
  refund_only?: RefundOnly | null; suggested?: Suggested | null; state: OverpaidState; decisions?: OverpaidDecision[] | null; request?: OverpaidRequest | null;
}

/** GET /finance/overpaid/rows: a page of the session's kept list, with the filters' options */
export interface OverpaidRows {
  session: string; refreshedAt?: string | null; computed: boolean; total: number; page: number; size: number; rows: OverpaidDeskRow[];
  faculties?: { code: string; name: string }[]; departments?: { code: string; name: string; faculty?: string | null }[];
}

/** the figures of one cause */
export interface CauseFigures {
  cause: OverpaidCause; students: number; excess: number; undecided: number; undecidedAmount: number; held: number; heldAmount: number; ready: number;
  readyAmount: number;
}

/** an open batch of requests made on the desk (figures.requests.batches) */
export interface CreditBatch {
  batch: string;
  /** the batch's one cause, or MIXED */
  cause?: OverpaidCause | "MIXED" | null;
  requestedBy?: string | null; requestedAt?: string | null; count: number; amount: number; pending: number; returned: number;
  /** pending requests an approval pass left as they were */
  skipped: number; mine: boolean;
}

/** GET /finance/overpaid/figures (finance.overpaid_figures): the kept list counted, the state read live. Not decided is the state, so a
 *  row with a request open is not in it; every amount of a row not decided is what is left of its excess. */
export interface OverpaidFigures {
  session: string; sessions: string[]; nextSession?: string | null;
  /** false until the session's list has been worked out: every figure is then zero */
  computed: boolean; refreshedAt?: string | null; tookMs?: number | null;
  students: number; excess: number; causes: CauseFigures[];
  paidTwice: { students: number; amount: number; ready: number; readyAmount: number; walletReady: number; walletReadyAmount: number; refundOnly: number; refundOnlyAmount: number };
  apart: { students: number; amount: number };
  held: { students: number; amount: number; reasons?: Record<string, number> | null };
  overDecided: { students: number; amount: number };
  requests: { pending: number; pendingAmount: number; forYou: number; forYouAmount: number; mine: number; mineAmount: number; returned: number; returnedMine: number;
    /** waiting on Legacy Financial Reconciliation: requests made on that desk are decided there */
    single: number; batches?: CreditBatch[] | null };
  credited: { students: number; amount: number; applied: number; inWallets: number };
  refunds: { raised: number; raisedAmount: number; approved: number; approvedAmount: number; paid: number; paidAmount: number; byHand: number; byHandAmount: number };
  carried: { students: number; amount: number };
}

/** a credit request made on the desk, as its tabs say it (the row is finance.legacy_credit_rows, lib/legacy-reconciliation) */
export const CREDIT_STATUS_WORDS: Record<RequestStatus, [string, Tone]> = {
  PENDING_BURSAR_APPROVAL: ["Waiting for the Bursar", "warn"],
  RETURNED_FOR_CORRECTION: ["Returned for correction", "bad"],
  CREDITED: ["Credited to the wallet", "ok"],
  REJECTED: ["Rejected", "bad"],
  WITHDRAWN: ["Withdrawn", "grey"],
};

/** GET /finance/overpaid/credits: a page of the requests made on the desk, each with whether it is the reader's own (mine); a page
 *  as long as its size may have another behind it. The rows of an answer, whether it came as the list itself or under `rows`. */
export function creditRows(answer: unknown): CreditRequestRow[] {
  if (Array.isArray(answer)) return answer as CreditRequestRow[];
  const rows = (answer as { rows?: unknown } | null)?.rows;
  return Array.isArray(rows) ? (rows as CreditRequestRow[]) : [];
}

/** a student a request or a refund left, or a request an approval left, with the server's sentence */
export interface SkipWhy { id?: string; ref?: string; student_id?: string; number?: string | null; name?: string | null; code: string; why: string }

/** POST /credits/request: one call of a request (the same batch is passed back while remaining is above nothing) */
export interface RequestAnswer { batch?: string | null; requested: number; amount: number; skipped: number; skippedWhy?: SkipWhy[] | null; remaining: number }

/** POST /refund (finance.decide_overpayments REFUND): requested is the students left because a wallet credit request is open */
export interface RefundAnswer {
  refunds: number; held?: number; apart?: number; requested?: number; uncertain?: number; unchecked?: number; remaining: number;
}

/** POST /credits/decide: one call of an approval pass (since is passed back on every further call of the pass) */
export interface DecideAnswer {
  batch?: string | null; since?: string | null; credited: number; amount: number; rejected: number; returned: number; skipped: number; skippedWhy?: SkipWhy[] | null;
  remaining: number;
}

/** the totals of one act over its calls */
export interface ActTotals {
  calls: number; batch: string | null;
  /** credit requests made, wallets credited, requests rejected and returned, refunds raised — each added over the calls */
  requested: number; credited: number; rejected: number; returned: number; refunds: number; amount: number;
  skipped: number; skippedWhy: SkipWhy[];
  /** what a refund left, as its last call counts them: held, not an exact repeat, a credit request open, the two readings differing,
   *  the fee setup not confirmed */
  held: number; apart: number; open: number; uncertain: number; unchecked: number;
  remaining: number;
}

const n = (v: unknown): number => {
  const x = Number(v ?? 0);
  return Number.isFinite(x) ? x : 0;
};

/** a figure as the server sent it, to the kobo (0 for a key the API left out) */
export const num = (v: unknown): number => Math.round(n(v) * 100) / 100;

/** ₦ and thousands, the kobo only when there are any */
export function naira(v: unknown): string {
  const x = num(v);
  const kobo = Math.round(x * 100) % 100 !== 0;
  return `₦${x.toLocaleString("en-NG", { minimumFractionDigits: kobo ? 2 : 0, maximumFractionDigits: 2 })}`;
}

/** a count with its noun: "1 student", "2,300 students" */
export function count(v: unknown, one: string, many = `${one}s`): string {
  const x = n(v);
  return `${x.toLocaleString("en-GB")} ${x === 1 ? one : many}`;
}

/** the totals of one act over its calls. A request and a refund read every row again on each call, so what they left is whole in the
 *  last call; an approval marks what it left and does not try it again in the pass, so each call's are joined. */
export function addUp(calls: readonly (RequestAnswer | RefundAnswer | DecideAnswer)[]): ActTotals {
  const t: ActTotals = { calls: calls.length, batch: null, requested: 0, credited: 0, rejected: 0, returned: 0, refunds: 0, amount: 0, skipped: 0, skippedWhy: [],
    held: 0, apart: 0, open: 0, uncertain: 0, unchecked: 0, remaining: 0 };
  for (const c of calls) {
    t.remaining = n(c.remaining);
    if ("refunds" in c) {
      t.refunds += n(c.refunds);
      t.held = n(c.held); t.apart = n(c.apart); t.open = n(c.requested); t.uncertain = n(c.uncertain); t.unchecked = n(c.unchecked);
      t.skipped = t.held + t.apart + t.open + t.uncertain + t.unchecked;
    } else if ("credited" in c) {
      t.batch = t.batch ?? c.batch ?? null;
      t.credited += n(c.credited); t.rejected += n(c.rejected); t.returned += n(c.returned); t.amount += n(c.amount);
      t.skipped += n(c.skipped);
      t.skippedWhy = [...t.skippedWhy, ...(c.skippedWhy ?? [])];
    } else {
      t.batch = t.batch ?? c.batch ?? null;
      t.requested += n(c.requested); t.amount += n(c.amount);
      t.skipped = n(c.skipped);
      t.skippedWhy = [...(c.skippedWhy ?? [])];
    }
  }
  t.amount = num(t.amount);
  return t;
}

/** a request runs call after call, the first answer's batch passed back, until nothing is left or a call requested nothing */
export function requestDone(a: RequestAnswer): boolean {
  return n(a.remaining) <= 0 || n(a.requested) <= 0;
}

/** a refund runs call after call until nothing is left or a call raised nothing */
export function refundDone(a: RefundAnswer): boolean {
  return n(a.remaining) <= 0 || n(a.refunds) <= 0;
}

/** an approval pass runs call after call, the first answer's `since` passed back, until nothing is left or a call tried nothing */
export function decideDone(a: DecideAnswer): boolean {
  return n(a.remaining) <= 0 || n(a.credited) + n(a.rejected) + n(a.returned) + n(a.skipped) <= 0;
}

/** what an act did, as the Note after it says it: the title, and what was left with the count of each reason. The sentences of the
 *  students left are the server's (totals.skippedWhy), shown as sent beneath it. */
export function actWords(act: "request" | "refund" | "approve" | "reject" | "return", t: ActTotals): { title: string; text: string; tone: "ok" | "info" | "bad" } {
  const left = (words: [number, string][]) => words.filter(([c]) => c > 0).map(([c, w]) => `${c.toLocaleString("en-GB")} ${w}`).join("; ");
  if (act === "refund") {
    const rest = left([[t.held, "held for a check"], [t.apart, "not an exact repeated payment (decided one student at a time)"], [t.open, "with a wallet credit request open"],
      [t.uncertain, "whose own fee account reads another excess"], [t.unchecked, "waiting for the fee-setup confirmation"]]);
    return { title: t.refunds ? `${count(t.refunds, "refund")} raised on Refunds & Credits` : "No refund was raised",
      text: `${t.refunds ? "Another officer approves each, and it is paid there with the transfer reference and date." : ""}${rest ? `${t.refunds ? " " : ""}Left: ${rest}.` : ""}`,
      tone: t.refunds ? "ok" : "info" };
  }
  const rest = t.skipped ? `${count(t.skipped, "was", "were")} left as ${t.skipped === 1 ? "it was" : "they were"}.` : "";
  if (act === "request") {
    return { title: t.requested ? `${count(t.requested, "wallet credit")} of ${naira(t.amount)} requested${t.batch ? ` (batch ${t.batch})` : ""}` : "No wallet credit was requested",
      text: `${t.requested ? "Nothing is credited yet: another Bursary officer approves." : ""}${rest ? `${t.requested ? " " : ""}${rest}` : ""}`, tone: t.requested ? "ok" : "info" };
  }
  if (act === "approve") {
    return { title: t.credited ? `${count(t.credited, "wallet")} credited with ${naira(t.amount)}` : "No wallet was credited",
      text: `${t.credited ? "Each student is told. The student applies it to school fees on the Wallet page, or asks there for a refund." : ""}${rest ? `${t.credited ? " " : ""}${rest}` : ""}`,
      tone: t.credited ? "ok" : "info" };
  }
  const done = act === "reject" ? t.rejected : t.returned;
  return { title: done ? `${count(done, "request")} ${act === "reject" ? "rejected" : "returned for correction"}` : `No request was ${act === "reject" ? "rejected" : "returned"}`,
    text: `${done ? (act === "reject" ? "No wallet was credited and no student was told." : "The requester withdraws each and requests the student again once what your note names is put right.") : ""}${rest ? `${done ? " " : ""}${rest}` : ""}`,
    tone: done ? "ok" : "info" };
}

/** the row's holds (none for a key the API left out) */
const holdsOf = (row: Pick<OverpaidDeskRow, "holds">): string[] => row.holds ?? [];

/** decided one student a call, with the confirmation that the fee setup and the payments were checked */
export function needsFeeSetupTick(row: Pick<OverpaidDeskRow, "bulk">): boolean {
  return !row.bulk;
}

/** a refund may be raised: not decided, nothing holding it */
export function canRefund(row: Pick<OverpaidDeskRow, "state" | "holds">): boolean {
  return row.state === "UNDECIDED" && holdsOf(row).length === 0;
}

/** a wallet credit may be requested: not decided, nothing holding it, and a student whose excess is not refunded instead */
export function canCredit(row: Pick<OverpaidDeskRow, "state" | "holds" | "refund_only">): boolean {
  return canRefund(row) && !row.refund_only;
}

/** the sentence shown on a row that cannot be acted on; null for one that can. `may` is what the reader's office does on the desk
 *  (both by default): a row only another office may decide says so. */
export function whyNot(row: Pick<OverpaidDeskRow, "state" | "holds" | "refund_only" | "request" | "over_decided">, may: { credit: boolean; refund: boolean } = { credit: true, refund: true }): string | null {
  switch (row.state) {
    case "UNDECIDED": break;
    case "OVER_DECIDED":
      return `Decided for more than is now paid above the charge: ${naira(row.over_decided)} is owed back to the session's fees. What the wallet still holds of it is kept back from refunds.`;
    case "CREDIT_REQUESTED": return `A wallet credit request${row.request?.ref ? ` (${row.request.ref})` : ""} is open for this student.`;
    case "CREDIT_RETURNED": return `Credit request${row.request?.ref ? ` ${row.request.ref}` : ""} was returned for correction: its requester withdraws it first.`;
    default: return `Nothing is left to decide: ${(STATE_WORDS[row.state]?.[0] ?? row.state).toLowerCase()}.`;
  }
  if (holdsOf(row).length) return `Held: ${holdWords(row.holds)}.`;
  if (row.refund_only && !may.refund) return `${refundOnlyWord(row.refund_only)}: the excess is refunded, not credited to a wallet — a Bursary officer raises the refund.`;
  if (!may.credit && !may.refund) return "Your office reads this list; the Bursary and the Students Account Officer decide.";
  return null;
}

/** whether a row may be ticked beside those already ticked: a row that is not an exact repeat is decided alone, so it may be the
 *  only one ticked and nothing joins it; a row already ticked may always be unticked */
export function selectable(row: Pick<OverpaidDeskRow, "student_id" | "state" | "holds" | "bulk">, selected: readonly Pick<OverpaidDeskRow, "student_id" | "bulk">[]): boolean {
  if (selected.some((s) => s.student_id === row.student_id)) return true;
  if (!canRefund(row)) return false;
  if (!selected.length) return true;
  return row.bulk && selected.every((s) => s.bulk);
}

/** what an office does on the Overpaid school fees desk (the API's own lists, OverpaidController): the Bursary and the Students Account
 *  Officer request a wallet credit and work the list out again; only the Bursary raises a refund and approves, returns or rejects a
 *  request. Every other reader reads. The server refuses what the office may not do; this only keeps the screen from offering it. */
export function overpaidMay(office: string | null | undefined): { credit: boolean; refund: boolean; decide: boolean; refresh: boolean } {
  const requests = office === "bursar" || office === "studentaccounts" || office === "super";
  const decides = office === "bursar" || office === "super";
  return { credit: requests, refund: decides, decide: decides, refresh: requests };
}

/** the rows a "select all ready" ticks: not decided, nothing holding them, and an exact repeated payment — the ones decided with others */
export function readyRows<T extends Pick<OverpaidDeskRow, "state" | "holds" | "bulk">>(rows: readonly T[]): T[] {
  return rows.filter((r) => r.bulk && canRefund(r));
}

/** what the rows ticked come to for a wallet credit or a refund. A refund-only student (graduated, withdrawn, deceased) is never
 *  credited to a wallet, so is left out of a credit and named; the tick for the fee setup is asked of a row alone that is not an exact
 *  repeated payment. */
export interface Selection { ids: string[]; count: number; amount: number; leftOut: OverpaidDeskRow[]; needsTick: boolean }
export function selectionFor(act: "credit" | "refund", rows: readonly OverpaidDeskRow[]): Selection {
  const ok = rows.filter((r) => (act === "credit" ? canCredit(r) : canRefund(r)));
  const leftOut = act === "credit" ? rows.filter((r) => canRefund(r) && !canCredit(r)) : [];
  return { ids: ok.map((r) => r.student_id), count: ok.length, amount: num(ok.reduce((a, r) => a + n(r.remaining), 0)), leftOut,
    needsTick: rows.length === 1 && needsFeeSetupTick(rows[0]) };
}

/** the body of POST /credits/request and POST /refund: the students ticked, or a paid-twice cause as a whole; the confirmation that
 *  the payments were looked at is always sent, and the one for the fee setup only when it was asked. `batch` is the first answer's,
 *  passed back while the act goes on (a refund has none). */
export function actBody(f: { session: string; students?: readonly string[] | null; cause?: string | null; reason: string; feeSetupChecked?: boolean; batch?: string | null;
  limit?: number }): Record<string, unknown> {
  const b: Record<string, unknown> = { session: f.session };
  if (f.students?.length) b.students = [...f.students]; else if (f.cause) b.cause = f.cause;
  b.reason = f.reason.trim();
  b.confirmed = true;
  if (f.feeSetupChecked) b.feeSetupChecked = true;
  if (f.batch) b.batch = f.batch;
  if (f.limit) b.limit = f.limit;
  return b;
}

/** why a student's session cannot be requested for a wallet credit on Legacy Financial Reconciliation (the student's picture carries
 *  the holds and the refund-only reason of each session); null when it can */
export function whyNotRequestable(s: { holds?: readonly string[] | null; refund_only?: string | null } | null | undefined): string | null {
  if (!s) return null;
  if (s.holds?.length) return `Held: ${holdWords(s.holds)}. The Overpaid school fees desk says what each one waits for.`;
  if (s.refund_only) return `${refundOnlyWord(s.refund_only)}: the excess is refunded, not credited to a wallet. Raise a refund on the Overpaid school fees desk.`;
  return null;
}

/** the kind of a counted payment, in words */
const PAYMENT_KIND: Record<string, string> = { PORTAL: "Portal", OLD: "Old portal", CARRIED: "Carried in" };
export function paymentKindWord(kind: string | null | undefined): string {
  return kind ? PAYMENT_KIND[kind] ?? kind : "";
}

/** the payments behind a row in one line: "3 payments: ₦66,745 · Legacy · 12 Mar 2026; …" */
export function paymentsWords(row: Pick<OverpaidDeskRow, "payments" | "n_payments">): string {
  const list = row.payments ?? [];
  const many = list.length || n(row.n_payments);
  if (!many) return "No payment on the list";
  const head = count(many, "payment");
  if (!list.length) return head;
  return `${head}: ${list.map((p) => [naira(p.amount), p.channel || paymentKindWord(p.kind), p.on ? day(p.on) : ""].filter(Boolean).join(" · ")).join("; ")}`;
}

/** the level a row was charged at: "100 Level", or both where the level by entry year differs from the level on record */
export function levelWords(row: Pick<OverpaidDeskRow, "level" | "cohort_level">): string {
  const level = row.level == null ? null : `${row.level} Level`;
  if (row.cohort_level == null || row.cohort_level === row.level) return level ?? "—";
  return level ? `Charged at ${level} · ${row.cohort_level} Level by entry year` : `${row.cohort_level} Level by entry year`;
}

/** whether the level the charge was read at is not the level by entry year (such a row is never decided with others) */
export function levelsDiffer(row: Pick<OverpaidDeskRow, "level" | "cohort_level">): boolean {
  return row.cohort_level != null && row.cohort_level !== row.level;
}

/** a decision in words, as the Excel list and the row say it */
const DECISION_WORDS: Record<string, string> = { CARRY: "Carried into the next session", REFUND: "Refund", WALLET: "Credited to the wallet" };
export function decisionWords(d: OverpaidDecision): string {
  const what = d.decision === "REFUND" ? `Refund ${String(d.refund_state ?? "raised").toLowerCase()}` : d.decision === "CARRY" && d.to_session ? `Carried into ${d.to_session}`
    : DECISION_WORDS[d.decision] ?? d.decision;
  return `${what} ${naira(d.amount)}${d.reference ? ` (${d.reference})` : ""}`;
}

/** the desk's Excel list. Not OVERPAID_HEADERS: lib/old-fees exports that name for the old panel's list. */
export const OVERPAID_DESK_HEADERS = ["Matric/admission no.", "Name", "Programme", "Faculty", "Department", "Level charged", "Level by entry year", "Charged (₦)", "Paid (₦)",
  "Excess (₦)", "Decided (₦)", "Refunded on Refunds & Credits (₦)", "Remaining (₦)", "Cause", "Exact repeat", "Repeated amount (₦)", "Payments", "Held for", "Suggested",
  "State", "Request", "Decisions"];

/** a row of the desk as an Excel row, in the order of OVERPAID_DESK_HEADERS */
export function overpaidExcelRow(o: OverpaidDeskRow): (string | number)[] {
  const q = o.request;
  return [o.number ?? "", o.name, o.programme_code ?? "", o.faculty_code ?? "", o.dept_code ?? "", o.level ?? "", o.cohort_level ?? o.level ?? "", num(o.due), num(o.paid),
    num(o.excess), num(o.decided), num(o.refunded_by_hand), num(o.remaining), o.cause ? CAUSE_WORDS[o.cause] ?? o.cause : "", o.bulk ? "Yes" : "No",
    o.repeat_amount == null ? "" : num(o.repeat_amount), paymentsWords(o), holdWords(o.holds), o.suggested ? SUGGESTED_WORDS[o.suggested] ?? o.suggested : "",
    `${STATE_WORDS[o.state]?.[0] ?? o.state}${num(o.over_decided) >= 1 ? `: ${naira(o.over_decided)} to recover` : ""}`,
    q ? `${q.ref} · ${CREDIT_STATUS_WORDS[q.status as RequestStatus]?.[0] ?? q.status} · ${naira(q.amount)}${q.by ? ` · by ${q.by}` : ""}${q.skip ? ` · ${q.skip}` : ""}` : "",
    (o.decisions ?? []).map(decisionWords).join("; ")];
}

/** the keys GET /rows reads as filters, with the tab and the page of the desk's own address */
const DESK_KEYS = ["session", "tab", "cause", "state", "held", "bulk", "faculty", "department", "q", "page"];

/** the desk's address for a session and its filters */
export function overpaidHref(f: Record<string, string | null | undefined>): string {
  const qs = new URLSearchParams();
  for (const k of DESK_KEYS) {
    const v = f[k];
    if (v) qs.set(k, v);
  }
  const s = qs.toString();
  return `/finance/overpaid${s ? `?${s}` : ""}`;
}

/** the query GET /rows is asked with for the desk's filters (never the tab), a page of `size`; the whole filtered list for Excel */
export function rowsQuery(f: Record<string, string | null | undefined>, size = 100, excel = false): string {
  const qs = new URLSearchParams();
  for (const k of DESK_KEYS) {
    const v = f[k];
    if (v && k !== "tab" && !(excel && k === "page")) qs.set(k, v);
  }
  qs.set("size", String(excel ? 100000 : size));
  if (excel) qs.set("export", "true");
  return qs.toString();
}

/** when the list was last worked out, as the dashboard and the desk say it */
export function asOf(iso: string | null | undefined): string {
  if (!iso) return "";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  return d.toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" });
}

/** the two commonest reasons rows are held for, in words with their counts ("" when none is held) */
export function commonestHolds(reasons: Record<string, number> | null | undefined, take = 2): string {
  return Object.entries(reasons ?? {}).filter(([, c]) => n(c) > 0).sort((a, b) => n(b[1]) - n(a[1]) || a[0].localeCompare(b[0])).slice(0, take)
    .map(([code, c]) => `${holdWord(code)} (${n(c).toLocaleString("en-GB")})`).join(" · ");
}

/** an open batch in one line, as the dashboard and the Approvals tab say it */
export function batchWords(b: CreditBatch): string {
  return `${[b.batch, causeWord(b.cause), count(b.count, "student"), naira(b.amount)].filter(Boolean).join(" · ")} · requested by ${b.requestedBy || "an officer"}`
    + `${b.requestedAt ? `, ${asOf(b.requestedAt)}` : ""}${n(b.skipped) > 0 ? ` · ${n(b.skipped).toLocaleString("en-GB")} left by an earlier approval` : ""}`;
}

/** what approving a batch does, as the confirmation says it. The credit stays on the wallet until the student applies it or asks for
 *  it as a refund: the approval itself pays no fees. */
export const APPROVE_WORDS = "Each student's wallet is credited and the student told. The student applies it to school fees on the Wallet page, or asks there for a refund. "
  + "This approval pays no fees.";

/** students decided for more than is now paid above their charge (a charge that rose after the decision), as the dashboard says it;
 *  "" when there is none */
export function overDecidedWords(students: unknown, amount: unknown): string {
  const s = n(students);
  if (s <= 0) return "";
  return `${count(s, "student was", "students were")} decided for ${naira(amount)} more than is now paid above their charge. `
    + "What their wallets still hold of it is kept back from refunds; see the desk.";
}
