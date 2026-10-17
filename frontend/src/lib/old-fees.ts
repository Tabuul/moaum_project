/** V498: the old-portal payments on Old Fees History — the payments on record twice (by the retired Payment History Upload, or
 *  left by earlier uploads), and the reconciliation against the fee setup — as the screen and its Excel lists read them.
 *  Node-tested. */

export type ReconState = "UNDER" | "OVER" | "OVER_SETTLED" | "NO_FEE_STATED" | "MATCHED";

export const RECON_STATE: Record<ReconState, [string, "bad" | "warn" | "ok" | "info"]> = {
  UNDER: ["Paid less than due", "bad"],
  OVER: ["Paid more than due", "warn"],
  OVER_SETTLED: ["Overpaid: carried or refunded", "info"],
  NO_FEE_STATED: ["No fee stated", "info"],
  MATCHED: ["Matched", "ok"],
};

/** one student's reconciliation (finance.old_fees_reconciliation) */
export interface ReconRow {
  student_id: string; number: string; name: string; programme_code: string; faculty_code: string | null; level: number | null;
  due: number | string; paid: number | string; paid_old_s1: number | string; paid_old_s2: number | string; paid_old_session: number | string;
  paid_payment_history: number | string; paid_portal: number | string; old_payments: number; difference: number | string; state: ReconState;
  /** V506: carried in from the session before; what of an excess is settled, and how (CARRY, REFUND) */
  carried_in?: number | string; settled?: number | string; decision?: string | null;
}

export const RECON_HEADERS = ["Matric/admission no.", "Name", "Programme", "Faculty", "Level", "Due by the fee setup (₦)", "Paid (₦)",
  "Old portal, 1st semester (₦)", "Old portal, 2nd semester (₦)", "Old portal, whole session (₦)", "Payment History Upload (₦)", "Portal (₦)",
  "Old-portal payments", "Difference (₦)", "State", "Carried in (₦)", "Excess settled (₦)", "Settled by"];

const n = (v: number | string | null | undefined): number => {
  const x = Number(v ?? 0);
  return Number.isFinite(x) ? Math.round(x * 100) / 100 : 0;
};

/** a reconciliation row as an Excel row, in the order of RECON_HEADERS */
export function reconRow(r: ReconRow): (string | number)[] {
  return [r.number, r.name, r.programme_code, r.faculty_code ?? "", r.level ?? "", n(r.due), n(r.paid), n(r.paid_old_s1), n(r.paid_old_s2),
    n(r.paid_old_session), n(r.paid_payment_history), n(r.paid_portal), Number(r.old_payments ?? 0), n(r.difference), RECON_STATE[r.state]?.[0] ?? r.state,
    n(r.carried_in), n(r.settled), r.decision ? r.decision.split(", ").map((d) => DECISION[d as Decision] ?? d).join(", ") : ""];
}

export type DoubleKind = "PAYMENT_HISTORY" | "WHOLE_SESSION" | "UNNUMBERED";

/** why a record is a double, in words (finance.old_payment_doubles) */
export const DOUBLE_KIND: Record<DoubleKind, string> = {
  PAYMENT_HISTORY: "Recorded again by Payment History Upload",
  WHOLE_SESSION: "Whole-session record repeating the semester record (the semester record keeps the payment number)",
  UNNUMBERED: "Earlier upload's record repeating a numbered payment",
};

/** one old-portal payment on record twice (finance.old_payment_doubles) */
export interface DoubleRow {
  double_reference: string; double_kind: DoubleKind; kept_reference: string; kept_kind: "OLD_FEES_HISTORY" | "PAYMENT_HISTORY"; number: string; name: string;
  session: string; amount: number | string; paid_on: string; purpose: string; kept_purpose: string; linked: string | null;
}

export const DOUBLE_HEADERS = ["Matric/admission no.", "Name", "Session", "Day paid", "Amount (₦)", "Recorded twice as", "Its purpose",
  "Why it is a double", "Kept record", "Kept record's purpose", "Left because"];

export const LINKED_WORD: Record<string, string> = {
  DEFERMENT_FEE: "A deferment fee uses it",
  REFUND: "A refund names it",
  GST_RECONCILIATION: "The GST reconciliation uses it",
};

/** a double as an Excel row, in the order of DOUBLE_HEADERS */
export function doubleRow(d: DoubleRow): (string | number)[] {
  return [d.number, d.name, d.session, d.paid_on, n(d.amount), d.double_reference, d.purpose, DOUBLE_KIND[d.double_kind] ?? d.double_kind,
    d.kept_reference, d.kept_purpose, d.linked ? LINKED_WORD[d.linked] ?? d.linked : ""];
}

