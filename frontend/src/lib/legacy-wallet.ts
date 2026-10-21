/** The old portal's e-wallet reconciled (V583): the shapes /api/v1/finance/legacy-wallet returns, the words its states are shown in,
 *  and the report's rows (S/N first). The balance is computed by the server from the imported payments; nothing here works one out. */

export type LegacyWalletStatus = "COMPUTED" | "VERIFIED" | "POSTED" | "NO_BALANCE" | "REQUIRES_REVIEW" | "REJECTED" | "FROZEN" | "RETURNED";

export const STATUS_WORDS: Record<LegacyWalletStatus, [string, "ok" | "bad" | "warn" | "grey" | "info"]> = {
  COMPUTED: ["Computed: to verify", "info"], VERIFIED: ["Verified: to post", "warn"], POSTED: ["Posted to the wallet", "ok"],
  NO_BALANCE: ["No balance", "grey"], REQUIRES_REVIEW: ["Requires review", "bad"], REJECTED: ["Rejected", "bad"], FROZEN: ["Frozen", "grey"],
  RETURNED: ["Returned for correction", "bad"],
};
export const REASON_WORDS: Record<string, string> = {
  USED_EXCEEDS_TOPUPS: "Paid from the old wallet more than the top-ups on file",
  NO_TOPUP_ON_FILE: "No top-up on file; rests on the old portal's statement",
  STATEMENT_DIFFERS: "The old portal's statement differs from the imported payments",
  CHANGED_AFTER_POSTING: "The imported payments changed after the posting",
  CHANGED_AFTER_VERIFICATION: "The imported payments changed after the verification",
};

export interface LegacyWalletRow {
  id: string; student_id: string; student: string; matric_no: string | null; jamb_reg_no: string | null; student_status: string; programme: string | null;
  dept_code: string | null; department: string | null; faculty_code: string | null; faculty: string | null;
  topups: number | string; topup_count: number; used: number | string; used_count: number; first_topup_at: string | null; last_topup_at: string | null; last_topup_ref: string | null;
  session: string | null; stated_topups: number | string | null; stated_used: number | string | null; stated_refunds: number | string | null; stated_reversed: number | string | null;
  stated_balance: number | string | null; stated_source: string | null; stated_note: string | null; stated_by: string | null; stated_at: string | null;
  available: number | string; status: LegacyWalletStatus; reason_code: string | null; reason: string | null; computed_at: string;
  verified_by: string | null; verified_office: string | null; verified_at: string | null; verify_note: string | null;
  posted_by: string | null; posted_office: string | null; posted_at: string | null; batch_ref: string | null;
  decided_by: string | null; decided_at: string | null; decision_note: string | null;
  wallet_reference: string | null; applied: number | string; refunded: number | string; remaining: number | string | null;
}

export interface LegacyWalletFigures {
  students: number; topups: number | string; topupCount: number; used: number | string; computed: number; computedAmount: number | string;
  verified: number; verifiedAmount: number | string; posted: number; postedAmount: number | string; applied: number | string; refunded: number | string;
  remaining: number | string; review: number; reviewUsed: number | string; noBalance: number; rejected: number; frozen: number; stated: number; differs: number;
  changed: number; orphanStudents: number; orphanAmount: number | string; lastComputed: string | null;
  /** V625: balances the Bursar returned for correction */
  returned?: number; returnedAmount?: number | string;
  batches: { ref: string; posted_at: string; students: number; amount: number | string; skipped: number; posted_by: string | null; office: string | null }[];
}

export const num = (v: unknown) => Math.round(Number(v ?? 0) * 100) / 100;
const day = (v: unknown) => (v ? new Date(String(v)).toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }) : "");

/** the report's columns, S/N first (the brief's §54) */
export const REPORT_HEADERS = ["S/N", "Student", "Matric No.", "JAMB No.", "Legacy wallet reference", "Original top-up", "Historical usage", "Refund/Reversal",
  "Migrated balance", "Applied to fees", "Current balance", "Status", "Session", "Source", "Reconciliation batch"];

export function reportRows(rows: LegacyWalletRow[]): (string | number)[][] {
  return rows.map((r, i) => [i + 1, r.student, r.matric_no ?? "", r.jamb_reg_no ?? "", r.wallet_reference ?? r.last_topup_ref ?? "",
    num(r.stated_topups ?? r.topups), num(r.stated_used ?? r.used), num(Number(r.stated_refunds ?? 0) + Number(r.stated_reversed ?? 0)),
    r.status === "POSTED" ? num(r.available) : 0, num(r.applied), r.remaining == null ? "" : num(r.remaining),
    STATUS_WORDS[r.status]?.[0] ?? r.status, r.session ?? "", r.stated_source ? `Old portal statement: ${r.stated_source}` : "Old-fees export",
    r.batch_ref ?? ""]);
}

/** how the balance was arrived at, in words */
export function balanceWords(r: Pick<LegacyWalletRow, "topups" | "topup_count" | "used" | "used_count" | "stated_balance" | "stated_source" | "available">): string {
  if (r.stated_balance != null) return `As the old portal states it (${r.stated_source ?? "statement"}): ₦${num(r.stated_balance).toLocaleString("en-GB", { minimumFractionDigits: 2 })}`;
  return `Topped up ₦${num(r.topups).toLocaleString("en-GB", { minimumFractionDigits: 2 })} (${r.topup_count}) − paid from it ₦${num(r.used).toLocaleString("en-GB", { minimumFractionDigits: 2 })} (${r.used_count})`;
}

/** the address of the desk for a filter set */
export function legacyWalletHref(f: Record<string, string>): string {
  const qs = new URLSearchParams();
  for (const [k, v] of Object.entries(f)) if (v) qs.set(k, v);
  const q = qs.toString();
  return `/finance/legacy-wallet${q ? `?${q}` : ""}`;
}

export const whenDay = day;
