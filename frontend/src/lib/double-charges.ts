/** V561: old-portal payments the bank may have charged twice, and payments the bank never received — the shapes
 *  /api/v1/finance/legacy-fees/double-charges and /api/v1/finance/payments-not-received return, and the words for them. */

type Kind = "grey" | "info" | "ok" | "bad" | "warn";

export interface DoubleCharge {
  student_id: string; number: string; name: string; programme_code: string | null; session: string; purpose: string; paid_on: string;
  amount: number | string; payments: number; refs: string[]; payrefs: string[]; check_id: string | null; verdict: Verdict | null;
  evidence: string | null; checked_by: string | null; checked_at: string | null; open_requests: number;
}
export interface DoubleCharges {
  session: string; sessions: string[]; count: number; unchecked: number; received: number; notReceived: number; waiting: number;
  atStake: number | string; rows: DoubleCharge[];
}
export type Verdict = "RECEIVED" | "NOT_RECEIVED";
export type PnrState = "PROPOSED" | "APPROVED" | "REJECTED" | "CANCELLED";
export interface NotReceived {
  request_ref: string; reference: string; kept_reference: string | null; student_id: string; number: string; name: string; session: string;
  purpose: string; amount: number | string; paid_on: string | null; payref: string | null; evidence: string; reason: string; state: PnrState;
  raised_by: string | null; raised_at: string; mine: boolean; decided_by: string | null; decided_at: string | null; decision_note: string | null;
  from_check: boolean;
}
export interface NotReceivedList { counts: Partial<Record<PnrState, number>>; withdrawn: number | string; rows: NotReceived[] }

export const VERDICT: Record<Verdict, [string, Kind, string]> = {
  RECEIVED: ["Every payment received", "ok", "The bank received each payment: the excess is real and may be carried or refunded"],
  NOT_RECEIVED: ["Not all received", "warn", "The records the bank never received are withdrawn, once another officer approves"],
};
export const PNR_STATE: Record<PnrState, [string, Kind]> = {
  PROPOSED: ["Waiting for approval", "warn"], APPROVED: ["Withdrawn", "ok"], REJECTED: ["Rejected", "bad"], CANCELLED: ["Cancelled", "grey"],
};

export function verdictWord(v: Verdict | null | undefined): [string, Kind] {
  return v ? [VERDICT[v][0], VERDICT[v][1]] : ["Not checked with the bank", "bad"];
}

/** PNR/2026/000014 → 2026/000014, the path the API files it under; anything else is refused */
export function pnrPath(ref: string): string | null {
  const m = /^PNR\/(\d{4})\/(\d{6})$/.exec(ref.trim());
  return m ? `${m[1]}/${m[2]}` : null;
}

/** the records named as never received: at least one, never all of them (the bank received one), each one of the group */
export function notReceivedOk(chosen: string[], refs: string[]): boolean {
  const set = new Set(chosen);
  return set.size >= 1 && set.size < refs.length && [...set].every((r) => refs.includes(r));
}

/** what a group puts at stake: every payment beyond the first */
export function atStake(g: { amount: number | string; payments: number }): number {
  return Number(g.amount) * Math.max(0, Number(g.payments) - 1);
}

/** the old portal's payment number of a record, or a dash when it holds none */
export function payrefOf(g: { refs: string[]; payrefs: string[] }, ref: string): string {
  const i = g.refs.indexOf(ref);
  return i >= 0 && g.payrefs[i] ? g.payrefs[i] : "—";
}

export const DOUBLE_CHARGE_HEADERS = ["Matric/admission no.", "Name", "Session", "Item", "Paid on", "Amount (₦)", "Payments", "References", "Payment numbers",
  "Bank check", "Evidence", "Checked by", "Withdrawal waiting"];

/** a possible double charge as an Excel row, in the order of DOUBLE_CHARGE_HEADERS */
export function doubleChargeRow(g: DoubleCharge): (string | number)[] {
  return [g.number, g.name, g.session, g.purpose, g.paid_on, Number(g.amount), Number(g.payments), g.refs.join(", "), g.payrefs.filter(Boolean).join(", "),
    verdictWord(g.verdict)[0], g.evidence ?? "", g.checked_by ?? "", g.open_requests ? "Yes" : "No"];
}