/** the withdrawal runs in batches until nothing is withdrawn or nothing is left (what the screen loops on) */
export function withdrawDone(r: { withdrawn: number; remaining: number }): boolean {
  return Number(r.remaining) <= 0 || Number(r.withdrawn) <= 0;
}

/** V498: what putting a mislabelled record right does (finance.legacy_mislabelled) */
export type MislabelAction = "RENAME" | "RELABEL" | "DOUBLE" | "UNKNOWN_CODE";

export const MISLABEL_ACTION: Record<MislabelAction, [string, "ok" | "warn" | "bad" | "info"]> = {
  RENAME: ["Recorded as what it is", "ok"],
  RELABEL: ["Its purpose put right", "ok"],
  DOUBLE: ["On record under its item: withdrawn", "warn"],
  UNKNOWN_CODE: ["Code not in the list: waits", "info"],
};

/** one record an earlier upload made under a code or an old label */
export interface MislabelledRow {
  reference: string; number: string; name: string; session: string; amount: number | string; paid_on: string; stored_purpose: string;
  item: string | null; target_reference: string | null; target_purpose: string | null; action: MislabelAction;
}

export const MISLABELLED_HEADERS = ["Matric/admission no.", "Name", "Session", "Day paid", "Amount (₦)", "Recorded as", "Reference",
  "What it is", "Put right as", "New reference", "What putting it right does"];

/** a mislabelled record as an Excel row, in the order of MISLABELLED_HEADERS */
export function mislabelledRow(m: MislabelledRow): (string | number)[] {
  return [m.number, m.name, m.session, m.paid_on, n(m.amount), m.stored_purpose, m.reference, m.item ?? "(code not in the list)",
    m.target_purpose ?? "", m.target_reference ?? "", MISLABEL_ACTION[m.action]?.[0] ?? m.action];
}

/** V502: what a record the retired Payment History Upload made, matched by nothing, counts as now (finance.payment_history_left) */
export type CountsAs = "SCHOOL_FEES" | "GST" | "OTHER";

export const COUNTS_AS: Record<CountsAs, string> = {
  SCHOOL_FEES: "School fees",
  GST: "The GST fee",
  OTHER: "Another item",
};

/** one record the retired Payment History Upload made that neither Old Fees History took over nor repeats another */
export interface LeftRow {
  reference: string; number: string; name: string; session: string; amount: number | string; paid_on: string;
  number_day: string | null; purpose: string; counts_as: CountsAs;
}

export const LEFT_HEADERS = ["Matric/admission no.", "Name", "Session", "Day on record", "Day its payment number carries", "Amount (₦)",
  "Reference", "Recorded as", "Counts as"];

/** a left record as an Excel row, in the order of LEFT_HEADERS */
export function leftRow(l: LeftRow): (string | number)[] {
  return [l.number, l.name, l.session, l.paid_on, l.number_day ?? "", n(l.amount), l.reference, l.purpose, COUNTS_AS[l.counts_as] ?? l.counts_as];
}

/** V506: what the Bursary decided for an overpaid student's excess (finance.overpayment_decision) */
export type Decision = "CARRY" | "REFUND";

export const DECISION: Record<Decision, string> = {
  CARRY: "Carried into the next session",
  REFUND: "Refund raised",
};

/** one overpaid student of a session (finance.overpaid) */
export interface OverpaidRow {
  student_id: string; number: string; name: string; programme_code: string; faculty_code: string | null; level: number | null;
  due: number | string; paid: number | string; excess: number | string; decision: Decision | null; decided: number | string | null;
  reference: string | null; to_session: string | null; decided_at: string | null; refund_state: string | null;
}

export const OVERPAID_HEADERS = ["Matric/admission no.", "Name", "Programme", "Faculty", "Level", "Due by the fee setup (₦)", "Paid (₦)",
  "Excess (₦)", "Decision", "Into session", "Reference", "Refund state", "Decided on"];

/** an overpaid student as an Excel row, in the order of OVERPAID_HEADERS */
export function overpaidRow(o: OverpaidRow): (string | number)[] {
  return [o.number, o.name, o.programme_code, o.faculty_code ?? "", o.level ?? "", n(o.due), n(o.paid), n(o.excess),
    o.decision ? DECISION[o.decision] ?? o.decision : "Not decided", o.to_session ?? "", o.reference ?? "", o.refund_state ?? "",
    o.decided_at ? o.decided_at.slice(0, 10) : ""];
}

/** the decisions run in batches until nothing is decided or nothing is left (what the screen loops on) */
export function decideDone(r: { carried: number; refunds: number; remaining: number }): boolean {
  return Number(r.remaining) <= 0 || Number(r.carried) + Number(r.refunds) <= 0;
}
