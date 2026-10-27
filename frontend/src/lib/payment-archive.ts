/**
 * Payments archived for review (V670): the words and shapes the Archived payments screens share. Every figure, state, signal and
 * refusal is the server's (finance.archive_payment, finance.payment_archive_propose, finance.payment_archive_decide); these only
 * say them.
 */

export type ArchiveState = "ARCHIVED" | "UNDER_REVIEW" | "PENDING_BURSAR_APPROVAL" | "RETURNED" | "RECONCILED" | "DUPLICATE_CONFIRMED" | "NOT_RECEIVED";
export type ArchiveOutcome = "RESTORE" | "REALLOCATE" | "DUPLICATE" | "NOT_RECEIVED";
export type ArchiveSource = "DESK" | "DUPLICATE_WITHDRAWAL" | "NOT_RECEIVED_WITHDRAWAL";
type Kind = "ok" | "info" | "bad" | "grey" | "warn";

export const STATE_WORDS: Record<ArchiveState, [kind: Kind, word: string]> = {
  ARCHIVED: ["warn", "Archived"],
  UNDER_REVIEW: ["warn", "Under review"],
  PENDING_BURSAR_APPROVAL: ["info", "Pending Bursar approval"],
  RETURNED: ["info", "Returned for correction"],
  RECONCILED: ["ok", "Reconciled"],
  DUPLICATE_CONFIRMED: ["grey", "Duplicate confirmed"],
  NOT_RECEIVED: ["bad", "Never received"],
};

export const ARCHIVE_STATES = Object.keys(STATE_WORDS) as ArchiveState[];
export const OPEN_STATES: ArchiveState[] = ["ARCHIVED", "UNDER_REVIEW", "PENDING_BURSAR_APPROVAL", "RETURNED"];

export function isOpen(state: string | null | undefined): boolean {
  return (OPEN_STATES as string[]).includes(String(state ?? ""));
}

/** the verification status the brief names, from the archive's state */
export function verificationWords(state: ArchiveState | string): [kind: Kind, words: string] {
  if (state === "PENDING_BURSAR_APPROVAL") return ["info", "VERIFIED — READY FOR RECONCILIATION"];
  if (state === "RECONCILED") return ["ok", "RECONCILED"];
  if (state === "DUPLICATE_CONFIRMED") return ["grey", "DUPLICATE CONFIRMED — EXCLUDED FOR GOOD"];
  if (state === "NOT_RECEIVED") return ["bad", "NEVER RECEIVED — EXCLUDED FOR GOOD"];
  return ["warn", "NOT YET VERIFIED"];
}

export const OUTCOME_WORDS: Record<ArchiveOutcome, [title: string, words: string]> = {
  RESTORE: ["Restore to the student it stands on", "The payment is genuine and belongs to the student it stands on: it counts again."],
  REALLOCATE: ["Reallocate to its true owner", "The payment belongs to another student: it is moved to them through the payment swap, once a Bursar officer approves."],
  DUPLICATE: ["Confirm it a duplicate", "The record repeats another payment kept on record: it stays archived and is never counted; its posting is reversed."],
  NOT_RECEIVED: ["Confirm it was never received", "The money never reached the University's account: it stays archived and is never counted; its posting is reversed."],
};

export const ARCHIVE_OUTCOMES = Object.keys(OUTCOME_WORDS) as ArchiveOutcome[];

export const SOURCE_WORDS: Record<ArchiveSource, string> = {
  DESK: "Archived payments desk",
  DUPLICATE_WITHDRAWAL: "Old Fees History: recorded twice",
  NOT_RECEIVED_WITHDRAWAL: "Old Fees History: never received",
};

export const SIGNAL_WORDS: Record<string, string> = {
  SAME_GATEWAY_REFERENCE: "The same gateway reference",
  SAME_TRANSACTION_REFERENCE: "The same transaction reference",
  SAME_OLD_PORTAL_NUMBER: "The same old-portal payment number",
  SAME_STUDENT: "The same student",
  SAME_AMOUNT: "The same amount",
  SAME_PURPOSE: "The same purpose",
  SAME_SESSION: "The same session",
  SAME_DAY: "The same day",
  SAME_STUDENT_AMOUNT_PURPOSE_DAY: "Only the same student, amount, purpose and day",
};

