/** The JUPEB programme (V339) on the portal: the candidate's record as the API returns it, the words for its states, and the
 *  one fetch every JUPEB screen goes through. Nothing here decides anything — the server computes the fees, the eligibility,
 *  the activation and what may be done; the pages only show it and ask. */
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { csvRows, xlsxRows } from "@/lib/xlsx";

export interface Subject { id: string; code: string; title: string }
export interface Combination {
  id: string; code: string; name: string; area: string | null; description: string | null; eligibility_notes: string | null; active: boolean;
  subject1_code: string; subject1: string; subject2_code: string; subject2: string; subject3_code: string; subject3: string;
  leads_to: string[]; applications: number;
}
export interface Olevel { sitting: number; exam_type: string; exam_number: string | null; exam_year: number | null; subject: string; grade: string }
export interface Doc {
  kind: string; label: string; required: boolean; image: boolean; id: string | null; filename: string | null; content_type: string | null; size_bytes: number | null;
  status: string | null; review_note: string | null; reviewed_at: string | null; uploaded_at: string | null;
}
export interface Fees {
  category: string; indigene: boolean; total: number | null; first_percent: number; first_amount: number | null; second_amount: number | null; allow_full: boolean;
  first_paid: boolean; second_paid: boolean; full_paid: boolean; paid: number; outstanding: number; status: string; frozen: boolean;
}
export interface FeeRef { kind: string; reference: string; amount: number; semester: number | null; expires_at: string; confirmed_at: string | null; channel: string | null; created_at: string }
export interface Registered { code: string; title: string; registered_at: string; grade?: string | null; points?: number | null }
export interface JEvent { kind: string; note: string | null; at: string; actor_office?: string | null; actor_name?: string | null }
export interface Candidate {
  id: string; session: string; application_no: string; surname: string; first_name: string; middle_name: string | null; sex: string | null; date_of_birth: string | null;
  nin: string | null; email: string; phone: string | null; nationality: string | null; state_of_origin: string | null; lga: string | null; contact_address: string | null;
  permanent_address: string | null; home_town: string | null; guardian_name: string | null; guardian_phone: string | null; guardian_address: string | null;
  next_of_kin_name: string | null; next_of_kin_phone: string | null; next_of_kin_relationship: string | null;
  /** V341: SCIENCE or ARTS, chosen on the application */
  stream: string | null;
  programme_code: string | null; programme_name: string | null; department_name: string | null; faculty_code: string | null; faculty_name: string | null;
  combination_id: string | null; combination_code: string | null; combination_name: string | null; combination_area: string | null;
  state: string; fee_confirmed_at: string | null; submitted_at: string | null; return_note: string | null; returned_at: string | null;
  eligibility_note: string | null; eligibility_decided_at: string | null; admission_ref: string | null; admission_note: string | null; admission_decided_at: string | null;
  activated_at: string | null; class_id: string | null; class_name: string | null; subjects_registered_at: string | null; exam_no: string | null; exam_no_assigned_at: string | null;
  screening_state: string | null; screening_venue: string | null; screening_at: string | null; screening_reason: string | null; screening_decided_at: string | null;
  created_at: string; updated_at: string; editable: boolean; application_fee: number;
  subjects: Subject[]; olevel: Olevel[]; olevelCheck: { credits: number; english: boolean; mathematics: boolean; sittings: number; ok: boolean; reasons: string[] };
  documents: Doc[]; missing: string[]; fees: Fees; feeRule: { application_fee: number; first_percent: number; allow_full: boolean; activation: string; indigene_state: string };
  references: FeeRef[]; screeningSetting: { screening_required: boolean; screening_venue: string | null; screening_starts_on: string | null; screening_ends_on: string | null; screening_instructions: string | null };
  resultsPublished: boolean; registered: Registered[]; events: JEvent[];
  examNoHistory?: { old_no: string | null; new_no: string; reason: string | null; source: string; batch_ref: string | null; changed_office: string | null; changed_at: string; changed_by_name: string | null }[];
  resultChanges?: { code: string; old_grade: string | null; new_grade: string; reason: string; batch_ref: string | null; changed_at: string }[];
  decidedBy?: { eligibility: string | null; admission: string | null; returned: string | null; screening: string | null };
  combinations?: Combination[];
}

