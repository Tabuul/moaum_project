/** The funding wallet and the Bursary's desk, as the API states them (V033, V079). */
export interface WalletEntry { id: string; at: string; session: string; kind: string; amount: number; reference: string | null; note: string | null; source_code: string | null; source_name: string | null; nature: string | null; balance: number }
export interface FundStatus { session: string; number: string; state: string; reason: string | null; correctable: boolean; loaded_at: string }
export interface Eligibility { eligible: boolean; balance: number; cleared: boolean; arrears: boolean; pending: boolean; reason: string }
export interface Withdrawal { id: string; session: string; amount: number; bank_name: string; account_no: string; account_name: string; state: string; reason: string | null; requested_at: string; decided_at: string | null; paid_at: string | null; paid_ref: string | null }
export interface StudentWallet {
  session: string; balance: number; statement: WalletEntry[];
  position: { due: number; paid: number; balance: number; instalments_paid: number; paid_in_full: boolean; has_arrears: boolean };
  status: FundStatus | null;
  eligibility: Eligibility;
  withdrawal: Withdrawal | null;
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
