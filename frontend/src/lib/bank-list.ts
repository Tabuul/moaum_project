/** V684: the bank's or the gateway's list of payments received, read for the payment numbers on it — the old portal's payment
 *  numbers (PR…) the possible double charges carry — with the amount and the day where the list shows them, and the shapes
 *  /api/v1/finance/legacy-fees/double-charges/bank-list and /legacy-fees/bank-lists return. Node-tested. */
import { readAmount, readDate } from "./bank-statement.ts";

type Kind = "grey" | "info" | "ok" | "bad" | "warn";

/** one payment number as it is sent: n the number, a the amount the list shows (when it shows one) */
export interface BankNumber { n: string; a?: string }

export interface BankListRead {
  numbers: BankNumber[];
  /** the rows read below the header (or every row, when the numbers were looked for in every cell) */
  rows: number;
  /** "column": a column names the payment number; "anywhere": no such column, so every cell was searched for a number */
  mode: "column" | "anywhere";
  header: { number: string | null; amount: string | null; date: string | null };
  /** the first and the last day the list's date column shows */
  from: string | null;
  to: string | null;
  problem: string | null;
}

const norm = (s: string) => (s ?? "").toLowerCase().replace(/[^a-z0-9]/g, "");
const NUMBER_HEADS = ["payref", "paymentref", "paymentreference", "paymentrefno", "paymentnumber", "paymentno", "transactionreference", "transactionref",
  "transref", "txnref", "txnreference", "merchantreference", "merchantref", "customerreference", "custreference", "customerref", "reference",
  "referenceno", "referencenumber", "refno", "ref", "receiptno", "receiptnumber"];
const AMOUNT_HEADS = ["amount", "amountpaid", "paidamount", "transactionamount", "credit", "creditamount", "totalamount", "amountngn"];
const DATE_HEADS = ["paymentdate", "datepaid", "paidon", "transactiondate", "transdate", "valuedate", "settlementdate", "date", "txndate"];

/** the column of each kind in a header row (the first name on each list that a cell carries), or -1 */
function columnsOf(row: string[]): { number: number; amount: number; date: number } {
  const cells = row.map((c) => norm(String(c ?? "")));
  const first = (names: string[]) => { for (const n of names) { const i = cells.indexOf(n); if (i >= 0) return i; } return -1; };
  return { number: first(NUMBER_HEADS), amount: first(AMOUNT_HEADS), date: first(DATE_HEADS) };
}

/** a payment number as the old portal keeps it: no spaces, upper case */
export function cleanNumber(v: string): string {
  return String(v ?? "").replace(/\s+/g, "").toUpperCase();
}

/** the tokens of a cell that could be a payment number: at least eight letters and digits (hyphens allowed), one a digit — a
 *  narration's words, dates and amounts fall away; the portal matches only the numbers it holds */
export function numbersIn(cell: string): string[] {
  return (String(cell ?? "").match(/[A-Za-z0-9][A-Za-z0-9-]{7,39}/g) ?? []).filter((t) => /\d/.test(t)).map(cleanNumber);
}

/** the list's payment numbers: from the column naming them (with the amount and day where the list has those columns), or, where
 *  no column names them, every number-like token of every cell; each number once, its largest amount kept */
export function readBankList(rows: string[][]): BankListRead {
  const empty = { numbers: [], rows: 0, header: { number: null, amount: null, date: null }, from: null, to: null };
  const lines = rows.filter((r) => r.some((c) => String(c ?? "").trim() !== ""));
  if (!lines.length) return { ...empty, mode: "column", problem: "The file has no rows." };
  const hi = lines.slice(0, 40).findIndex((r) => columnsOf(r).number >= 0);
  const found = new Map<string, number | null>();
  const add = (n: string, a: number | null) => {
    if (!n) return;
    const had = found.get(n);
    found.set(n, had == null ? a : a == null ? had : Math.max(had, a));
  };
  let from: string | null = null;
  let to: string | null = null;
  if (hi >= 0) {
    const head = lines[hi];
    const col = columnsOf(head);
    const body = lines.slice(hi + 1);
    for (const r of body) {
      // every dated row shows a day the list covers, a row without a number too
      const d = col.date >= 0 ? readDate(String(r[col.date] ?? "")) : "";
      if (d) { if (!from || d < from) from = d; if (!to || d > to) to = d; }
      const n = cleanNumber(String(r[col.number] ?? ""));
      if (!n) continue;
      const amt = col.amount >= 0 ? readAmount(String(r[col.amount] ?? "")).replace(/^-/, "") : "";
      add(n, amt && Number(amt) > 0 ? Number(amt) : null);
    }
    const numbers = [...found].map(([n, a]) => (a == null ? { n } : { n, a: String(a) }));
    return {
      numbers, rows: body.length, mode: "column", from, to,
      header: { number: String(head[col.number] ?? ""), amount: col.amount >= 0 ? String(head[col.amount] ?? "") : null, date: col.date >= 0 ? String(head[col.date] ?? "") : null },
      problem: numbers.length ? null : `The column “${String(head[col.number] ?? "")}” holds no payment number.`,
    };
  }
  for (const r of lines) for (const c of r) for (const n of numbersIn(String(c ?? ""))) add(n, null);
  const numbers = [...found].map(([n]) => ({ n }));
  return { ...empty, numbers, rows: lines.length, mode: "anywhere", problem: numbers.length ? null : "No payment number was found in the file." };
}