export const STATE_LABEL: Record<string, string> = {
  DRAFT: "Draft — not yet submitted", SUBMITTED: "Submitted — with the JUPEB Office", RETURNED: "Returned to you for correction",
  ELIGIBLE: "Found eligible — awaiting the admission decision", INELIGIBLE: "Not eligible", ADMITTED: "Admitted", NOT_ADMITTED: "Not admitted",
  PENDING: "Admission decision pending", STUDENT: "JUPEB student — active", COMPLETED: "Results published", WITHDRAWN: "Withdrawn",
};
export const STATE_SHORT: Record<string, string> = {
  DRAFT: "Draft", SUBMITTED: "Submitted", RETURNED: "Returned", ELIGIBLE: "Eligible", INELIGIBLE: "Not eligible", ADMITTED: "Admitted",
  NOT_ADMITTED: "Not admitted", PENDING: "Pending", STUDENT: "Student", COMPLETED: "Completed", WITHDRAWN: "Withdrawn",
};
export function stateKind(s: string | null | undefined): "grey" | "info" | "ok" | "bad" | "warn" {
  switch (s) {
    case "ADMITTED": case "STUDENT": case "COMPLETED": case "ELIGIBLE": case "VERIFIED": case "CLEARED": case "PAID": return "ok";
    case "INELIGIBLE": case "NOT_ADMITTED": case "REJECTED": case "NOT_CLEARED": case "WITHDRAWN": return "bad";
    case "RETURNED": case "PENDING": case "REPLACEMENT_REQUIRED": case "CORRECTION_REQUIRED": case "PARTIALLY_PAID": return "warn";
    case "SUBMITTED": case "UNDER_REVIEW": case "SCHEDULED": case "IN_PROGRESS": case "UPLOADED": return "info";
    default: return "grey";
  }
}
export const DOC_STATUS: Record<string, string> = {
  UPLOADED: "Uploaded", UNDER_REVIEW: "Under review", VERIFIED: "Verified", REJECTED: "Rejected", REPLACEMENT_REQUIRED: "Replacement required",
};
export const SCREENING_LABEL: Record<string, string> = {
  PENDING: "Awaiting screening", SCHEDULED: "Scheduled", IN_PROGRESS: "In progress", CLEARED: "Cleared", NOT_CLEARED: "Not cleared", CORRECTION_REQUIRED: "Correction required",
};
export const FEE_KIND: Record<string, string> = {
  APPLICATION: "Application fee", SCHOOL_FIRST: "School fees — first semester", SCHOOL_SECOND: "School fees — second semester", SCHOOL_FULL: "School fees — full payment",
};
export const EVENT_LABEL: Record<string, string> = {
  CREATED: "Application started", APPLICATION_FEE_CONFIRMED: "Application fee confirmed", SUBMITTED: "Submitted", RETURNED: "Returned for correction",
  ELIGIBLE: "Found eligible", INELIGIBLE: "Found not eligible", ADMITTED: "Admitted", NOT_ADMITTED: "Not admitted", PENDING: "Admission pending",
  SCHOOL_FEE_CONFIRMED: "School fee confirmed", STUDENT: "Activated as a JUPEB student", SUBJECTS_REGISTERED: "Subjects registered",
  EXAM_NO_ASSIGNED: "Examination number assigned", COMPLETED: "Results published", RESULT_CORRECTED: "Result corrected", CLASS: "Class",
  DOCUMENT_VERIFIED: "Document verified", DOCUMENT_REJECTED: "Document rejected", DOCUMENT_REPLACEMENT_REQUIRED: "Document to be replaced",
  DOCUMENT_UNDER_REVIEW: "Document under review", DOCUMENT_REPLACED: "Document replaced",
  SCREENING_PENDING: "Screening opened", SCREENING_SCHEDULED: "Screening scheduled", SCREENING_IN_PROGRESS: "Screening in progress", SCREENING_CLEARED: "Cleared at screening",
  SCREENING_NOT_CLEARED: "Not cleared at screening", SCREENING_CORRECTION_REQUIRED: "Correction required at screening",
};
export const OLEVEL_GRADES = ["A1", "B2", "B3", "C4", "C5", "C6", "D7", "E8", "F9", "AR"];
export const OLEVEL_EXAMS = ["WAEC", "NECO", "NABTEB", "GCE", "OTHER"];
export const OLEVEL_SUBJECTS = [
  "English Language", "Mathematics", "Physics", "Chemistry", "Biology", "Agricultural Science", "Further Mathematics", "Geography", "Economics", "Government",
  "Literature in English", "Christian Religious Studies", "Islamic Religious Studies", "History", "Civic Education", "Commerce", "Financial Accounting",
  "Technical Drawing", "Computer Studies", "Data Processing", "Food and Nutrition", "Home Management", "Visual Art", "Music", "French", "Hausa", "Igbo",
  "Yoruba", "Tiv", "Marketing", "Insurance", "Office Practice", "Book Keeping", "Animal Husbandry", "Fisheries", "Physical Education", "Health Education",
];

