/**
 * The document profiles (V320): what kind of document a print, a PDF or a workbook is, and what that
 * kind carries — the header on the first page and on the pages after it, the footer, the paper, the
 * margins, whether rows are numbered, which copy label and which watermark apply. A module says which
 * profile and gives its data; the profile decides the dress.
 */
export type DocumentProfileId =
  | "STANDARD_REPORT" | "BROADSHEET" | "RECEIPT" | "INVOICE" | "LETTER" | "FORM" | "RESULT"
  | "CERTIFICATE" | "TRANSCRIPT" | "STUDENT_PROFILE" | "ID_CARD" | "STATEMENT";

export interface DocumentProfile {
  id: DocumentProfileId;
  /** the default document title, in capitals as it prints; a document may give its own */
  title: string;
  orientation: "portrait" | "landscape";
  /** page margins in points (PDF) — the HTML print converts to millimetres */
  margin: { top: number; right: number; bottom: number; left: number };
  /** the first page's header: the full letterhead, a compact band, or none (a certificate dresses itself) */
  header: "full" | "compact" | "none";
  /** continuation pages carry the compact band, or nothing */
  continuation: "compact" | "none";
  footer: boolean;
  pageNumbers: boolean;
  /** a serial number column leads every table */
  serialColumn: boolean;
  /** the copy label printed under the title, or null */
  copy: string | null;
  /** a confidentiality label in the footer, or null */
  confidentiality: string | null;
}

const M = { top: 40, right: 44, bottom: 56, left: 44 };

export const DOCUMENT_PROFILES: Record<DocumentProfileId, DocumentProfile> = {
  STANDARD_REPORT: { id: "STANDARD_REPORT", title: "REPORT", orientation: "portrait", margin: M, header: "full", continuation: "compact", footer: true, pageNumbers: true, serialColumn: true, copy: null, confidentiality: "OFFICIAL USE ONLY" },
  BROADSHEET: { id: "BROADSHEET", title: "RESULT BROADSHEET", orientation: "landscape", margin: { top: 36, right: 36, bottom: 50, left: 36 }, header: "full", continuation: "compact", footer: true, pageNumbers: true, serialColumn: true, copy: null, confidentiality: "CONFIDENTIAL" },
  RECEIPT: { id: "RECEIPT", title: "OFFICIAL PAYMENT RECEIPT", orientation: "portrait", margin: M, header: "full", continuation: "compact", footer: true, pageNumbers: false, serialColumn: false, copy: null, confidentiality: null },
  INVOICE: { id: "INVOICE", title: "INVOICE", orientation: "portrait", margin: M, header: "full", continuation: "compact", footer: true, pageNumbers: true, serialColumn: true, copy: null, confidentiality: null },
  LETTER: { id: "LETTER", title: "", orientation: "portrait", margin: { top: 40, right: 56, bottom: 56, left: 56 }, header: "full", continuation: "compact", footer: true, pageNumbers: true, serialColumn: false, copy: null, confidentiality: null },
  FORM: { id: "FORM", title: "FORM", orientation: "portrait", margin: M, header: "full", continuation: "compact", footer: true, pageNumbers: true, serialColumn: false, copy: null, confidentiality: null },
  RESULT: { id: "RESULT", title: "STATEMENT OF RESULT", orientation: "portrait", margin: M, header: "full", continuation: "compact", footer: true, pageNumbers: true, serialColumn: true, copy: "STUDENT COPY", confidentiality: null },
  CERTIFICATE: { id: "CERTIFICATE", title: "CERTIFICATE", orientation: "portrait", margin: M, header: "none", continuation: "none", footer: false, pageNumbers: false, serialColumn: false, copy: null, confidentiality: null },
  TRANSCRIPT: { id: "TRANSCRIPT", title: "ACADEMIC TRANSCRIPT", orientation: "portrait", margin: M, header: "full", continuation: "compact", footer: true, pageNumbers: true, serialColumn: false, copy: null, confidentiality: "CONFIDENTIAL" },
  STUDENT_PROFILE: { id: "STUDENT_PROFILE", title: "STUDENT PROFILE", orientation: "portrait", margin: M, header: "full", continuation: "compact", footer: true, pageNumbers: true, serialColumn: true, copy: null, confidentiality: "OFFICIAL USE ONLY" },
  ID_CARD: { id: "ID_CARD", title: "IDENTITY CARD", orientation: "portrait", margin: M, header: "none", continuation: "none", footer: false, pageNumbers: false, serialColumn: false, copy: null, confidentiality: null },
  STATEMENT: { id: "STATEMENT", title: "STATEMENT", orientation: "portrait", margin: M, header: "full", continuation: "compact", footer: true, pageNumbers: true, serialColumn: true, copy: null, confidentiality: null },
};

export function profileOf(id: DocumentProfileId | string | null | undefined): DocumentProfile {
  return DOCUMENT_PROFILES[(id ?? "STANDARD_REPORT") as DocumentProfileId] ?? DOCUMENT_PROFILES.STANDARD_REPORT;
}

/** the title a document prints: its own, else the profile's; always in capitals */
export function documentTitle(profile: DocumentProfile, own?: string | null): string {
  return (own && own.trim() ? own.trim() : profile.title).toUpperCase();
}

/** "2025/2026 Academic Session — First Semester", from what the document knows */
export function periodSubtitle(session?: string | null, semester?: number | string | null): string | null {
  const sem = semester == null || semester === "" ? null : Number(semester);
  const semName = sem === 1 ? "First Semester" : sem === 2 ? "Second Semester" : sem === 3 ? "Third Semester" : null;
  if (!session && !semName) return null;
  return [session ? `${session} Academic Session` : null, semName].filter(Boolean).join(" — ");
}
