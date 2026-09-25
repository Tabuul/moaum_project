/** Digital academic documents (V262): the shapes the screens read, the words for each state, and the small helpers. */
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";

export type PilKind = "grey" | "info" | "ok" | "bad" | "warn";

export interface Course { code: string; title: string; units: number; grade: string | null; points: number | null; quality: number | null; type: string | null; outcome: string | null }
export interface SemesterBlock { semester: number; courses: Course[]; units: number | null; gpa: number | null; cgpa: number | null; tcr?: number | null; tce?: number | null; twgp?: number | null }
export interface SessionBlock { session: string; semesters: SemesterBlock[] }
export interface Statement {
  holder: string; matricNo: string; admissionNo?: string; programme: string; programmeCode?: string; department?: string; faculty?: string; award?: string;
  entryMode?: string; entrySession?: string; entryLevel?: number; level?: number; status?: string; postgraduate?: boolean; scope?: string; session?: string; semester?: number;
  sessions: SessionBlock[]; cgpa?: number; classOfDegree?: string; standing?: string; graduationSession?: string; graduationMinute?: string; graduationDate?: string;
  research?: { kind?: string; topic?: string; stage?: string; vivaGrade?: string; awardedAt?: string };
  gradingScale?: { grade: string; low: number; high: number; points: number }[]; classificationBands?: { class: string; low: number; high: number }[];
  kind: string; number: string; version: number; templateVersion?: number; issuedOn: string; issuingAuthority?: string;
}
export interface Template { id?: string; kind: string; version: number; title: string; subtitle: string | null; signatory_name: string; signatory_title: string; second_name: string | null; second_title: string | null; footer: string | null; remarks: string | null; active?: boolean; created_at?: string }
export interface DocumentRow {
  id: string; kind: string; kind_label: string; number: string | null; version: number; status: string; verification_code: string; issued_on: string; issued_at: string; issued_office: string; template_version: number | null;
  flagged_at: string | null; flag_reason: string | null; supersedes: string | null; request_id: string | null; request_ref: string | null; student_id: string | null; student_name: string | null; student_number: string | null;
  programme: string | null; department: string | null; faculty: string | null; holder: string | null; award: string | null; class_of_degree: string | null; graduation_session: string | null; downloads: number; verifications: number; revoked_on: string | null; revoked_reason: string | null;
}
export interface DocumentFull extends DocumentRow { statement: string; template: Template | null; events?: DocEvent[]; downloadsLog?: { kind: string; at: string; ip: string | null }[]; verificationsLog?: { status: string; at: string; ip: string | null }[]; tokens?: { id: string; for_kind: string; email: string | null; expires_at: string; uses: number; max_uses: number; revoked_at: string | null; created_at: string }[]; versions?: { id: string; number: string; version: number; verification_code: string; issued_on: string; status: string; note: string | null }[] }
export interface RequestRow {
  id: string; ref: string; kind: string; kind_label: string; stage: string; delivery: string; destination: string; destination_name: string | null; recipient_email: string | null; express: boolean; copies: number; session: string | null; semester: number | null;
  fee: number | null; reference: string | null; paid_at: string | null; requested_at: string; started_at: string | null; validated_at: string | null; produced_at: string | null; qc_at: string | null; released_at: string | null; delivered_at: string | null; completed_at: string | null; closed_at: string | null; closed_reason: string | null;
  sla_due_on: string | null; breaching: boolean; issued_id: string | null; document_number: string | null; document_version: number | null; document_status: string | null; verification_code: string | null;
  student_id: string; student_name: string; student_number: string; programme: string | null; programme_code: string | null; dept_code: string | null; department: string | null; faculty_code: string | null; faculty: string | null; level: number; student_status: string;
  payment_status: string; receipt_no: string | null; deliveries_open: number;
}
export interface DocEvent { action: string; from_state: string | null; to_state: string | null; note: string | null; at: string; actor_office?: string | null; actor?: string | null }
export interface Delivery { id: string; kind: string; state: string; recipient: string | null; email: string | null; address?: string | null; courier: string | null; tracking_no: string | null; dispatched_on: string | null; delivered_on: string | null; note: string | null; updated_at: string; token?: string | null; expires_at?: string | null; uses?: number; max_uses?: number }
export interface RequestFull extends RequestRow {
  recipient_department: string | null; recipient_name: string | null; recipient_address: string | null; recipient_reference: string | null; purpose: string | null; international: boolean; validation: string | null; qc_note: string | null;
  produced_by: string | null; released_by: string | null; qc_by: string | null; events: DocEvent[]; deliveries: Delivery[]; preview: string; document?: DocumentFull; versions: { id: string; number: string; version: number; verification_code: string; issued_on: string; status: string }[];
}
export interface Policy {
  kind: string; label: string; billable: boolean; fee: number | null; urgent_fee: number; physical_fee: number; international_fee: number; currency: string; self_service: boolean; sla_days: number; urgent_sla_days: number;
  includes: string; number_prefix: string; public_fields: string[]; graduates_only: boolean; active: boolean; fee_now?: number; physical_extra?: number;
}
export interface MyDocuments {
  documents: DocumentRow[]; requests: RequestRow[]; policies: Policy[]; sessions: string[];
  student: { name: string; number: string; status: string; level: number; entry_mode: string; programme: string | null; department: string | null; faculty: string | null; senate_state: string | null };
  counts: { certificates: number; transcripts: number; pending: number; downloads: number };
}
export interface Validation { ok: boolean; findings: { severity: string; message: string }[]; published: number; unpublished: number; postgraduate: boolean; checkedAt: string }
export interface Verify {
  status: string; kind?: string; kindLabel?: string; number?: string | null; version?: number; issuedOn?: string; issuingInstitution?: string; currentInstitutionName?: string; issuingAuthority?: string; verificationCode?: string; verifiedAt?: string;
  revokedOn?: string; revokedUnder?: string; replacedBy?: string; remedy?: string; holder?: string; programme?: string; award?: string; classOfDegree?: string; faculty?: string; department?: string; graduationSession?: string; graduationDate?: string; session?: string; level?: number;
}