export const EVENT_WORDS: Record<string, string> = {
  ARCHIVED: "Archived for review",
  INVESTIGATION_RECORDED: "Investigation recorded",
  EVIDENCE_ADDED: "Evidence file added",
  PROPOSED: "Settlement proposed",
  RESUBMITTED: "Changed and proposed again",
  RETURNED: "Returned for correction",
  REJECTED: "Proposal rejected",
  APPROVED: "Approved by the Bursar",
  RESTORED: "Restored: counts again",
  REALLOCATED: "Reallocated to its owner",
  DUPLICATE_CONFIRMED: "Duplicate confirmed",
  NOT_RECEIVED_CONFIRMED: "Confirmed never received",
  LEDGER_RECLASSIFIED: "Ledger reclassified",
  LEDGER_REVERSED: "Ledger posting reversed",
  FAILED: "Settlement failed; nothing changed",
  WITHDRAWN_AS_DOUBLE: "Withdrawn as recorded twice (Old Fees History)",
  WITHDRAWN_NOT_RECEIVED: "Withdrawn as never received (Old Fees History)",
};

export interface Reason { code: string; label: string; explanation: string; needs_related: boolean }
export interface EvidenceKind { code: string; label: string; strength: "STRONG" | "SUPPORTING" }
export interface Catalogue { reasons: Reason[]; evidenceKinds: EvidenceKind[]; sessions: string[]; channels: string[] }

export interface Figures {
  session: string | null;
  recordedCount: number; recordedAmount: number; archivedCount: number; archivedAmount: number; activeCount: number; activeAmount: number;
  total: number; totalAmount: number; open: number; openAmount: number; duplicates: number; duplicateAmount: number;
  wrongStudent: number; wrongStudentAmount: number; ownershipPending: number; ownershipPendingAmount: number;
  awaitingBursar: number; awaitingBursarAmount: number; reconciled: number; reconciledAmount: number;
  reallocated: number; reallocatedAmount: number; notReceived: number; notReceivedAmount: number; unresolved: number; unresolvedAmount: number;
}

export interface FoundPayment {
  id: string; reference: string; amount: number; session: string; purpose: string; category: string; channel?: string | null; receipt_no?: string | null;
  generated_at?: string | null; confirmed_at?: string | null; archived_at?: string | null; student_id: string; matric_no?: string | null;
  admission_no?: string | null; name: string; legacy_payref?: string | null; eligible: boolean; refusals: string[];
}

export interface FoundStudent { id: string; matric_no?: string | null; admission_no?: string | null; jamb_reg_no?: string | null; name: string; programme?: string | null;
  current_level?: number | null; status?: string | null; merged?: boolean }

export interface ArchiveRow {
  id: string; archive_ref: string; reference: string; amount: number; purpose: string; category: string; semester?: number | null; session: string;
  channel?: string | null; receipt_no?: string | null; payment_confirmed_at: string; legacy: boolean; source: ArchiveSource; reason_code: string; reason: string;
  state: ArchiveState; outcome?: ArchiveOutcome | null; related_reference?: string | null; archived_at: string; archived_by?: string | null; archived_office: string;
  proposed_at?: string | null; proposed_by?: string | null; decided_at?: string | null; decided_by?: string | null; settled_at?: string | null;
  student_id: string; number?: string | null; jamb_reg_no?: string | null; name: string; current_student_id: string; current_number?: string | null;
  owner_number?: string | null; legacy_payref?: string | null; proposed_by_me?: boolean;
}

export interface ArchiveList { rows: ArchiveRow[]; total: number; page: number; size: number; counts: { state: ArchiveState; n: number; amount: number }[] }

export interface EvidenceItem { kind: string; label: string; strength: "STRONG" | "SUPPORTING"; value: string; addedBy?: string | null; addedAt?: string | null }

export interface Account {
  session: string; stated: boolean; assessed: number; verifiedPaid: number; outstanding: number; archived: number; verifiedAll: number; archivedAll: number;
  clearsRegistration?: boolean | null;
}

export interface ArchiveStudent { id: string; matric_no?: string | null; admission_no?: string | null; jamb_reg_no?: string | null; name: string; programme?: string | null;
  department?: string | null; faculty?: string | null; current_level?: number | null; status?: string | null }

