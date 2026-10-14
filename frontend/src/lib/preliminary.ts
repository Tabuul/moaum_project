/**
 * V446 — the Preliminary Science Programme as the screens read it: the public programme, the applicant's part of an application,
 * the desk's rows and the words for each state. The eligibility and the remediation are the backend's (admissions.prelim_evaluate);
 * these screens only show them.
 */
import type { Application } from "./applicant";
export { jcall as pcall, fileBase64, naira, when } from "./jupeb";

export interface PrelimTarget { group: string; name: string; programmeCode: string; registerName: string }
export interface PrelimDocumentKind { kind: string; label: string; hint: string | null; required: boolean; secondSittingOnly: boolean }
export interface PrelimRules {
  minCredits: number; maxSittings: number; minCoreCredits: number; coreSubjects: string[]; creditGrade: string;
  completionCredits: number; completionSubjects: string[]; awaitingAccepted: boolean; remediationTerms: string | null;
}
export interface PrelimPublic {
  route: string; name: string; programmeType: string | null; description: string; completionNote: string; procedure: string[]; officeNote: string | null;
  session: string; studyMode: string;
  window: { state: string; opensAt: string | null; closesAt: string | null; message: string | null };
  fee: { stated: boolean; applicationFee: number | null; session: string };
  rules: PrelimRules; targets: PrelimTarget[]; documents: PrelimDocumentKind[];
}
export interface PrelimCheck { key: string; label: string; required?: number; held?: number; ok: boolean; atMost?: boolean; subjects?: string[] }
export interface PrelimEligibility { status: string; totalCredits: number; coreCredits: number; sittings: number; creditedCore: string[]; checks: PrelimCheck[]; reasons: string[] }
export interface PrelimRemediation { status: string | null; subjects: string[]; creditsShort: number; note: string | null }
export interface PrelimOlevel { sitting: number; exam_body: string; exam_type: string | null; exam_number: string; exam_year: number; subject: string; grade: string }
export interface PrelimEvent { at: string; action: string; from_state: string | null; to_state: string | null; note: string | null; office: string | null }
export interface PrelimBlock {
  route: string; programme: string; state: string; editable: boolean; feeSettled: boolean; sex: string | null;
  targetProgramme: string | null; targetName: string | null; submittedAt: string | null; requestNote: string | null;
  eligibility: PrelimEligibility; remediation: PrelimRemediation; olevelVerification: string | null;
  fields: { field: string; required: boolean; label: string | null; value: string | null }[];
  olevel: PrelimOlevel[]; problems: { step: string; field: string; message: string }[]; events: PrelimEvent[]; programmeInfo: PrelimPublic;
}
export interface PrelimView extends Application { preliminary: PrelimBlock }

/** a row of the desk's list */
export interface PrelimRow {
  id: string; application_no: string; surname: string; other_names: string; sex: string | null; target_programme: string | null; target_name: string | null;
  dept_code: string | null; faculty_code: string | null; total_credits: number | null; core_credits: number | null; sittings: number | null;
  eligibility_status: string; remediation_status: string | null; remediation_subjects: string[]; olevel_verification: string; paid: boolean;
  fee_confirmed_at: string | null; state: string; published_at: string | null; submitted_at: string | null; session: string; created_at: string;
  state_of_origin: string | null; lga: string | null; email?: string; phone?: string;
}

