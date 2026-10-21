/**
 * V607: an Old Fees History upload by the Students Account Officer, held for the Bursar's approval — its states in words and the
 * import's totals added up across the parts the Bursar checks (each part is checked on its own: a payment repeated across parts
 * reads as new in each).
 */

export type UploadState = "DRAFT" | "PENDING" | "APPROVING" | "APPROVED" | "REJECTED" | "WITHDRAWN";

export interface OldFeesUpload {
  id: string; ref: string; state: UploadState; file_name: string | null; note: string | null; parts: number; row_count: number;
  students: number | null; sessions: string | null; amount: number | string | null; uploaded_by: string; uploaded_by_name: string | null;
  uploaded_at: string; submitted_at: string | null; decided_by: string | null; decided_by_name: string | null; decided_at: string | null;
  decision_note: string | null; applied_parts: number; result: ImportTotals | null; completed_at: string | null; item_codes: number;
}

/** what finance.import_legacy_payments counts, added up */
export type ImportTotals = Partial<Record<(typeof TOTAL_KEYS)[number], number>> & { duplicate_sample?: string[] };

export const TOTAL_KEYS = ["rows", "cleared", "no_student", "no_due", "duplicates", "corrected", "undated", "matched", "separate", "taken_over"] as const;

export const STATE_WORD: Record<UploadState, [string, "grey" | "info" | "ok" | "bad" | "warn"]> = {
  DRAFT: ["Being sent", "grey"],
  PENDING: ["Waiting for the Bursar", "warn"],
  APPROVING: ["Being loaded", "info"],
  APPROVED: ["Approved and loaded", "ok"],
  REJECTED: ["Rejected", "bad"],
  WITHDRAWN: ["Withdrawn", "grey"],
};

/** the totals of one more checked part added to those so far (the duplicate sample kept to fifty) */
export function addTotals(a: ImportTotals, b: ImportTotals): ImportTotals {
  const out: ImportTotals = {};
  for (const k of TOTAL_KEYS) out[k] = Number(a[k] ?? 0) + Number(b[k] ?? 0);
  out.duplicate_sample = [...(a.duplicate_sample ?? []), ...(b.duplicate_sample ?? [])].slice(0, 50);
  return out;
}

/** the Bursar may act on an upload while it waits or is being loaded; the officer withdraws their own while it waits */
export function mayDecide(office: string | null | undefined, u: Pick<OldFeesUpload, "state">): boolean {
  return office === "bursar" && (u.state === "PENDING" || u.state === "APPROVING");
}

export function mayWithdraw(office: string | null | undefined, u: Pick<OldFeesUpload, "state">): boolean {
  return office === "studentaccounts" && (u.state === "PENDING" || u.state === "DRAFT");
}
