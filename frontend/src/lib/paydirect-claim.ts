/**
 * V480: the receipt a payer reports for a Pay on Quickteller payment Interswitch has not reported — the Payment Log Id, the
 * day paid, the amount and where. It confirms nothing; it tells the Bursary what to look for. Kept apart from the form so the
 * checks and the ask-list rows are tested with node.
 */

export type ClaimChannel = "QUICKTELLER" | "BANK" | "OTHER";

export const CHANNEL_LABEL: Record<ClaimChannel, string> = {
  QUICKTELLER: "Quickteller (website or app)",
  BANK: "At a bank",
  OTHER: "Somewhere else",
};

/**
 * V490: where a receipt stands. CONFIRMED — the reference is paid; NOT_FOUND — the Bursary asked Interswitch and it has no
 * such payment (with its note); ELSEWHERE — Interswitch reported the Payment Log Id against another reference; SEEN —
 * Interswitch reported it for this reference without settling it (short of the amount); WAITING — nothing yet.
 */
export type ClaimState = "CONFIRMED" | "NOT_FOUND" | "ELSEWHERE" | "SEEN" | "WAITING";

export const CLAIM_STATE: Record<ClaimState, [string, "ok" | "bad" | "warn" | "info" | "grey"]> = {
  CONFIRMED: ["Confirmed", "ok"],
  NOT_FOUND: ["Not found at Interswitch", "bad"],
  ELSEWHERE: ["Reported against another reference", "bad"],
  SEEN: ["Reported, not settled", "warn"],
  WAITING: ["Waiting for Interswitch", "warn"],
};

/** the receipt as the University's record keeps it */
export interface Claim {
  reference: string;
  payment_log_id: string;
  paid_on: string;
  amount: number | string | null;
  channel: ClaimChannel | null;
  note: string | null;
  claimed_at: string | number;
  /** V490: where it stands, and the Bursary's note when it is not found */
  state?: ClaimState;
  not_found_at?: string | null;
  not_found_note?: string | null;
}

/** what the payer is told about their receipt, by its state (V490) */
export function claimWords(c: Pick<Claim, "state" | "not_found_note">): { title: string; body: string; correct: boolean } {
  switch (c.state) {
    case "NOT_FOUND":
      return { title: "The Bursary could not find this payment at Interswitch", correct: true,
        body: `${c.not_found_note ?? ""} Check the Payment Log Id on your receipt and correct it if it was mistyped; otherwise contact the Bursary with the receipt and your bank's debit details. Do not pay the same reference twice.`.trim() };
    case "ELSEWHERE":
      return { title: "Interswitch reported this receipt against another reference", correct: false,
        body: "The money reached the University under a different number from this reference. The Bursary has it on its list and settles it; you do not need to pay again." };
    case "SEEN":
      return { title: "Interswitch reported this receipt but it did not settle the reference", correct: false,
        body: "The payment Interswitch reported for this reference is short of what it asks, or was not settled. The Bursary has it on its list and will contact you; do not pay the same reference again." };
    default:
      return { title: "Receipt reported", correct: true,
        body: "The Bursary looks for it in Interswitch's report and asks Interswitch to re-send it; it is confirmed here when it arrives." };
  }
}

export interface ClaimForm {
  paymentLogId: string;
  paidOn: string;
  amount: string;
  channel: ClaimChannel | "";
  note: string;
}

/** a calendar day (YYYY-MM-DD, as the API sends the day paid) as the receipt reads it: 15 Oct 2026 */
export function paidDay(iso: string | null | undefined): string {
  if (!iso) return "";
  const d = new Date(`${String(iso).slice(0, 10)}T12:00:00Z`);
  return Number.isNaN(d.getTime()) ? String(iso) : d.toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" });
}

/** today as a Lagos calendar day, YYYY-MM-DD */
export function lagosToday(now: Date = new Date()): string {
  return now.toLocaleDateString("en-CA", { timeZone: "Africa/Lagos" });
}

function daysBetween(a: string, b: string): number {
  return Math.round((Date.parse(`${b}T00:00:00Z`) - Date.parse(`${a}T00:00:00Z`)) / 86_400_000);
}

/** what stops the form being sent, field by field — the same rules the database holds (finance.paydirect_claim_set) */
export function claimProblems(f: ClaimForm, today: string = lagosToday()): Partial<Record<keyof ClaimForm, string>> {
  const out: Partial<Record<keyof ClaimForm, string>> = {};
  if (f.paymentLogId.trim().length < 3) out.paymentLogId = "Enter the Payment Log Id printed on the receipt.";
  else if (f.paymentLogId.trim().length > 40) out.paymentLogId = "The Payment Log Id is at most 40 characters.";
  if (!/^\d{4}-\d{2}-\d{2}$/.test(f.paidOn)) out.paidOn = "Enter the day you paid.";
  else if (f.paidOn > today) out.paidOn = "The day paid cannot be after today.";
  else if (daysBetween(f.paidOn, today) > 120) out.paidOn = "Only a payment made in the last four months can be reported here.";
  if (f.amount.trim() !== "") {
    const n = Number(f.amount.replace(/[₦,\s]/g, ""));
    if (!Number.isFinite(n) || n <= 0) out.amount = "Enter the amount on the receipt, or leave it out.";
  }
  if (f.note.length > 500) out.note = "Keep the note to 500 characters.";
  return out;
}

/** the body the API takes (POST /api/v1/payments/claims) */
export function claimBody(reference: string, f: ClaimForm) {
  const amount = f.amount.trim() === "" ? null : Number(f.amount.replace(/[₦,\s]/g, ""));
  return {
    reference,
    paymentLogId: f.paymentLogId.trim(),
    paidOn: f.paidOn,
    amount,
    channel: f.channel === "" ? null : f.channel,
    note: f.note.trim() === "" ? null : f.note.trim(),
  };
}

/** one row of the list the Bursary sends Interswitch (finance.paydirect_ask_list) */
export interface AskRow {
  reference: string;
  payer: string | null;
  number: string | null;
  due: number | string | null;
  opened_at: string | number | null;
  payment_log_id: string | null;
  paid_on: string | null;
  paid_amount: number | string | null;
  channel: ClaimChannel | null;
}

export const ASK_HEADERS = ["Reference (customer reference)", "Payer", "Matric/application no.", "Amount due (₦)", "Opened on Quickteller",
  "Payment Log Id (payer's receipt)", "Day paid", "Amount paid (₦)", "Where paid"];

function num(v: number | string | null): number | string {
  if (v === null || v === "") return "";
  const n = Number(v);
  return Number.isFinite(n) ? n : String(v);
}

function stamp(v: string | number | null): string {
  if (v === null || v === "") return "";
  const d = new Date(v);
  if (Number.isNaN(d.getTime())) return String(v);
  return d.toLocaleString("en-GB", { timeZone: "Africa/Lagos", day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });
}

/** the ask list as spreadsheet rows, in the order of ASK_HEADERS */
export function askRows(rows: AskRow[]): (string | number)[][] {
  return rows.map((r) => [r.reference, r.payer ?? "", r.number ?? "", num(r.due), stamp(r.opened_at),
    r.payment_log_id ?? "", r.paid_on ?? "", num(r.paid_amount), r.channel ? CHANNEL_LABEL[r.channel] ?? r.channel : ""]);
}
