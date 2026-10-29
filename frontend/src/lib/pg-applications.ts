/**
 * V694: the Postgraduate applications desk's words for when an application was made, where its document upload stands, and an
 * applicant who applied more than once. The API decides each (admissions.pg_document_state, admissions.pg_session_duplicates);
 * these only name them.
 */
import { docLabel } from "./pg-documents.ts";

export type DocumentsState = "COMPLETE" | "PENDING" | "NONE" | "FEE_UNPAID";
type Kind = "ok" | "bad" | "warn" | "info" | "grey";

/** the filters the desk offers, in its order, each with the count it reads from the API's counts */
export const DOCUMENT_FILTERS: { value: DocumentsState; label: string; count: string }[] = [
  { value: "COMPLETE", label: "Documents complete", count: "documents_complete" },
  { value: "PENDING", label: "Documents pending", count: "documents_pending" },
  { value: "NONE", label: "Paid, not uploaded", count: "documents_none" },
  { value: "FEE_UNPAID", label: "Fee unpaid", count: "documents_fee_unpaid" },
];

/** where an application's document upload stands, as a pill: complete, pending (with how many of how many), not uploaded (the
 *  fee paid), or the fee unpaid (the upload opens once it is confirmed) */
export function documentsPill(state: string | null | undefined, uploaded?: number | null, required?: number | null): { kind: Kind; label: string } {
  switch (state) {
    case "COMPLETE": return { kind: "ok", label: "Complete" };
    case "PENDING": return { kind: "warn", label: uploaded != null && required ? `Pending · ${uploaded} of ${required}` : "Pending" };
    case "NONE": return { kind: "bad", label: "Not uploaded" };
    case "FEE_UNPAID": return { kind: "grey", label: "Fee unpaid" };
    default: return { kind: "grey", label: "—" };
  }
}

/** the documents still to upload, by name ("NYSC,LGA_CERTIFICATE" → "NYSC certificate, LGA / indigene certificate") */
export function missingDocuments(missing: string | null | undefined): string {
  return (missing ?? "").split(",").map((k) => k.trim()).filter(Boolean).map(docLabel).join(", ");
}

/** the line for an applicant who applied more than once: how many times, and the other application numbers */
export function appliedTimes(times: number | string | null | undefined, others: string | null | undefined): string | null {
  const n = Number(times ?? 1);
  if (!(n > 1)) return null;
  return `Applied ${n} times${others ? ` · also ${others}` : ""}`;
}

/** the day an application was made, as the desk shows it ("22 Oct 2026"), and its time ("17:04"), in Lagos time */
export function appliedOn(v: string | null | undefined): { day: string; time: string } {
  if (!v) return { day: "—", time: "" };
  const d = new Date(v);
  if (Number.isNaN(d.getTime())) return { day: "—", time: "" };
  return {
    day: d.toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric", timeZone: "Africa/Lagos" }),
    time: d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" }),
  };
}

/** the desk's address for a session and its narrowing — the documents filter, those who applied more than once, the order */
export function desksHref(session: string, f: { documents?: string | null; duplicates?: boolean; sort?: string | null }): string {
  const q = new URLSearchParams({ session });
  if (f.documents) q.set("documents", f.documents);
  if (f.duplicates) q.set("duplicates", "1");
  if (f.sort === "applied") q.set("sort", "applied");
  return `/admissions/postgraduate?${q.toString()}`;
}