/** V341: the programme a JUPEB candidate is in — Science or Arts; the school fee's OTHER category is the Arts fee */
export const streamLabel = (s: string | null | undefined) => (s === "SCIENCE" ? "Science" : s === "ARTS" ? "Arts" : "—");
export const feeCategoryLabel = (c: string | null | undefined) => (c === "SCIENCE" ? "Science" : c === "OTHER" ? "Arts" : "—");

export const naira = (n: number | string | null | undefined) => (n == null || n === "" ? "—" : "₦" + Number(n).toLocaleString("en-NG", { minimumFractionDigits: 0, maximumFractionDigits: 2 }));
export const day = (v: string | null | undefined) => {
  if (!v) return "—";
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? "—" : d.toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric", timeZone: "Africa/Lagos" });
};
export const when = (v: string | null | undefined) => {
  if (!v) return "—";
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? "—" : d.toLocaleString("en-GB", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" });
};
export const fullName = (c: { surname: string; first_name: string; middle_name: string | null }) => `${c.surname}, ${c.first_name}${c.middle_name ? " " + c.middle_name : ""}`;

export type Result<T> = { ok: true; data: T } | { ok: false; problem: Problem };

/** one call to the API through the BFF: the JSON back, or the problem the server stated */
export async function jcall<T>(path: string, method = "GET", body?: unknown, reason?: string): Promise<Result<T>> {
  const headers: Record<string, string> = { Accept: "application/json" };
  if (body !== undefined) headers["Content-Type"] = "application/json";
  if (reason) headers["X-Reason"] = reasonHeader(reason);
  let r: Response;
  try {
    r = await fetch(`/api/bff${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body), cache: "no-store" });
  } catch {
    return { ok: false, problem: { status: 503, title: "The portal could not be reached; check your connection and try again." } };
  }
  const j = await r.json().catch(() => null);
  if (!r.ok) return { ok: false, problem: j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText || "The request failed" } };
  return { ok: true, data: j as T };
}

/** a file as base64, for the document uploads */
export function fileBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const fr = new FileReader();
    fr.onload = () => resolve(String(fr.result).replace(/^data:[^,]*,/, ""));
    fr.onerror = () => reject(fr.error);
    fr.readAsDataURL(file);
  });
}

/** the rows of an uploaded .xlsx or .csv, each keyed by the field its heading names (by ALIASES), with its row number in the file */
export async function readSheet(file: File, aliases: Record<string, string>): Promise<Record<string, string | number>[]> {
  const grid = /\.csv$/i.test(file.name) ? csvRows(await file.text()) : await xlsxRows(await file.arrayBuffer());
  const norm = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
  const headAt = grid.findIndex((r) => r.filter((c) => aliases[norm(String(c ?? ""))]).length >= 2);
  if (headAt < 0) return [];
  const keys = grid[headAt].map((h) => aliases[norm(String(h ?? ""))] ?? null);
  const out: Record<string, string | number>[] = [];
  for (let i = headAt + 1; i < grid.length; i++) {
    const r = grid[i];
    if (!r || r.every((c) => String(c ?? "").trim() === "")) continue;
    const o: Record<string, string | number> = { row: i + 1 };
    keys.forEach((k, j) => { if (k) o[k] = String(r[j] ?? "").trim(); });
    out.push(o);
  }
  return out;
}
