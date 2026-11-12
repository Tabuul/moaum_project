/**
 * V727: the inter-departmental transfer fee as the student's screens word it — the fee the Bursary states now, what is paid on this
 * portal and on the old portal, the balance, what to do next — read from GET /api/v1/me/transfer. Every figure is the server's
 * (people.transfer_entitlement); nothing here works out a fee or a balance.
 */
import { naira, num, type Money } from "./outstanding-fees.ts";

export { naira, num };
export type { Money };

type Tone = "ok" | "bad" | "warn" | "info" | "grey";

/** the states in which an application is live (people.transfer_live_states): one at a time */
export const LIVE_STATES = ["APPLIED", "FROM_OK", "TO_OK", "REG_OK", "RECOMMENDED", "APPROVED"] as const;

export function isLive(state: string | null | undefined): boolean {
  return !!state && (LIVE_STATES as readonly string[]).includes(state);
}

/** a reference drawn for the transfer fee (finance.payment_reference.purpose), never a school-fee one */
export function isTransferPurpose(purpose: string | null | undefined): boolean {
  return (purpose ?? "").startsWith("Inter-departmental transfer");
}

/** CLOSED: a declined, not recommended or withdrawn application, which owes nothing more */
export type TransferBand = "CLOSED" | "FEE_NOT_STATED" | "NO_FEE" | "NOT_PAID" | "PENDING" | "PART_PAID" | "SETTLED_IN_PARTS" | "PAID_IN_FULL" | "OVERPAID";
export type NextAction = "PAY_NOW" | "PAY_BALANCE" | "COMPLETE_PAYMENT" | "AWAIT_APPROVAL" | "NONE";

/** the live application's fee (or, with none live, the newest effected or declined one's) */
export interface TransferPayment {
  applicationId: string;
  state: string;
  stageLabel: string | null;
  feeDue: Money | null;
  portalPaid: Money;
  oldPortalPaid: Money;
  paidTotal: Money;
  balance: Money | null;
  excess: Money;
  payments: number;
  settled: boolean;
  pending: boolean;
  openReference: string | null;
  openAmount: Money | null;
  openExpiresAt: string | null;
  band: TransferBand | string;
  nextAction: NextAction | string;
}

/** a payment counted toward the application: this portal's (CONFIRMED, AWAITING_BANK) or the old portal's (its reconciliation status) */
export interface TransferPaymentMade {
  source: "PORTAL" | "OLD_PORTAL" | string;
  reference: string | null;
  payref: string | null;
  item: string | null;
  amount: Money;
  paidOn: string | null;
  status: string;
}

/** old-portal transfer payments awaiting an application */
export interface TransferCredit {
  total: Money;
  payments: { payref: string | null; item: string | null; amount: Money; paidOn: string | null }[];
}

/** the old portal's record of the live application, as its export gave it */
export interface TransferLegacy { legacyRef: string; appliedOn: string | null; stage: string | null; approvals: string | null; documents: string | null }

/** what the dashboard card reads of GET /api/v1/me/transfer */
export interface TransferFeeView {
  applications: { id: string; state: string; session?: string | null }[];
  fee: Money | null;
  payment?: TransferPayment | null;
  credit?: TransferCredit | null;
}

const BAND_WORDS: Record<string, [string, Tone]> = {
  CLOSED: ["Closed — nothing owed", "grey"],
  FEE_NOT_STATED: ["Fee not yet stated", "grey"],
  NO_FEE: ["No fee charged", "grey"],
  NOT_PAID: ["Not paid", "bad"],
  PENDING: ["Not paid · reference open", "info"],
  PART_PAID: ["Part paid", "warn"],
  SETTLED_IN_PARTS: ["Paid in full, in parts", "ok"],
  PAID_IN_FULL: ["Paid in full", "ok"],
  OVERPAID: ["Overpaid", "info"],
};

/** the payment status in words, and its tone */
export function bandWords(band: string | null | undefined): [string, Tone] {
  return BAND_WORDS[band ?? ""] ?? [band ? band.replace(/_/g, " ").toLowerCase() : "—", "grey"];
}

/** the band, where a caller has it: a CLOSED application owes nothing whatever else it carries */
type WithBand = { band?: TransferBand | string | null };

/** what is owed now: the balance of a live application; nothing on one effected, declined, not recommended or withdrawn (band CLOSED) */
export function owedNow(p: Pick<TransferPayment, "state" | "balance"> & WithBand): number {
  return isLive(p.state) && p.band !== "CLOSED" ? num(p.balance) : 0;
}

/** the pay button: PAY NOW before anything is paid, PAY OUTSTANDING BALANCE after a part payment; none once nothing is owed, while the
 *  fee is not stated, or when the application is no longer live (band CLOSED) */
export function payLabel(p: Pick<TransferPayment, "state" | "feeDue" | "paidTotal" | "balance"> & WithBand): "PAY NOW" | "PAY OUTSTANDING BALANCE" | null {
  if (p.feeDue == null || p.balance == null || owedNow(p) <= 0) return null;
  return num(p.paidTotal) > 0 ? "PAY OUTSTANDING BALANCE" : "PAY NOW";
}

/** the open reference to pay, when it is for what is owed now; one drawn for another figure is replaced by the server when the button
 *  is pressed (people.transfer_fee_reference) */