export interface ArchiveDetail {
  archive: ArchiveRow & {
    payment_id: string; related_payment_id?: string | null; signals?: { authoritative?: string[]; supporting?: string[] } | null; archive_note: string;
    held?: Record<string, unknown> | null; evidence: EvidenceItem[]; owner_student_id?: string | null; proposal_note?: string | null; proposed_office?: string | null;
    swap_id?: string | null; returned_at?: string | null; returned_note?: string | null; returned_by_name?: string | null; decision?: string | null;
    decided_office?: string | null; decision_note?: string | null; failure?: string | null; reason_explanation?: string | null;
    archived_by_name?: string | null; proposed_by_name?: string | null; decided_by_name?: string | null; archived_by_me?: boolean;
    archive_journal_no?: number | null; settle_journal_no?: number | null; payment_journal_no?: number | null; payment_reversal_no?: number | null;
  };
  payment: { id: string; reference: string; amount: number; purpose: string; session: string; channel?: string | null; receipt_no?: string | null; generated_at?: string | null;
    confirmed_at?: string | null; archived_at?: string | null; note?: string | null; student_id: string; semester?: number | null; paid_as?: string | null; batch_ref?: string | null };
  gateway: { kind: string; gateway?: string | null; ref?: string | null; outcome?: string | null; amount?: number | null; at?: string | null }[];
  legacyNumbers: { payref: string; amount?: number | null; recorded_at?: string | null }[];
  student?: ArchiveStudent | null; currentStudent?: ArchiveStudent | null; owner?: ArchiveStudent | null;
  account?: Account | null; ownerAccount?: Account | null;
  related?: { id: string; reference: string; amount: number; purpose: string; session: string; channel?: string | null; receipt_no?: string | null; confirmed_at?: string | null;
    archived_at?: string | null; number?: string | null; name?: string | null; student_id: string } | null;
  signalsNow?: { authoritative?: string[]; supporting?: string[] } | null;
  swap?: { id: string; swap_ref: string; status: string; from_number?: string | null; to_number?: string | null; executed_at?: string | null; failure?: string | null } | null;
  linked: { kind: string; ref: string; state?: string | null }[];
  events: { action: string; note?: string | null; at: string; actor_office?: string | null; actor?: string | null }[];
  files: { id: string; filename: string; content_type: string; size_bytes: number; added_at: string; added_by?: string | null }[];
  paymentHistory: { ref: string; kind: string; status: string; what?: string | null; at: string }[];
  result?: { state?: string; outcome?: string; failure?: string; swapRef?: string };
}

export interface Suspect {
  payment_id: string; reference: string; related_id: string; related_reference: string; student_id: string; session: string; amount: number; purpose: string;
  paid_on: string; basis: string; authoritative: boolean; matric_no?: string | null; admission_no?: string | null; name: string; related_number?: string | null;
}

export interface MyArchive {
  archive_ref: string; reference: string; amount: number; purpose: string; session: string; paid_at: string; state: ArchiveState; outcome?: ArchiveOutcome | null;
  archived_at: string; settled_at?: string | null; counts: boolean;
}

export interface ArchiveFilters {
  state: string; q: string; reason: string; session: string; semester: string; category: string; channel: string; source: string;
  from: string; to: string; paidFrom: string; paidTo: string; amount: string;
}

export const EMPTY_FILTERS: ArchiveFilters = { state: "", q: "", reason: "", session: "", semester: "", category: "", channel: "", source: "", from: "", to: "", paidFrom: "", paidTo: "", amount: "" };

export const CATEGORIES = ["School fees", "Acceptance fee", "Application fee", "Hostel", "Transcript", "Portal and ICT charge", "Identity card", "Transfer fee", "Other"];

/** the list's query string — only what is set */
export function archiveQuery(f: ArchiveFilters, extra: Record<string, string | number | boolean | undefined> = {}): string {
  const p = new URLSearchParams();
  (Object.keys(f) as (keyof ArchiveFilters)[]).forEach((k) => { const v = f[k].trim(); if (v) p.set(k, v); });
  Object.entries(extra).forEach(([k, v]) => { if (v !== undefined && v !== "" && v !== false) p.set(k, String(v)); });
  return p.toString();
}

/** the filters a page was asked for, each checked */
export function readArchiveFilters(p: Record<string, string | string[] | undefined>): ArchiveFilters {
  const one = (k: string) => (typeof p[k] === "string" ? (p[k] as string).trim() : "");
  const date = (k: string) => (/^\d{4}-\d{2}-\d{2}$/.test(one(k)) ? one(k) : "");
  const state = one("state").toUpperCase();
  const source = one("source").toUpperCase();
  const reason = one("reason").toUpperCase();
  return {
    state: state === "OPEN" || (ARCHIVE_STATES as string[]).includes(state) ? state : "",
    q: one("q").slice(0, 80),
    reason: /^[A-Z][A-Z_]{2,39}$/.test(reason) ? reason : "",
    session: /^\d{4}\/\d{4}$/.test(one("session")) ? one("session") : "",
    semester: /^[123]$/.test(one("semester")) ? one("semester") : "",
    category: CATEGORIES.includes(one("category")) ? one("category") : "",
    channel: one("channel").slice(0, 40),
    source: (Object.keys(SOURCE_WORDS) as string[]).includes(source) ? source : "",
    from: date("from"), to: date("to"), paidFrom: date("paidFrom"), paidTo: date("paidTo"),
    amount: /^\d{1,12}(\.\d{1,2})?$/.test(one("amount")) ? one("amount") : "",
  };
}

