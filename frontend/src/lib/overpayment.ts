/** V519: what the Bursary decided for school fees a student paid beyond a session's charge, in the student's own words on the
 *  fees page (finance.student_overpayments). Node-tested. */

/** one decision on the student's overpaid school fees */
export interface StudentOverpayment {
  session: string; amount: number | string; decision: "CARRY" | "REFUND"; to_session: string | null; reference: string;
  refund_state: "PROPOSED" | "APPROVED" | "REJECTED" | "PAID" | null; decided_at: string | null;
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
  const where = o.refund_state === "PAID" ? "has been paid to you"
    : o.refund_state === "APPROVED" ? "is approved and waiting to be paid"
    : o.refund_state === "REJECTED" ? "was not approved; the Bursary will decide again"
    : "is waiting for the Bursary's approval";
  return {
    title: o.refund_state === "PAID" ? `Refund of ${amt} paid` : `Refund of ${amt} raised`,
    text: `You paid ${amt} more than your ${o.session} school fees. Its refund (${o.reference}) ${where}.`,
  };
}
