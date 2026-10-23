/** V647: school-fees history, JAMB number to matriculation number — what /api/v1/finance/fee-history-reconciliation answers */

export type Category = "MATCHED" | "AMBIGUOUS" | "NO_MATCH" | "ALREADY_RECONCILED" | "DUPLICATE" | "INVALID";

export interface HeldRow {
  id: string; original_identifier: string; identifier_type: string; purpose: "SCHOOL_FEES" | "GST" | "OTHER"; session: string | null; semester: number | null;
  amount: number | string | null; payref: string | null; held_status: string; category: Category; student_id: string | null; student_name: string | null;
  matric_no: string | null; programme: string | null; faculty_code: string | null; dept_code: string | null; candidates: number; first_seen: string; last_seen: string;
  payment_id: string | null; batch_ref: string | null;
}

export interface HeldPage {
  total: number; amount: number | string; byCategory: { category: Category; n: number; amount: number | string }[]; rows: HeldRow[]; page: number; size: number;
}

export interface Figures {
  held: number; heldAmount: number | string; byCategory: Partial<Record<Category, number>>; reconciled: number; resolvedByJamb: number; pending: number;
}

export interface Batch {
  ref: string; state: "PENDING_APPROVAL" | "APPROVED" | "REJECTED" | "WITHDRAWN"; reason: string; scanned: number; matched: number; ambiguous: number;
  unmatched: number; duplicate: number; amount: number | string; reconciled: number | null; reconciled_amount: number | string | null;
  initiated_by: string | null; initiated_by_id?: string; initiated_office: string; initiated_at: string; decided_by: string | null; decided_office: string | null;
  decided_at: string | null; decision_note: string | null; payments?: BatchPayment[] | number;
}

export interface BatchPayment {
  id: string; original_identifier: string; identifier_type: string; purpose: string; session: string | null; semester: number | null; amount: number | string | null;
  payref: string | null; status: string; payment_id: string | null; student_id: string | null; student_name: string | null; matric_no: string | null; payment_reference: string | null;
}

export const CATEGORY_WORDS: Record<Category, [string, "ok" | "warn" | "bad" | "grey" | "info"]> = {
  MATCHED: ["Matched", "ok"], AMBIGUOUS: ["Ambiguous", "warn"], NO_MATCH: ["No match", "bad"], ALREADY_RECONCILED: ["Already reconciled", "grey"],
  DUPLICATE: ["Duplicate", "grey"], INVALID: ["Invalid", "bad"],
};

export const CATEGORY_HELP: Record<Category, string> = {
  MATCHED: "The number names one student now: ready to reconcile",
  AMBIGUOUS: "The number names several students: never chosen automatically",
  NO_MATCH: "No student on the register has this number yet",
  ALREADY_RECONCILED: "Recorded under its student already",
  DUPLICATE: "Its old payment number is on record already: not recorded twice",
  INVALID: "No session or no amount on the row",
};

export const STATE_WORDS: Record<Batch["state"], [string, "ok" | "warn" | "bad" | "grey" | "info"]> = {
  PENDING_APPROVAL: ["Awaiting the Bursar", "warn"], APPROVED: ["Approved", "ok"], REJECTED: ["Rejected", "bad"], WITHDRAWN: ["Withdrawn", "grey"],
};

export const PURPOSE_WORDS: Record<string, string> = { SCHOOL_FEES: "School fees", GST: "GST fee", OTHER: "Other" };

export const IDENTIFIER_WORDS: Record<string, string> = {
  JAMB_NUMBER: "JAMB number", MATRIC_NUMBER: "Matriculation number", ADMISSION_NUMBER: "Admission number", APPLICATION_NUMBER: "Application number",
  STUDENT_ID: "Student ID", OTHER: "Other",
};

/** "PAY-RECON/2026/000001" → "2026/000001", the path the API takes */
export const batchPath = (ref: string) => ref.replace(/^PAY-RECON\//, "");