export function openForBalance(p: Pick<TransferPayment, "state" | "feeDue" | "paidTotal" | "balance" | "openReference" | "openAmount"> & WithBand): { reference: string; amount: number } | null {
  if (!p.openReference || p.openAmount == null || payLabel(p) == null) return null;
  return num(p.openAmount) === num(p.balance) ? { reference: p.openReference, amount: num(p.openAmount) } : null;
}

/** what follows a payment, by where the application stands */
function afterPaying(state: string, whole: boolean): string {
  if (state === "RECOMMENDED" || state === "APPROVED") return "The transfer is given effect on the register once the whole fee is paid.";
  if (state === "APPLIED" && !whole) return "Your current department acts once a payment is confirmed.";
  return "The Academic Office gives its final approval once the whole fee is paid.";
}

/** the next action in words, from the server's nextAction */
export function nextActionWords(p: Pick<TransferPayment, "state" | "feeDue" | "paidTotal" | "balance" | "openReference" | "openAmount" | "nextAction"> & WithBand): string {
  const owed = owedNow(p);
  if (p.feeDue == null && isLive(p.state)) return "Wait for the Bursary to state the transfer fee; you pay it then.";
  switch (p.nextAction) {
    case "PAY_NOW":
      return `Pay the transfer fee of ${naira(p.balance)}. ${afterPaying(p.state, false)}`;
    case "PAY_BALANCE":
      return `Pay the outstanding balance of ${naira(p.balance)}. ${afterPaying(p.state, true)}`;
    case "COMPLETE_PAYMENT": {
      const open = openForBalance(p);
      return open
        ? `Pay reference ${open.reference} (${naira(open.amount)}), or wait while the bank confirms a payment you have made.`
        : `Pay the outstanding balance of ${naira(p.balance)}. ${afterPaying(p.state, true)}`;
    }
    case "AWAIT_APPROVAL":
      return owed > 0
        ? `Nothing to do now: the offices are considering your application. Pay the ${naira(owed)} balance before the final approval.`
        : "Nothing to pay: the offices are considering your application.";
    case "NONE":
      return p.state === "EFFECTED" ? "None: the transfer is complete."
        : p.state === "DECLINED" ? "None: the application was declined; nothing is owed."
        : p.state === "NOT_RECOMMENDED" ? "None: the application was not recommended; nothing is owed."
        : p.state === "WITHDRAWN" ? "None: the application was withdrawn; nothing is owed."
        : p.band === "CLOSED" ? "None: the application is closed; nothing is owed." : "None.";
    default:
      return owed > 0 ? `Pay the outstanding balance of ${naira(owed)}.` : "—";
  }
}

/** an overpayment, said without a promise of a refund: the Bursary decides */
export function overpaidWords(p: Pick<TransferPayment, "excess">): string | null {
  const x = num(p.excess);
  return x > 0 ? `You paid ${naira(x)} more than the fee; the Bursary will contact you.` : null;
}

/** old-portal transfer payments awaiting an application: nothing is owed until one exists, and then they count toward its fee */
export function creditWords(c: Pick<TransferCredit, "total"> | null | undefined, where: "below" | "page" | "later"): string | null {
  if (!c || num(c.total) <= 0) return null;
  const paid = `You paid ${naira(c.total)} on the old portal toward a transfer`;
  if (where === "later") return `${paid}; it counts toward the fee once you apply.`;
  return `${paid} — ${where === "below" ? "apply below" : "apply on the transfer page"}; it counts toward the fee.`;
}

const MADE_WORDS: Record<string, [string, Tone]> = {
  CONFIRMED: ["Confirmed", "ok"],
  AWAITING_BANK: ["Awaiting the bank", "info"],
  LINKED: ["Counted", "ok"],
  AWAITING_APPLICATION: ["Awaiting an application", "info"],
  USED: ["Used by a restored transfer", "info"],
  UNMATCHED: ["With the Bursary", "warn"],
  NOT_COUNTED: ["Not counted", "grey"],
  OUT_OF_SCOPE: ["Before the current exercise", "grey"],
  REJECTED: ["Not counted", "grey"],
};

/** a payment's status in words, and its tone */
export function madeWords(status: string | null | undefined): [string, Tone] {
  return MADE_WORDS[status ?? ""] ?? [status ? status.replace(/_/g, " ").toLowerCase() : "—", "grey"];
}

export function sourceWord(source: string | null | undefined): string {
  return source === "OLD_PORTAL" ? "Old portal" : "This portal";
}

/** the dashboard's transfer card: shown for a live application, for old-portal payments awaiting one, and for an application closed
 *  (effected or declined) in the session the student is in — never for a transfer finished in an earlier session */
export function showTransferCard(v: TransferFeeView | null | undefined, session: string | null | undefined): boolean {
  if (!v) return false;
  if (v.credit && num(v.credit.total) > 0) return true;
  const p = v.payment;
  if (!p) return false;
  if (isLive(p.state)) return true;
  const app = v.applications.find((a) => a.id === p.applicationId);
  return !!session && app?.session === session;
}

/** the route an approved transfer took, for its letter: the four desks (current HOD → new HOD → Registry → the Academic Office, whose
 *  final approval effects it and stamps acad_at), or the committee and Senate (V070), given effect by the Registry */
export function letterRoute(app: { acad_at?: string | null }): "DESKS" | "SENATE" {
  return app.acad_at ? "DESKS" : "SENATE";
}