/** a refusal as the server words it ("PAR_EVIDENCE_STRONG: a payment is moved …"): its code and its words */
export function refusalParts(r: string): { code: string; words: string } {
  const i = r.indexOf(":");
  if (i < 0 || !/^[A-Z_]+$/.test(r.slice(0, i))) return { code: "", words: r.trim() };
  const words = r.slice(i + 1).trim();
  return { code: r.slice(0, i), words: words ? words.charAt(0).toUpperCase() + words.slice(1) : words };
}

/** what the evidence recorded so far allows the officer to propose (the server decides) */
export function proposalReadiness(outcome: ArchiveOutcome, evidence: EvidenceItem[], authoritative: string[], hasRelated: boolean): string | null {
  const strong = evidence.some((e) => e.strength === "STRONG");
  if (outcome === "RESTORE" && evidence.length === 0) return "Record the evidence that the payment is genuine and the student's first.";
  if (outcome === "REALLOCATE" && !strong) return "A payment is moved to another student only on strong evidence — never on a name alone.";
  if (outcome === "DUPLICATE" && !hasRelated) return "A duplicate repeats a payment kept on record; this archive names none.";
  if (outcome === "DUPLICATE" && authoritative.length === 0 && !strong)
    return "The same amount, student, day or purpose is no proof: an identifier the two share, or strong evidence, is.";
  if (outcome === "NOT_RECEIVED" && !strong) return "That the money never arrived is shown by strong evidence (a bank statement, the gateway's or the bank's reference).";
  return null;
}

/** a reason or note the server accepts: the length it asks */
export function longEnough(text: string, min: number): boolean {
  return text.trim().length >= min;
}

/** the report's columns — S/N is put first by the export itself */
export const ARCHIVE_HEAD = ["Archive ref", "Payment ref", "Old-portal number", "Student", "Matric no", "JAMB no", "Stands on now", "Purpose", "Session", "Semester",
  "Channel", "Amount (₦)", "Payment date", "Reason", "Source", "Status", "Verification", "Outcome", "Owner", "Repeats", "Archived by", "Archived on", "Decided by", "Settled on"];

/** an archived payment as a row of the report */
export function archiveLine(r: ArchiveRow, when: (iso: string | null | undefined) => string): (string | number)[] {
  const sem = (n?: number | null) => (n === 1 ? "First" : n === 2 ? "Second" : n === 3 ? "Third" : "");
  return [
    r.archive_ref, r.reference, r.legacy_payref ?? "", r.name, r.number ?? "", r.jamb_reg_no ?? "", r.current_number ?? "", r.purpose, r.session, sem(r.semester),
    r.channel ?? "", Number(r.amount), when(r.payment_confirmed_at), r.reason, SOURCE_WORDS[r.source] ?? r.source,
    STATE_WORDS[r.state]?.[1] ?? r.state, verificationWords(r.state)[1], r.outcome ? OUTCOME_WORDS[r.outcome]?.[0] ?? r.outcome : "", r.owner_number ?? "",
    r.related_reference ?? "", r.archived_by ?? "", when(r.archived_at), r.decided_by ?? "", when(r.settled_at),
  ];
}

/** the evidence file a browser may send: PDF, JPEG or PNG, up to 5 MB */
export function fileRefusal(file: { type: string; size: number }): string | null {
  if (!["application/pdf", "image/jpeg", "image/png"].includes(file.type)) return "Evidence is a PDF, JPEG or PNG file.";
  if (file.size <= 0) return "The file is empty.";
  if (file.size > 5 * 1024 * 1024) return "Evidence is up to 5 MB.";
  return null;
}

/** the notice a student reads on their fees page: what is under review, apart from the verified payments */
export function underReviewNote(rows: MyArchive[], naira: (n: number) => string): string | null {
  const open = rows.filter((r) => !r.counts && isOpen(r.state));
  if (!open.length) return null;
  const sum = open.reduce((s, r) => s + Number(r.amount), 0);
  return open.length === 1
    ? `${naira(sum)} payment is currently under verification and is not included in your verified payment balance.`
    : `${open.length} payments of ${naira(sum)} in all are currently under verification and are not included in your verified payment balance.`;
}
