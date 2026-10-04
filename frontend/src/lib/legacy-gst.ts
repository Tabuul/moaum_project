/** Old-portal GST payment reconciliation (V323) as the screens read it. */
import type { LegacySummary } from "./gst";

export type ReconStatus = "UNPROCESSED" | "MATCHED" | "RECONCILED" | "REQUIRES_REVIEW" | "REJECTED" | "DUPLICATE" | "UNMATCHED";

export interface LegacyImport {
  id: string; reference: string; source_system: string; file_name: string | null; session: string | null; uploaded_by: string | null; uploaded_by_name?: string | null; uploader_office: string | null;
  uploaded_at: string; total_rows: number; staged: number; already_staged: number; skipped: number; status: "STAGED" | "APPLIED"; applied_at: string | null; note: string | null;
  reconciled: number; matched: number; requires_review: number; unmatched: number; duplicates: number; rejected: number; reconciled_amount: number;
}
export interface Candidate { student_id: string; number: string; name: string; programme: string; method: string }
export interface LegacyRowView {
  id: string; import_id: string; import_reference: string; row_no: number; source_system: string; source_transaction_id: string | null; source_reference: string | null; gateway: string | null;
  gateway_reference: string | null; source_student_id: string | null; matric_no: string | null; jamb_no: string | null; application_no: string | null; student_name: string | null;
  payment_type: string | null; maps_to: string | null; amount: number | null; currency: string; paid_at: string | null; paid_at_text: string | null; session: string | null; semester: number | null;
  legacy_status: string | null; normalized_status: string; imported_at: string; status: ReconStatus; reason_code: string | null; reason: string | null; student_id: string | null;
  match_method: string | null; match_confidence: string | null; candidates: Candidate[]; fee_amount: number | null; payment_reference_id: string | null; reconciled_at: string | null;
  reconciled_office: string | null; resolved_at: string | null; resolved_office: string | null; override_reason: string | null; surname: string | null; other_names: string | null;
  number: string | null; programme_code: string | null; level: number | null; ledger_reference: string | null; ledger_receipt: string | null; ledger_confirmed_at: string | null;
  ledger_purpose: string | null; reconciled_by_name: string | null;
}
export interface RowsPage { total: number; page: number; size: number; rows: LegacyRowView[] }
export interface ExceptionRow { status: ReconStatus; code: string; n: number; amount: number }
export interface LegacySummaryPage {
  session: string | null; summary: LegacySummary; exceptions: ExceptionRow[]; imports: LegacyImport[];
  sessions: { session: string | null; rows: number; reconciled: number; open: number; amount: number }[];
  fees: { session: string; amount: number; level: number | null; entry_mode: string | null; faculty_code: string | null; programme_code: string | null }[]; now: string;
}
export interface ImportView extends RowsPage { import: LegacyImport; summary: LegacySummary; exceptions: ExceptionRow[]; staging?: { total_rows: number; staged: number; already_staged: number; skipped: number }; dryRun?: boolean; applied?: { reconciled: number; duplicates: number; amount: number } }
export interface RowDetail {
  row: LegacyRowView; raw: Record<string, unknown>;
  standing?: { state: string; entitled: boolean; fee: number; paid: number; reference: string | null; source: string | null; paid_at: string | null };
  ledger?: { id: string; reference: string; purpose: string; amount: number; confirmed_at: string; channel: string | null; receipt_no: string | null; note: string | null }[];
}

export const STATUS_WORD: Record<string, [string, "ok" | "bad" | "warn" | "grey" | "info"]> = {
  UNPROCESSED: ["Unprocessed", "grey"], MATCHED: ["Matched — ready", "info"], RECONCILED: ["Reconciled", "ok"], REQUIRES_REVIEW: ["Requires review", "warn"],
  REJECTED: ["Rejected", "bad"], DUPLICATE: ["Duplicate", "grey"], UNMATCHED: ["Unmatched", "bad"],
};
export const CODE_WORD: Record<string, string> = {
  STUDENT_NOT_FOUND: "Student not found", AMBIGUOUS_STUDENT: "Ambiguous student", PAYMENT_FAILED: "Invalid payment (failed)", PAYMENT_REFUNDED: "Refunded", PAYMENT_REVERSED: "Reversed",
  PAYMENT_PENDING: "Payment pending", PAYMENT_STATUS_UNKNOWN: "Payment status unknown", UNKNOWN_PAYMENT_TYPE: "Unknown payment type", MISSING_SESSION: "Missing session", INVALID_SESSION: "Wrong session",
  MISSING_AMOUNT: "Missing amount", EXISTING_ENTITLEMENT: "Duplicate — entitlement already held", REFERENCE_ON_LEDGER: "Duplicate — reference on the ledger", NO_FEE_FOR_SESSION: "No fee stated for the session",
  PARTIAL_PAYMENT: "Invalid amount — below the fee", AMOUNT_ABOVE_FEE: "Invalid amount — above the fee", POSSIBLE_RELABEL: "Same money on the ledger as school fees", REJECTED_BY_OFFICER: "Rejected by an officer",
  RELABELLED: "Relabelled from school fees",
};
export const METHOD_WORD: Record<string, string> = {
  STUDENT_ID: "Exact student ID", MATRIC_NO: "Exact matriculation number", JAMB_NO: "Exact JAMB number", APPLICATION_NO: "Exact application number", LEGACY_ID_CROSSWALK: "Old-portal id on the crosswalk", MANUAL: "Finance officer selected",
};
export const naira = (n: number | string | null | undefined) => (n == null ? "—" : "₦" + Number(n).toLocaleString("en-NG", { maximumFractionDigits: 2 }));
export const num = (n: number | string | null | undefined) => Number(n ?? 0).toLocaleString();
export const whenAt = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
export const dayOf = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }) : "—");
