/** V519: what the Bursary decided for school fees a student paid beyond a session's charge, in the student's own words on the
 *  fees page (finance.student_overpayments). V781: a wallet credit said as one, and what is paid above the charge before it is
 *  decided (finance.student_excess). Node-tested. */

import { causeWord } from "./overpaid.ts";

/** one decision on the student's overpaid school fees: carried into the next session, refunded, or (V625) credited to the wallet */
export interface StudentOverpayment {
  session: string; amount: number | string; decision: "CARRY" | "REFUND" | "WALLET"; to_session: string | null; reference: string;
  refund_state: "PROPOSED" | "APPROVED" | "REJECTED" | "PAID" | null; decided_at: string | null;
  /** V528: the account given for a refund (the last four digits only), and whether the student may give or change it now */
  bank_name?: string | null; account_name?: string | null; account_last4?: string | null; account_given_at?: string | null;
  account_open?: boolean;
  /** V534: when the refund was paid and the bank transfer reference */
  paid_on?: string | null; paid_reference?: string | null;
}

const naira = (v: number | string) => {
  const n = Number(v ?? 0);
  const kobo = Math.round(n * 100) % 100 !== 0;
  return `₦${n.toLocaleString("en-NG", { minimumFractionDigits: kobo ? 2 : 0, maximumFractionDigits: 2 })}`;
};

/** the title and the sentence the fees page shows for a decision */
export function overpaymentWords(o: StudentOverpayment): { title: string; text: string } {
  const amt = naira(o.amount);
  if (o.decision === "CARRY") {
    return {
      title: `${amt} carried into ${o.to_session ?? "the next session"}`,
      text: `You paid ${amt} more than your ${o.session} school fees. It counts as school fees already paid in ${o.to_session ?? "the next session"} (reference ${o.reference}).`,
    };
  }
  // V781: credited to the wallet — a record of what was done, true after the money is used or refunded; what the wallet holds now, and what to
  // do with it, is said by the note the fees page shows while the wallet holds overpaid money (walletOverpaid) and by the Wallet page
  if (o.decision === "WALLET") {
    return {
      title: `${amt} credited to your wallet`,
      text: `You paid ${amt} more than your ${o.session} school fees. The Bursary credited it to your wallet (reference ${o.reference}). The Wallet page shows how much of it is still there and what it was used for.`,
    };
  }
  const paidOn = o.paid_on ? new Date(`${o.paid_on}T12:00:00`).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : null;
  const where = o.refund_state === "PAID" ? `has been paid to you${paidOn ? ` on ${paidOn}` : ""}${o.paid_reference ? ` (bank transfer reference ${o.paid_reference})` : ""}`
    : o.refund_state === "APPROVED" ? "is approved and waiting to be paid"
    : o.refund_state === "REJECTED" ? "was not approved; the Bursary will decide again"
    : "is waiting for the Bursary's approval";
  return {
    title: o.refund_state === "PAID" ? `Refund of ${amt} paid` : `Refund of ${amt} raised`,
    text: `You paid ${amt} more than your ${o.session} school fees. Its refund (${o.reference}) ${where}.`,
  };
}

/** V528: the account a refund is paid into, as the fees page says it (never more than the last four digits); null when none is given */
export function refundAccountWords(o: StudentOverpayment): string | null {
  if (o.decision !== "REFUND" || !o.account_last4) return null;
  const who = o.account_name ? `, ${o.account_name}` : "";
  return `${o.refund_state === "PAID" ? "Paid" : "To be paid"} into ${o.bank_name ?? "your bank"}${who}, account ending ${o.account_last4}.`;
}

/** V781: what the fees payload says of school fees paid above a session's charge and not yet all decided (finance.student_excess):
 *  the whole excess, what is decided of it, what is left, what a wallet credit request waits for, and — where the Bursary's list
 *  holds the student — the cause and what holds it. Every key is absent unless it applies. */
