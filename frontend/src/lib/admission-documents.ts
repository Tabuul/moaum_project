/** The admission documents in one place (V282): the rows /api/v1/applicant/me/documents-centre and /api/v1/me/admission-documents
 *  serve — each read from the store that owns it, with its state — and the routes that open them from either door. */
import type { PilKind } from "@/lib/documents";
import { stepHref } from "@/lib/screening";

export type DocStatus = "PENDING" | "AVAILABLE" | "GENERATED" | "DOWNLOADED" | "PRINTED" | "REPLACED" | "REVOKED" | "NOT_ISSUED";
export interface AdmissionDocRow {
  key: string; group: "ADMISSION" | "ACCEPTANCE" | "SCREENING" | "FEES"; title: string; status: DocStatus; availableAfter: string | null;
  number: string | null; version: number | null; code: string | null; issuedOn: string | null;
  reference: string | null; receiptNo: string | null; amount: number | null; confirmedAt: string | null;
  /** letter · forms · receipt:<reference> · fees-receipt:<reference> · null when nothing opens yet */
  action: string | null;
}

export const DOC_WORD: Record<DocStatus, [string, PilKind]> = {
  PENDING: ["Not yet available", "grey"], AVAILABLE: ["Available", "info"], GENERATED: ["Generated", "ok"], DOWNLOADED: ["Downloaded", "ok"],
  PRINTED: ["Printed", "ok"], REPLACED: ["Replaced", "warn"], REVOKED: ["Revoked", "bad"], NOT_ISSUED: ["Not issued", "grey"],
};
export const GROUP_WORD: Record<AdmissionDocRow["group"], string> = { ADMISSION: "Admission", ACCEPTANCE: "Acceptance", SCREENING: "Screening", FEES: "School fees" };

/** where a row opens, from the applicant's dashboard or from the student's library: the same document, two doors */
export function docHref(row: AdmissionDocRow, side: "applicant" | "student"): string | null {
  const a = row.action;
  if (!a) return null;
  if (a === "letter") return side === "applicant" ? "/applicant/status/letter" : "/student/documents/admission/letter";
  if (a === "forms") return side === "applicant" ? "/applicant/clearance/print" : "/student/documents/admission/forms";
  if (a.startsWith("receipt:")) {
    const ref = encodeURIComponent(a.slice("receipt:".length));
    return side === "applicant" ? `/applicant/fee/receipt?reference=${ref}` : `/student/documents/admission/receipt?reference=${ref}`;
  }
  if (a.startsWith("fees-receipt:")) {
    const ref = encodeURIComponent(a.slice("fees-receipt:".length));
    const student = `/student/receipt/${ref}/pdf`;
    return side === "applicant" ? stepHref(student) : student;
  }
  return null;
}

/** the same document, asked for as a download or as a print (the opening is logged on its trail either way) */
export function withMode(href: string, mode: "download" | "print"): string {
  if (href.startsWith("/applicant/to-student")) return href;   // the handover carries the door; the fees receipt opens inline there
  return `${href}${href.includes("?") ? "&" : "?"}${mode === "download" ? "download=1" : "print=1"}`;
}
