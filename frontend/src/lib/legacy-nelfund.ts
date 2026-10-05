/** Old-portal NELFUND payments reconciled onto the wallet (V327): the shapes the API answers with, and the words the desk uses. */
import { LEGACY_FIELDS } from "./legacy-gst-import";
export { METHOD_WORD, dayOf, naira, num, whenAt } from "./legacy-gst";

/** the columns an old-portal NELFUND export carries: the GST export's, less the payment type and gateway, the status optional (a list of payments made is a list of successes) */
export const NELFUND_FIELDS = LEGACY_FIELDS
  .filter((f) => !["paymentType", "gateway", "gatewayReference", "semester"].includes(f.key))
  .map((f) => (f.key === "status" ? { ...f, required: false } : f));

export type NelfundRecStatus = "UNPROCESSED" | "MATCHED" | "POSTED" | "REQUIRES_REVIEW" | "REJECTED" | "DUPLICATE" | "UNMATCHED";

export const NEL_STATUS_WORD: Record<string, [string, "ok" | "info" | "bad" | "grey" | "warn"]> = {
  UNPROCESSED: ["Unprocessed", "grey"], MATCHED: ["Matched, not posted", "info"], POSTED: ["Posted to the wallet", "ok"],
  REQUIRES_REVIEW: ["Requires review", "warn"], UNMATCHED: ["Unmatched", "bad"], DUPLICATE: ["Duplicate", "grey"], REJECTED: ["Rejected", "bad"],
};
export const NEL_CODE_WORD: Record<string, string> = {
  AMBIGUOUS_STUDENT: "Identifiers point to more than one student", STUDENT_NOT_FOUND: "No student carries the identifiers",
  PAYMENT_FAILED: "The old portal recorded it as failed", PAYMENT_REVERSED: "Reversed on the old portal", PAYMENT_REFUNDED: "Refunded on the old portal",
  PAYMENT_PENDING: "Never completed on the old portal", PAYMENT_STATUS_UNKNOWN: "Status unknown", MISSING_AMOUNT: "No amount", MISSING_SESSION: "No session, and no date to place it",
  REFERENCE_ON_LEDGER: "Already on the wallet", REJECTED_BY_OFFICER: "Rejected by an officer",
};

export interface NelfundLegacyRow {
  id: string; import_id: string; import_reference: string; row_no: number; source_system: string; source_transaction_id: string | null; source_reference: string | null;
  source_student_id: string | null; matric_no: string | null; jamb_no: string | null; application_no: string | null; student_name: string | null;
  amount: number | null; currency: string; paid_at: string | null; paid_at_text: string | null; session: string | null; legacy_status: string | null; normalized_status: string; imported_at: string;
  status: NelfundRecStatus; reason_code: string | null; reason: string | null; student_id: string | null; match_method: string | null; match_confidence: string | null; candidates: string | null;
  wallet_entry_id: string | null; posted_at: string | null; posted_office: string | null; resolved_at: string | null; resolved_office: string | null; override_reason: string | null;
  surname: string | null; other_names: string | null; number: string | null; programme_code: string | null; level: number | null;
  wallet_reference: string | null; wallet_at: string | null; wallet_session: string | null; posted_by_name: string | null;
}
export interface NelfundCandidate { student_id: string; number: string; name: string; programme: string; method: string }
export interface NelfundLegacySummary {
  total_rows: number; matched: number; posted: number; requires_review: number; unmatched: number; duplicates: number; rejected: number; unprocessed: number;
  amount_received: number; amount_posted: number; amount_review: number; students_posted: number;
}
export interface NelfundImportRow {
  id: string; reference: string; file_name: string | null; session: string | null; uploaded_by_name: string | null; uploader_office: string | null; uploaded_at: string;
  total_rows: number; staged: number; already_staged: number; skipped: number; status: "STAGED" | "APPLIED"; applied_at: string | null; note: string | null;
  posted: number; matched: number; requires_review: number; unmatched: number; duplicates: number; rejected: number; posted_amount: number;
}
export interface NelfundLegacyPage {
  session: string | null; summary: NelfundLegacySummary;
  exceptions: { status: string; code: string; n: number; amount: number }[];
  imports: NelfundImportRow[];
  sessions: { session: string | null; rows: number; posted: number; open: number; amount: number }[];
}
export interface NelfundImportView {
  import: NelfundImportRow; summary: NelfundLegacySummary; exceptions: { status: string; code: string; n: number; amount: number }[];
  rows: NelfundLegacyRow[]; total: number; page: number; size: number;
  staging?: { total_rows: number; staged: number; already_staged: number; skipped: number }; dryRun?: boolean;
  applied?: { posted: number; amount: number; skipped: number };
}
export interface NelfundRowsPage { rows: NelfundLegacyRow[]; total: number; page: number; size: number }
export type NelfundRowDetail = NelfundLegacyRow & { raw: string };

/** the candidates column, as the API sends it (jsonb as text) */
export function candidatesOf(r: NelfundLegacyRow): NelfundCandidate[] {
  if (!r.candidates) return [];
  try { const v = JSON.parse(r.candidates); return Array.isArray(v) ? (v as NelfundCandidate[]) : []; } catch { return []; }
}
