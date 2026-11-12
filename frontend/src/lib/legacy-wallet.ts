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
  PAID_BEFORE_TOPUPS: "Paid from the old wallet before these top-ups: the top-ups since are the balance",
  NO_TOPUP_ON_FILE: "No top-up on file; rests on the old portal's statement",
  STATEMENT_DIFFERS: "The old portal's statement differs from the imported payments",
  CHANGED_AFTER_POSTING: "The balance reads otherwise since the posting (the imported payments or their date order)",
  CHANGED_AFTER_VERIFICATION: "The balance reads otherwise since the verification (the imported payments or their date order)",
};
/** V736: findings that explain a balance rather than hold it — not shown as faults */
export const INFO_REASONS = new Set(["PAID_BEFORE_TOPUPS"]);

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
  /** V736: what the old wallet paid beyond what had been topped up on file before it — from top-ups the export does not show */
  paid_before_topups?: number | string;
}

export interface LegacyWalletFigures {
  students: number; topups: number | string; topupCount: number; used: number | string; computed: number; computedAmount: number | string;
  verified: number; verifiedAmount: number | string; posted: number; postedAmount: number | string; applied: number | string; refunded: number | string;
  remaining: number | string; review: number; reviewUsed: number | string; noBalance: number; rejected: number; frozen: number; stated: number; differs: number;
  changed: number; orphanStudents: number; orphanAmount: number | string; lastComputed: string | null;
  /** V625: balances the Bursar returned for correction */
  returned?: number; returnedAmount?: number | string;
  /** V736: balances owed to the date order — top-ups after the wallet paid beyond what was on file — to verify or post */
  paidBefore?: number; paidBeforeAmount?: number | string;
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

const ngn = (v: unknown) => `₦${num(v).toLocaleString("en-GB", { minimumFractionDigits: 2 })}`;

/** how the balance was arrived at, in words; V736: with what the wallet paid before the top-ups on file, read in date order */
export function balanceWords(r: Pick<LegacyWalletRow, "topups" | "topup_count" | "used" | "used_count" | "stated_balance" | "stated_source" | "available" | "paid_before_topups">): string {
  if (r.stated_balance != null) return `As the old portal states it (${r.stated_source ?? "statement"}): ${ngn(r.stated_balance)}`;
  const base = `Topped up ${ngn(r.topups)} (${r.topup_count}) − paid from it ${ngn(r.used)} (${r.used_count})`;
  return num(r.paid_before_topups) > 0 ? `${base} + ${ngn(r.paid_before_topups)} it paid before these top-ups, read in date order` : base;
}

/** the table's "how" in a few words: the statement, the date order, or top-ups less what was paid (V736) */
export function howWords(r: Pick<LegacyWalletRow, "stated_balance" | "stated_source" | "paid_before_topups">): string {
  if (r.stated_balance != null) return `Old portal statement (${r.stated_source})`;
  return num(r.paid_before_topups) > 0 ? "Top-ups − paid, in date order" : "Top-ups − paid";
}

/** the address of the desk for a filter set */
export function legacyWalletHref(f: Record<string, string>): string {
  const qs = new URLSearchParams();
  for (const [k, v] of Object.entries(f)) if (v) qs.set(k, v);
  const q = qs.toString();
  return `/finance/legacy-wallet${q ? `?${q}` : ""}`;
}

export const whenDay = day;
