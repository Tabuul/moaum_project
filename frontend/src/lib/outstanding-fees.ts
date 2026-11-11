/** Every outstanding school fee of a student's record (V720): the past sessions and semesters as the historical engine assesses
 *  them, the current session as the fees position reads it — one list from GET /api/v1/me/outstanding-fees — with the words the
 *  dashboard shows for each status, the summary, and the report rows. */

export type Money = number | string;
export type OutstandingStatus = "UNPAID" | "PARTIALLY_PAID" | "PAYMENT_PENDING" | "PAID" | "CREDIT" | "BEING_ASSESSED";
type Tone = "ok" | "bad" | "warn" | "info" | "grey";

export interface OpenReference { reference: string; session: string; amount: Money; expires_at: string; purpose?: string }

export interface OutstandingRow {
  /** a past session (the historical engine) or the current one (the fees position) */
  kind: "PAST" | "CURRENT";
  session: string;
  /** null: the whole session is one fee period */
  semester: number | null;
  period: string;
  level: number | null;
  description: string;
  due: Money | null;
  paid: Money;
  balance: Money | null;
  credit?: Money | null;
  waived?: Money | null;
  status: OutstandingStatus;
  /** V683: what is under review for the period (evidence, an archived payment, a payment under another purpose) */
  review?: string | null;
  /** the open, unexpired reference that pays this row */
  reference?: OpenReference | null;
  payable: boolean;
  payAmount: Money | null;
  door: "HISTORICAL" | "CURRENT";
}

export interface OutstandingSummary { sessions: number; periods: number; items: number; outstanding: Money; pending: Money; paid: Money; beingAssessed?: number }

export interface OutstandingFees {
  session: string;
  graduated: boolean;
  graduationSession?: string | null;
  awaitingFinalClearance?: boolean;
  onlinePayment: boolean;
  windowOpen: boolean;
  assessedFrom: string | null;
  entrySession: string | null;
  /** sessions before the Bursary's assessment start are not assessed, and so not listed */
  unassessedBefore: boolean;
  rows: OutstandingRow[];
  summary: OutstandingSummary;
  reference?: string;
}

export const STATUS_WORDS: Record<OutstandingStatus, [string, Tone]> = {
  UNPAID: ["Unpaid", "bad"],
  PARTIALLY_PAID: ["Partially paid", "warn"],
  PAYMENT_PENDING: ["Payment pending", "info"],
  PAID: ["Paid", "ok"],
  CREDIT: ["Credit", "ok"],
  BEING_ASSESSED: ["Being assessed", "grey"],
};

export const num = (v: Money | null | undefined) => (v == null || v === "" ? 0 : Number(v));
export const naira = (v: Money | null | undefined) => `₦${num(v).toLocaleString("en-NG", { minimumFractionDigits: 0, maximumFractionDigits: 2 })}`;

/** the rows a student is shown first: what is owed, what a payment is pending on, what is still being assessed */
export function attentionRows(rows: OutstandingRow[]): OutstandingRow[] {
  return rows.filter((r) => num(r.balance) > 0 || r.status === "PAYMENT_PENDING" || r.status === "BEING_ASSESSED");
}

/** the rows settled, kept for the breakdown */
export function settledRows(rows: OutstandingRow[]): OutstandingRow[] {
  return rows.filter((r) => !(num(r.balance) > 0 || r.status === "PAYMENT_PENDING" || r.status === "BEING_ASSESSED"));
}

/** one line for the dashboard: nothing owed, or the total across the sessions owed */
export function summaryWords(d: OutstandingFees): string {
  const s = d.summary;
  if (num(s.outstanding) <= 0) return s.beingAssessed ? `Nothing owed on what is assessed; ${s.beingAssessed} period${s.beingAssessed === 1 ? "" : "s"} still being assessed.` : "No outstanding school fees.";
  const sessions = `${s.sessions} session${s.sessions === 1 ? "" : "s"}`;
  const periods = `${s.periods} fee period${s.periods === 1 ? "" : "s"}`;
  return `${naira(s.outstanding)} outstanding across ${sessions} (${periods})${num(s.pending) > 0 ? `; ${naira(s.pending)} awaits a payment started` : ""}.`;
}

/** the Pay now words for a row: what the reference generated would settle, or why none can be made */
export function payWords(r: OutstandingRow, d: Pick<OutstandingFees, "onlinePayment" | "windowOpen">): string | null {
  if (r.status === "PAYMENT_PENDING" && r.reference) return `Pay reference ${r.reference.reference}`;
  if (num(r.balance) <= 0) return null;
  if (r.status === "BEING_ASSESSED") return "Awaiting the Bursary's assessment";
  if (r.door === "HISTORICAL" && !d.onlinePayment) return "Settled with the Bursary";
  if (r.door === "CURRENT" && !d.windowOpen) return "Payment window closed";
  return `Pay ${naira(r.payAmount ?? r.balance)}`;
}

/** a reference's time left, for the pending row */
export function expiresWords(iso: string): string {
  const ms = new Date(iso).getTime() - Date.now();
  if (!Number.isFinite(ms) || ms <= 0) return "expired";
  const h = Math.floor(ms / 3_600_000), m = Math.floor((ms % 3_600_000) / 60_000);
  return h > 0 ? `expires in ${h} h ${m} min` : `expires in ${m} min`;
}

export const BREAKDOWN_HEAD = ["S/N", "Academic Session", "Fee Period", "Level", "Fee Description", "Amount Due (₦)", "Amount Paid (₦)", "Outstanding Balance (₦)", "Payment Status", "Reference"];

/** the breakdown's rows for Excel and PDF: S/N first and numeric, amounts as numbers */
export function breakdownRows(rows: OutstandingRow[]): (string | number)[][] {
  return rows.map((r, i) => [i + 1, r.session, r.period, r.level ?? "", r.description, r.due == null ? "" : num(r.due), num(r.paid),
    r.balance == null ? "" : num(r.balance), STATUS_WORDS[r.status]?.[0] ?? r.status, r.reference?.reference ?? ""]);
}
