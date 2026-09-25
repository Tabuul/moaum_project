/** Deferment (V259): the shapes the API returns and the words every screen uses for them. */
import { Pil } from "@/components/proto/ui";

export interface Deferment {
  id: string; reference: string; student_id: string; kind: "SEMESTER" | "SESSION"; session: string; semester: number | null;
  reason_code: string; reason: string; needs_document: boolean; needs_words: boolean; explanation: string | null; declared: boolean; state: string;
  extension_of: string | null; period_from: string | null; return_session: string | null; return_semester: number | null; return_on: string | null;
  submitted_at: string | null; dept_at: string | null; dept_note: string | null; fac_at: string | null; fac_note: string | null;
  decided_at: string | null; decision_note: string | null; correction_note: string | null; cancel_note: string | null;
  prior_status: string | null; activated_at: string | null; returned_at: string | null; return_note: string | null; created_at: string; updated_at: string;
  surname: string; other_names: string; number: string; level: number; student_status: string; entry_mode: string;
  programme_code: string; programme: string; dept_code: string; department: string; faculty_code: string; faculty: string; college_code: string | null;
  return_status: string | null; dept_officer: string | null; faculty_officer: string | null; decided_officer: string | null; returned_officer: string | null;
}
export interface DefermentDoc { id: string; kind: string; filename: string; content_type: string; size_bytes: number; uploaded_at: string; verified_at: string | null }
export interface DefermentEvent { action: string; from_state: string | null; to_state: string | null; actor_office: string | null; note: string | null; at: string; actor: string | null }
export interface DefermentFull extends Deferment {
  documents: DefermentDoc[]; history: DefermentEvent[];
  previous?: { reference: string; kind: string; session: string; semester: number | null; state: string; submitted_at: string | null; decided_at: string | null }[];
  registration?: { session: string; semester: number; status: string; submitted_at: string | null }[];
  fees?: { payable: number; paid: number; outstanding: number; status: string };
  standing?: { standing?: string; cgpa?: number | null };
  may?: Record<string, boolean>;
}
export interface Reason { code: string; label: string; needs_document: boolean; needs_words: boolean }
export interface MyDeferments {
  eligibility: { eligible: boolean; reason: string | null; used: number; allowed: number; live_reference: string | null };
  requests: Deferment[]; reasons: Reason[]; sessions: { name: string; semesters: number; state: string }[];
  current: { session?: string; semester?: number | null }; setting: { max_sessions: number; allow_extension: boolean };
}

export const STATE: Record<string, [string, "grey" | "info" | "warn" | "ok" | "bad"]> = {
  DRAFT: ["Draft", "grey"], SUBMITTED: ["Submitted", "info"], CORRECTION_REQUIRED: ["Correction required", "warn"],
  DEPT_RECOMMENDED: ["Department recommended", "info"], FAC_RECOMMENDED: ["Faculty recommended", "info"], APPROVED: ["Approved", "ok"],
  ACTIVE: ["Active", "ok"], COMPLETED: ["Completed", "ok"], REJECTED: ["Rejected", "bad"], CANCELLED: ["Cancelled", "grey"],
};
export const RETURN: Record<string, [string, "grey" | "info" | "warn" | "ok" | "bad"]> = {
  UPCOMING: ["Upcoming", "grey"], DUE: ["Due", "warn"], OVERDUE: ["Overdue", "bad"], RETURNED: ["Returned", "ok"],
};
export const DOC_KIND: Record<string, string> = { MEDICAL: "Medical documentation", FINANCIAL: "Financial evidence", OFFICIAL_LETTER: "Official letter", EMPLOYER_LETTER: "Employer letter", OTHER: "Other supporting evidence" };
export const ACTION_WORD: Record<string, string> = {
  CREATED: "Request opened", UPDATED: "Request changed", DOCUMENT: "Document uploaded", SUBMITTED: "Submitted", RECOMMEND: "Recommended by the department",
  FAC_RECOMMEND: "Recommended by the faculty", APPROVE: "Approved", REJECT: "Rejected", CORRECTION: "Returned for correction", CANCEL: "Cancelled",
  ACTIVATED: "Deferment came into force", RETURNED: "Return confirmed",
};
export const SEM = (n: number | null | undefined) => (n == null ? "" : n === 1 ? "First semester" : n === 2 ? "Second semester" : "Third semester");
export const periodOf = (d: { kind: string; session: string; semester: number | null }) => d.kind === "SESSION" ? `${d.session} session` : `${d.session} · ${SEM(d.semester)}`;
export const returnOf = (d: { return_session: string | null; return_semester: number | null }) => d.return_session ? `${d.return_session} · ${SEM(d.return_semester)}` : "—";
export const dayOf = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }) : "—");
export const whenAt = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");

export function StatePil({ state }: { state: string }) {
  const [w, k] = STATE[state] ?? [state, "grey"];
  return <Pil kind={k}>{w}</Pil>;
}
export function ReturnPil({ status }: { status: string | null }) {
  if (!status) return null;
  const [w, k] = RETURN[status] ?? [status, "grey"];
  return <Pil kind={k}>{w}</Pil>;
}

export function readBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result).split(",")[1] ?? "");
    reader.onerror = () => reject(new Error("read failed"));
    reader.readAsDataURL(file);
  });
}