export type BankOutcome = "RECEIVED" | "NOT_RECEIVED" | "NONE_FOUND" | "AMOUNT_SHORT" | "NO_NUMBER" | "CHECKED" | "OUTSIDE_PERIOD" | "REFUSED";

export const OUTCOME: Record<BankOutcome, [string, Kind, string]> = {
  RECEIVED: ["Every payment on the list", "ok", "Checked: the bank received each payment, so the excess is real"],
  NOT_RECEIVED: ["Not all on the list", "warn", "Checked: the records not on the list are raised for withdrawal, for another officer to approve"],
  NONE_FOUND: ["None on the list", "grey", "The list says nothing about these payments; check them by hand"],
  AMOUNT_SHORT: ["Less on the list", "bad", "The list shows less than the record holds; check by hand"],
  NO_NUMBER: ["No payment number", "grey", "A record carries no payment number to look for; check by hand"],
  CHECKED: ["Checked already", "info", "Checked with the bank before, or a withdrawal waits"],
  OUTSIDE_PERIOD: ["Outside the days", "grey", "Paid outside the days the list covers"],
  REFUSED: ["Withdrawal refused", "bad", "The withdrawal was refused (several payments in one record, linked, swapped, or the excess decided); left unchecked"],
};

export interface BankGroup {
  student_id: string; number: string | null; name: string | null; session: string; purpose: string; paid_on: string; amount: number | string;
  payments?: number; refs: string[]; payrefs: string[]; outcome: BankOutcome; found: string[]; missing: string[]; refusal?: string | null;
  withdrawals?: { requestRef: string; reference: string; state: "PROPOSED" | "APPROVED" | "REJECTED" | "CANCELLED" }[];
}
export interface BankPreview {
  session: string; numbers: number; counts: Partial<Record<BankOutcome, number>>; toWithdraw: number; toWithdrawAmount: number | string; rows: BankGroup[];
}
export interface BankListRow {
  list_ref: string; session: string | null; covers_from: string; covers_to: string; file_name: string | null; rows_read: number; numbers_read: number;
  with_amounts: boolean; evidence: string; note: string | null; outcomes: Partial<Record<BankOutcome | "raised" | "raised_amount", number>>;
  checked_by: string | null; checked_at: string; mine: boolean; withdrawals: Partial<Record<"PROPOSED" | "APPROVED" | "REJECTED" | "CANCELLED", number>>;
}

/** what the preview leaves for a check by hand */
export function leftByHand(c: Partial<Record<BankOutcome, number>>): number {
  return (c.NONE_FOUND ?? 0) + (c.AMOUNT_SHORT ?? 0) + (c.NO_NUMBER ?? 0) + (c.REFUSED ?? 0);
}

/** BLC/2026/000014 → 2026/000014, the path the API files it under; anything else is refused */
export function blcPath(ref: string): string | null {
  const m = /^BLC\/(\d{4})\/(\d{6})$/.exec(ref.trim());
  return m ? `${m[1]}/${m[2]}` : null;
}

export const BANK_GROUP_HEADERS = ["Matric/admission no.", "Name", "Session", "Item", "Paid on", "Amount (₦)", "Records", "Payment numbers", "On the list",
  "Not on the list", "Outcome", "Withdrawals"];

/** a judged group as an Excel row, in the order of BANK_GROUP_HEADERS */
export function bankGroupRow(g: BankGroup): (string | number)[] {
  return [g.number ?? "", g.name ?? "", g.session, g.purpose, g.paid_on, Number(g.amount), g.refs.join(", "), g.payrefs.filter(Boolean).join(", "),
    g.found.join(", "), g.missing.join(", "), OUTCOME[g.outcome][0] + (g.refusal ? ` (${g.refusal})` : ""),
    (g.withdrawals ?? []).map((w) => `${w.requestRef} ${w.state.toLowerCase()}`).join(", ")];
}
