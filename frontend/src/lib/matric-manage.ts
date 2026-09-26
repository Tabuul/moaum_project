/** Matriculation Management (V267): the shapes the management endpoints answer with, and the words for them. */

export type BatchState = "DRAFT" | "GENERATED" | "READY_FOR_ISSUANCE" | "ISSUED" | "CANCELLED";
export type RowState = "PROPOSED" | "ISSUED" | "DROPPED";

export interface Candidate {
  student_id: string; admission_no: string | null; surname: string; other_names: string; programme_code: string; programme: string; dept_code: string | null; department: string | null;
  faculty_code: string; faculty: string; entry_session: string | null; status: string; matric_no: string | null; matriculated_at: string | null;
  registered: boolean; paid: boolean; query_reason: string | null; config_problem: string | null; eligible: boolean; reason: string | null;
  batch_id: string | null; batch_ref: string | null; batch_state: BatchState | null; row_id: string | null; proposed_no: string | null; row_state: RowState | null; problems: string[] | null; edited: boolean | null;
  series_code: string | null; sequence: number | null;
}
export interface Batch {
  id: string; ref: string; session: string; faculty_code: string; faculty: string; state: BatchState; prepared_at: string; generated_at: string | null; reviewed_at: string | null; issued_at: string | null; cancelled_at: string | null;
  cancel_reason: string | null; note: string | null; students: number; valid: number; conflicts: number; issued: number; dropped?: number; edited?: number;
  prepared_officer: string | null; reviewed_officer: string | null; issued_officer: string | null; prepared_by: string | null; reviewed_by: string | null; issued_by: string | null;
}
export interface BatchRow {
  id: string; student_id: string; admission_no: string | null; surname: string; other_names: string; entry_session: string | null; status: string; matric_no: string | null;
  programme_code: string | null; programme: string | null; dept_code: string | null; department: string | null; series_code: string | null; sequence: number | null;
  proposed_no: string | null; generated_no: string | null; edited: boolean; previous_no: string | null; edit_reason: string | null; edited_at: string | null; edited_officer: string | null;
  problems: string[]; state: RowState; drop_reason: string | null; issued_no: string | null; issued_at: string | null;
}
export interface BatchEdit { id: string; row_id: string; student_id: string; surname: string; other_names: string; previous_no: string | null; new_no: string; reason: string; officer: string | null; office: string | null; edited_at: string }
export interface BatchDetail { batch: Batch; rows: BatchRow[]; edits: BatchEdit[]; result?: { issued: number; username_updates: number; run_ref: string }; verification?: Verification }
export interface Verification { checked: number; with_number: number; status_active: number; history_rows: number; username_rows: number; unique_numbers: number; failed: number }
export interface Kpis { eligible: number; prepared: number; unprepared: number; pending: number; already: number; conflicts: number; issued: number }
export interface ProgrammeGroup { code: string; name: string; dept_code: string | null; department: string | null; students: number; eligible: number; prepared: number; matriculated: number }
export interface FacultyView { code: string; name: string; listState: string; kpis: Kpis; programmes: ProgrammeGroup[]; students: Candidate[]; batch: BatchDetail | null }
export interface ManagePage {
  session: string; canViewAll: boolean; boundFaculty: string | null; separateDuties: boolean;
  faculties: { code: string; name: string; matric_code: string | null; matric_series: string | null }[];
  batches: (Batch & { faculty: string })[];
  faculty?: FacultyView;
}
export interface OverviewRow {
  faculty_code: string; faculty: string; eligible: number; pending: number; already: number; prepared: number; valid: number; conflicts: number; issued: number;
  batch_id: string | null; batch_ref: string | null; batch_state: BatchState | null; list_state: string;
}
export interface Overview { session: string; faculties: OverviewRow[]; totals: { faculties: number; eligible: number; pending: number; already: number; prepared: number; valid: number; conflicts: number; issued: number; ready: number; in_review: number; programmes: number } }
export interface IssuedRow {
  matric_no: string; issued_at: string; series_code: string; sequence: number; reason: string | null; student_id: string; admission_no: string | null; surname: string; other_names: string; status: string; entry_session: string | null;
  programme_code: string | null; programme: string | null; department: string | null; faculty_code: string | null; faculty: string | null; run_ref: string | null; batch_ref: string | null; previous_username: string | null; issued_officer: string | null;
}
export interface PendingRow { student_id: string; admission_no: string | null; surname: string; other_names: string; programme_code: string; programme: string; department: string | null; faculty_code: string; faculty: string; reason: string; registered: boolean; paid: boolean; query_reason: string | null }
export interface StudentMatricRecord {
  id: string; admission_no: string | null; matric_no: string | null; matriculated_at: string | null; status: string; surname: string; other_names: string; entry_session: string | null; programme: string | null; faculty: string | null; department: string | null;
  run_ref: string | null; batch_ref: string | null; username: string | null; matriculation_status: "PRE_MATRICULATION" | "MATRICULATED";
  usernameHistory: { previous_username: string | null; new_username: string; reason: string; changed_at: string; office: string | null; batch_ref: string | null; officer: string | null }[];
  history: { matric_no: string; series_code: string; sequence: number; issued_at: string; reason: string | null; actor_office: string | null }[];
  proposals: { proposed_no: string | null; state: RowState; problems: string[]; edited: boolean; batch_ref: string; batch_state: BatchState }[];
}

export const BATCH_WORD: Record<BatchState, [string, "grey" | "info" | "ok" | "bad" | "warn"]> = {
  DRAFT: ["DRAFT", "grey"], GENERATED: ["GENERATED — UNDER REVIEW", "info"], READY_FOR_ISSUANCE: ["READY FOR ISSUANCE", "warn"], ISSUED: ["ISSUED", "ok"], CANCELLED: ["CANCELLED", "bad"],
};
export const PREPARERS = ["academic", "registrar", "dregistrar", "facultyofficer"];
export const ISSUERS = ["academic", "registrar", "dregistrar"];
export const whenAt = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
export const dayOf = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "2-digit", month: "2-digit", year: "numeric" }) : "—");
export const yy = (session: string | null | undefined) => (session ? session.slice(2, 4) : "—");
/** the student's standing on the exercise, in one word */
export function standing(c: Candidate): { word: string; kind: "grey" | "info" | "ok" | "bad" | "warn" } {
  if (c.matric_no) return { word: "MATRICULATED", kind: "ok" };
  if (c.row_id) return (c.problems ?? []).length ? { word: "CONFLICT", kind: "bad" } : c.batch_state === "READY_FOR_ISSUANCE" ? { word: "READY", kind: "warn" } : { word: "PREPARED", kind: "info" };
  return c.eligible ? { word: "ELIGIBLE", kind: "grey" } : { word: "PENDING", kind: "bad" };
}