export const KIND: Record<string, [string, PilKind]> = {
  DEGREE_CERTIFICATE: ["Degree certificate", "ok"], TRANSCRIPT: ["Full transcript", "info"], SESSIONAL_TRANSCRIPT: ["Sessional transcript", "info"], MINI_TRANSCRIPT: ["Mini-transcript", "grey"], ACADEMIC_STATEMENT: ["Academic statement", "grey"],
  STATEMENT_OF_RESULT: ["Statement of result", "grey"], MATRICULATION: ["Matriculation", "grey"],
};
export const STAGE: Record<string, [string, PilKind]> = {
  AWAITING_PAYMENT: ["Payment pending", "warn"], HELD_AT_CLEARANCE: ["Held at clearance", "bad"], READY: ["Paid — awaiting processing", "info"], PROCESSING: ["Under processing", "info"], GENERATED: ["Generated — quality check", "info"],
  CORRECTION: ["Correction in hand", "warn"], VERIFIED: ["Approved — awaiting release", "info"], RELEASED: ["Ready for delivery", "ok"], DELIVERED: ["Delivered", "ok"], COMPLETED: ["Completed", "ok"], REJECTED: ["Rejected", "bad"], CANCELLED: ["Cancelled", "grey"],
};
export const DOC_STATUS: Record<string, [string, PilKind]> = { ACTIVE: ["Valid", "ok"], REVOKED: ["Revoked", "bad"], REPLACED: ["Replaced", "warn"], VALID: ["Valid", "ok"], NOT_FOUND: ["Not found", "bad"], INVALID: ["Invalid", "bad"] };
export const PAYMENT: Record<string, [string, PilKind]> = { PAID: ["Paid", "ok"], PENDING: ["Pending", "warn"], UNPAID: ["Unpaid", "bad"], FREE: ["No fee", "grey"] };
export const DELIVERY_STATE: Record<string, [string, PilKind]> = {
  NOT_SENT: ["Not sent", "grey"], READY: ["Ready", "info"], SENT: ["Sent", "info"], DELIVERED: ["Delivered", "ok"], FAILED: ["Failed", "bad"], EXPIRED: ["Expired", "grey"], RESENT: ["Resent", "info"],
  PROCESSING: ["Processing", "info"], DISPATCHED: ["Dispatched", "info"], IN_TRANSIT: ["In transit", "info"], RETURNED: ["Returned", "bad"],
};
export const DESTINATIONS: [string, string][] = [["SELF", "Myself"], ["INSTITUTION", "An institution"], ["EMPLOYER", "An employer"], ["EMBASSY", "An embassy"], ["PROFESSIONAL_BODY", "A professional body"], ["OTHER", "Another authorised recipient"]];
export const EVENT_WORDS: Record<string, string> = {
  REQUESTED: "Request submitted", PAID: "Payment confirmed", VALIDATED: "Academic validation", GENERATED: "Document generated", QUALITY_CHECK: "Quality check", RELEASED: "Approved and released", DELIVERY: "Delivery", DELIVERED: "Delivered", COMPLETED: "Completed",
  CANCELLED: "Cancelled", ISSUED: "Document issued", REVOKED: "Revoked", REPLACED: "Replaced by a new version", FLAGGED: "Flagged for review", FLAG_CLEARED: "Review closed", LINK_MADE: "Secure link made",
};

export const dayOf = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");
export const longDay = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");
export const whenAt = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }) : "—");
export const naira = (n: number | string | null | undefined) => (n === null || n === undefined ? "—" : `₦${Number(n).toLocaleString("en-NG", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`);
export const verifyPathFor = (key: string) => `/verify/document/${encodeURIComponent(key)}`;
export const semesterName = (n: number | null | undefined) => (n === 1 ? "First semester" : n === 2 ? "Second semester" : n === 3 ? "Third semester" : n ? `Semester ${n}` : "");

export function parseStatement(s: string | null | undefined): Statement | null {
  if (!s) return null;
  try { return JSON.parse(s) as Statement; } catch { return null; }
}

/** one call to the document doors from the browser: the problem returned, never thrown */
export async function callDocs<T>(method: "GET" | "POST" | "PUT", path: string, body: unknown, reason: string): Promise<{ ok: true; data: T } | { ok: false; problem: Problem }> {
  const r = await fetch(`/api/bff/api/v1${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: body === undefined ? undefined : JSON.stringify(body) });
  const j = await r.json().catch(() => null);
  if (!r.ok) return { ok: false, problem: (j as Problem) ?? { status: r.status, title: r.statusText } };
  return { ok: true, data: j as T };
}