export const ELIGIBILITY: Record<string, [string, "ok" | "warn" | "bad" | "info" | "grey"]> = {
  PENDING_REVIEW: ["Pending review", "grey"], ELIGIBLE: ["Eligible", "ok"], NOT_ELIGIBLE: ["Not eligible", "bad"], REMEDIATION_REQUIRED: ["Remediation required", "warn"],
  ELIGIBLE_WITH_REMEDIATION: ["Eligible, with remediation", "warn"], REQUIRES_VERIFICATION: ["Requires verification", "info"],
  RESULT_REQUIRED: ["Not eligible: result required", "bad"], INVALID_RESULT: ["Invalid result", "bad"],
};
export const REMEDIATION: Record<string, [string, "ok" | "warn" | "bad" | "info" | "grey"]> = {
  NOT_REQUIRED: ["Not required", "ok"], REQUIRED: ["Required", "warn"], IN_PROGRESS: ["In progress", "info"], COMPLETED: ["Completed", "ok"],
  NOT_COMPLETED: ["Not completed", "bad"], REQUIRES_REVIEW: ["Requires review", "info"],
};
export const STATE: Record<string, [string, "ok" | "warn" | "bad" | "info" | "grey"]> = {
  DRAFT: ["Not submitted", "grey"], SUBMITTED: ["Submitted", "info"], UNDER_REVIEW: ["Under review", "info"], CORRECTION_REQUIRED: ["Correction required", "warn"],
  RECOMMENDED: ["Recommended", "info"], APPROVED: ["Approved, not published", "info"], ADMITTED: ["Admitted", "ok"], NOT_ADMITTED: ["Not admitted", "bad"],
  REJECTED: ["Rejected", "bad"], WITHDRAWN: ["Withdrawn", "grey"],
};
export const VERIFICATION: Record<string, [string, "ok" | "warn" | "bad" | "info" | "grey"]> = {
  PENDING: ["Not yet verified", "grey"], VERIFIED: ["Verified", "ok"], INVALID: ["Invalid", "bad"],
};
export const ACTION: Record<string, string> = {
  REGISTERED: "Application started", SUBMITTED: "Submitted", CORRECTED: "Correction sent back", START: "Taken up for review",
  REQUEST_CORRECTION: "Returned for a correction", RESUME: "Taken back under review", RECOMMEND: "Recommended", APPROVE: "Approved",
  NOT_ADMIT: "Not admitted", REJECT: "Rejected", REOPEN: "Reopened", PUBLISHED: "Outcome published", WITHDRAWN: "Withdrawn",
  TARGET_SET: "Target programme chosen", TARGET_CHANGED: "Target programme changed", OLEVEL_VERIFIED: "O'Level verified", OLEVEL_INVALID: "O'Level found invalid",
  DOCUMENT_ACCEPTED: "Document accepted", DOCUMENT_REJECTED: "Document rejected",
  REMEDIATION_NOT_REQUIRED: "Remediation: not required", REMEDIATION_REQUIRED: "Remediation: required", REMEDIATION_IN_PROGRESS: "Remediation: in progress",
  REMEDIATION_COMPLETED: "Remediation: completed", REMEDIATION_NOT_COMPLETED: "Remediation: not completed", REMEDIATION_REQUIRES_REVIEW: "Remediation: under review",
};
export const labelOf = (m: Record<string, [string, string]>, k: string | null | undefined): [string, string] => (k && m[k]) || [k ? k.replace(/_/g, " ").toLowerCase() : "—", "grey"];

/** what the completion rule asks the candidate to make up, in words */
export function remediationWords(r: { subjects: string[]; creditsShort: number }): string {
  const parts = [...r.subjects];
  if (r.creditsShort > 0) parts.push(`${r.creditsShort} more O'Level credit pass${r.creditsShort === 1 ? "" : "es"}`);
  return parts.join(", ");
}

/** the target notice, said wherever a target programme is shown */
export const TARGET_NOTE = "Selection of a target programme under Preliminary Science does not constitute admission into the undergraduate programme. Subsequent admission remains subject to University requirements and applicable admission processes.";

export const BODIES: [string, string][] = [["WAEC", "WAEC"], ["NECO", "NECO"], ["NABTEB", "NABTEB"], ["OTHER", "Another examination body"]];
export const EXAM_TYPES: [string, string][] = [["SSCE", "School certificate (May/June)"], ["GCE", "GCE (Nov/Dec)"], ["OTHER", "Another"]];
export const GRADES = ["A1", "B2", "B3", "C4", "C5", "C6", "D7", "E8", "F9"];
export const SUBJECTS = ["English Language", "Mathematics", "Biology", "Chemistry", "Physics", "Agricultural Science", "Further Mathematics", "Economics", "Geography",
  "Technical Drawing", "Computer Studies", "Data Processing", "Government", "Literature in English", "Christian Religious Studies", "Islamic Religious Studies",
  "Civic Education", "Commerce", "Financial Accounting", "Health Education", "Physical Education", "Food and Nutrition", "Fine Art", "History", "French", "Tiv", "Hausa", "Yoruba", "Igbo"];

/** "Monday, 20 July 2026" */
export function longDay(iso: string | null | undefined): string {
  if (!iso) return "—";
  return new Date(iso).toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long", year: "numeric", timeZone: "Africa/Lagos" });
}