export interface StudentExcess {
  session: string;
  excess?: number | string | null; excessDecided?: number | string | null; excessRemaining?: number | string | null; excessRequested?: number | string | null;
  excessCause?: string | null; excessHolds?: string[] | null;
}

/** which of the five things the fees page says of an excess not yet decided; null when nothing is left to decide */
export type ExcessCase = "AHEAD" | "LATE_FEE" | "REQUESTED" | "PAID_TWICE" | "CHECKING";

const AHEAD_HOLDS = ["SEMESTER_NOT_CHARGED", "SEMESTER_NOT_STATED", "SPILLOVER_SEMESTER"];
const LATE_FEE_HOLDS = ["LATE_FEE_LAPSED", "LATE_FEE_POSSIBLE"];
const PAID_TWICE = ["PORTAL_TWICE", "OLD_AND_PORTAL", "OLD_TWICE"];

/** the first that applies: a semester of the session still to be charged (the money is that session's own), a late fee that may
 *  count against it, a wallet credit already requested, a repeated payment with nothing holding it, or — any other cause or hold, or
 *  none known yet — the Bursary still checking */
export function excessCase(f: StudentExcess): ExcessCase | null {
  if (Number(f.excessRemaining ?? 0) < 1) return null;
  const holds = f.excessHolds ?? [];
  if (holds.some((h) => AHEAD_HOLDS.includes(h))) return "AHEAD";
  if (holds.some((h) => LATE_FEE_HOLDS.includes(h))) return "LATE_FEE";
  if (Number(f.excessRequested ?? 0) > 0) return "REQUESTED";
  if (!holds.length && PAID_TWICE.includes(f.excessCause ?? "")) return "PAID_TWICE";
  return "CHECKING";
}

/** the title and the sentence the fees page shows for school fees paid above the charge before the Bursary has decided them; null
 *  when nothing is left to decide. The amount is what is left of the excess. */
export function excessWords(f: StudentExcess): { title: string; text: string; kind: "info" } | null {
  const which = excessCase(f);
  if (!which) return null;
  const amt = naira(f.excessRemaining ?? 0);
  switch (which) {
    case "AHEAD":
      return { kind: "info", title: `${amt} paid ahead`,
        text: `You have paid ${amt} more than the fees charged to you so far for ${f.session}. It counts towards the rest of this session's fees when they are charged.` };
    case "LATE_FEE":
      return { kind: "info", title: `${amt} above the fees shown`, text: "A late fee may count against it. The Bursary will tell you if any of it is to come back to you." };
    case "REQUESTED":
      return { kind: "info", title: `${amt} paid above your fees`, text: "The Bursary is crediting it to your wallet; you will be told when it is there." };
    case "PAID_TWICE":
      return { kind: "info", title: `${amt} paid above your fees`,
        text: `You paid your ${f.session} school fees more than once. The Bursary will credit ${amt} to your wallet for your next school fees, or refund it. There is nothing for you to do until you are told.` };
    default:
      return { kind: "info", title: `${amt} paid above the fees stated`, text: "The Bursary is checking it against your fees and will tell you what happens to it." };
  }
}

/** the line the staff pop-up shows under a student's fee tiles for what is paid above the charge and not yet decided: the cases of
 *  excessWords, said of the student and naming the desk; null when nothing is left to decide */
export function excessStaffWords(f: StudentExcess): string | null {
  switch (excessCase(f)) {
    case null: return null;
    case "AHEAD": return "Paid ahead: more than the fees charged so far for the session. It counts towards the rest of the session's fees when they are charged.";
    case "LATE_FEE": return "A late fee may count against it: the Bursary tells the student if any of it is to come back — Overpaid school fees desk.";
    case "REQUESTED": return "A wallet credit is requested: another Bursary officer approves it — Overpaid school fees desk.";
    case "PAID_TWICE": return `${causeWord(f.excessCause)}: the Bursary credits it to the wallet or refunds it — Overpaid school fees desk.`;
    default: return "Not decided: the Bursary is checking it against the fees — Overpaid school fees desk.";
  }
}
