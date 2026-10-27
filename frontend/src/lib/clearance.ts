/** Student clearance (V415): fresh and final clearance as workflows on the one clearance engine — the shapes the API
 *  answers with, the words each state reads as, and the colour of its pill. */

export type StageState = "WAITING" | "PENDING" | "UNDER_REVIEW" | "REQUIRES_ACTION" | "NOT_CLEARED" | "REJECTED" | "CLEARED" | "NOT_APPLICABLE";
export type Overall = "IN_PROGRESS" | "PARTIALLY_CLEARED" | "PENDING_ACTION" | "NOT_CLEARED" | "REJECTED" | "CLEARED" | "COMPLETED" | "CANCELLED";

export interface WorkflowStage {
  unit: string; label: string; office_code: string | null; ord: number; required: boolean; waits: boolean; condition: string;
  programmes: string[]; faculties: string[]; departments: string[]; levels: number[]; entry_modes: string[]; documents: string[];
  deadline_days: number | null; instructions: string | null; active: boolean;
}
export interface Workflow {
  code: string; label: string; purpose: string; prefix: string; per_session: boolean; active: boolean; complete_word: string;
  reminder_days: number; certificate: boolean; description: string | null; stages: WorkflowStage[];
}
export interface Workflows {
  workflows: Workflow[]; units: { code: string; label: string; office_code: string | null; ord: number }[]; myUnits: string[];
  canConfigure: boolean; canStart: boolean; canOverride: boolean; sessions: string[]; currentSession: string | null;
}
export interface DeskStage { unit: string; label: string; state: StageState; applies: boolean; required: boolean }
export interface DeskRow {
  process_id: string; reference: string; student_id: string; session: string; started_at: string; completed_at: string | null; start_basis: string;
  surname: string; other_names: string; matric_no: string | null; admission_no: string | null; jamb_reg_no: string | null; application_no: string | null;
  sex: string | null; entry_mode: string | null; level: number | null; programme_code: string | null; programme: string | null; dept_code: string | null;
  department: string | null; faculty_code: string | null; faculty: string | null; stages: DeskStage[]; overall: Overall;
  my_state: StageState | null; my_item: string | null; my_applies: boolean | null; my_opened: boolean | null; my_decided_at: string | null;
  /** V416: the documents uploaded for the stage that await review, by name */
  docs_pending?: string | null;
}
export interface Desk {
  workflow: Workflow; session: string; unit: string | null; status: string | null; tiles: Record<string, number>; processes: number; total: number;
  page: number; size: number; rows: DeskRow[]; myUnits: string[]; scope: { faculty: string; department: string };
  /** V416: how many students have a document awaiting review, and whether the list is only those */
  documents?: number; documentsOnly?: boolean;
}
export interface Stage {
  unit: string; label: string; office_code?: string | null; ord: number; required: boolean; waits: boolean; applies: boolean; opened: boolean;
  state: StageState; item: string | null; note: string | null; decided_at: string | null; overridden: boolean; documents: string[];
  instructions: string | null; deadline: string | null; officer: string | null;
}
export interface HistoryRow {
  unit: string; label: string; state: string; item: string | null; note: string | null; internal_note?: string | null; override: boolean;
  previous_state: string | null; office: string | null; decided_at: string; officer: string | null;
}
export interface ClearanceDocument {
  id: string; unit: string; unit_label: string; label: string; file_name: string; content_type: string; size_bytes: number; state: string;
  reason: string | null; uploaded_at: string; uploaded_office: string | null; reviewed_at: string | null; superseded: boolean; reviewer: string | null;
}
export interface ProcessHead {
  id: string; reference: string; workflow: string; workflow_label: string; session: string; started_at: string; start_basis: string; start_reason: string | null;
  completed_at: string | null; cancelled_at: string | null; cancel_reason: string | null; overall: Overall; complete_word: string; certificate: boolean;
  surname: string; other_names: string; matric_no: string | null; admission_no: string | null; jamb_reg_no: string | null; application_no: string | null;
  sex: string | null; entry_mode: string | null; level: number | null; student_status: string; programme: string | null; department: string | null;
  faculty: string | null; started_by_name: string | null; student_id: string;
}
export interface ProcessDetail {
  process: ProcessHead; stages: Stage[]; history: HistoryRow[]; documents: ClearanceDocument[]; evidence: Record<string, Record<string, unknown>>;
  myUnits: string[]; canOverride: boolean; canCancel: boolean;
  /** V665: on a final clearance, for the offices that read the Bursary's account */
  finalCheck?: FinalCheck;
}

/** V665: what the Bursar's confirmation of a final clearance rests on, read afresh by the server (clearance.final_check) */
export interface FinalCheck {
  process: string; reference: string; workflow: string; graduates: boolean; status: string; bursaryState: string | null;
  graduand: { session: string; award: string; minute: string; approvedAt: string | null } | null;
  assessed: number; paid: number; waived: number; outstanding: number; credit: number; periods: number; reviewPeriods: number; pendingPeriods: number;
  unsettled: { session: string; semester: number; level: number | null; assessed: number | null; paid: number; waived: number; outstanding: number | null; status: string }[];
  pendingWaivers: number;
  otherPayments: { reference: string; session: string; purpose: string; amount: number; kind: string; desk_status: string | null }[];
  othersPending: { unit: string; label: string; state: string }[];
  academic: { ok: boolean; completion: string | null; outstandingCourses: string | null; awaitingCourses: string | null };
  blockers: string[]; ready: boolean;
}

/** V665: whether the word about to be given is the Bursar's confirmation that graduates the student — the Bursary's own CLEARED (never
 *  an override) on a final clearance of an approved award not yet graduated; the screen then asks for the confirmation first */
export function graduatesOnClear(detail: Pick<ProcessDetail, "finalCheck">, unit: string, state: string, override: boolean): boolean {
  return !!detail.finalCheck?.graduates && unit === "BURSARY" && state === "CLEARED" && !override;
}
export interface OfficeFigures {
  unit: string; label: string; ord: number; applies: number; waiting: number; pending: number; under_review: number; requires_action: number;
  not_cleared: number; rejected: number; cleared: number; not_applicable: number; avg_days: number | null;
}
export interface Overview {
  workflow: Workflow; session: string; offices: OfficeFigures[]; overall: Record<string, number>;
  eligible: { not_started: number; started: number; ineligible: number; reasons: { reason: string; students: number }[] };
}
export interface MyProcess {
  id: string; reference: string; workflow: string; workflow_label: string; session: string; started_at: string; completed_at: string | null;
  cancelled_at: string | null; cancel_reason: string | null; overall: Overall; complete_word: string; certificate: boolean; verify_code: string | null;
  stages: Stage[]; history: HistoryRow[]; documents: ClearanceDocument[];
}
export interface AlumniDetails {
  email: string | null; phone: string | null; address: string | null; state_of_residence: string | null; country: string | null;
  employment_status: string | null; employer: string | null; occupation: string | null; linkedin: string | null; association_member: boolean;
  membership_no: string | null; confirmed_at: string | null; verified_at: string | null;
}
export interface MyClearance { processes: MyProcess[]; alumni: AlumniDetails | null; final?: MyFinal | null }

/** V668: what the student is told of their final clearance — the award approved and awaiting it, the offices still to clear, the
 *  Bursary's stage, and the school fees owed by session and semester (official amounts only) */
export interface MyFinal {
  awaiting: boolean; graduated: boolean; status: string; award: string | null; minute: string | null; awardSession: string | null; basis: string | null;
  process: string | null; reference: string | null; othersPending: { unit: string; label: string; state: string }[]; bursaryState: string | null;
  assessed: number; paid: number; waived: number; outstanding: number; beingAssessed: number; owing: { session: string; semester: number; outstanding: number }[];
  onlinePayment: boolean;
}

/** V668: a final clearance waiting only on the Bursary's confirmation, with the account read afresh */
export interface ReadyRow {
  process_id: string; reference: string; session: string; student_id: string; surname: string; other_names: string; matric_no: string | null;
  programme: string | null; department: string | null; faculty: string | null; award: string | null; minute: string | null; award_session: string | null;
  basis: string | null; bursary_state: string | null; assessed: number | string; paid: number | string; waived: number | string; outstanding: number | string;
  review_periods: number; pending_periods: number; owing: string | null; ready: boolean;
}
export interface ReadyQueue { rows: ReadyRow[]; total: number; ready: number; canConfirm: boolean }

/** V668: where the student's final clearance stands, in their words: the next step, and whether money stands in the way */
export function finalWords(f: MyFinal): { title: string; body: string; kind: "ok" | "bad" | "info" } {
  if (f.graduated) return { kind: "ok", title: "You have graduated", body: "Every office has cleared you and the Bursar confirmed your final clearance." };
  const owed = Number(f.outstanding) >= 1;
  const offices = f.othersPending.map((o) => o.label);
  const next = offices.length ? `Still to clear you: ${offices.join(", ")}. ` : "Every other office has cleared you. ";
  if (owed) {
    return { kind: "bad", title: "School fees stand between you and graduation",
      body: `${next}The Bursary clears you last, and its clearance graduates you; it cannot while school fees are owed for any session.` };
  }
  if (f.beingAssessed > 0) {
    return { kind: "info", title: "The Bursary is assessing a past semester",
      body: `${next}A semester of your record is being assessed; nothing is owed for it until the Bursar approves an amount.` };
  }
  return { kind: "info", title: "Your award is approved — final clearance under way",
    body: `${next}${offices.length ? "Then the Bursary" : "The Bursary"} clears you last; its clearance graduates you and your record reads GRADUATED.` };
}

/** a stage's word as a person reads it */
export const STATE_WORD: Record<string, string> = {
  WAITING: "Waiting", PENDING: "Pending", UNDER_REVIEW: "Under review", REQUIRES_ACTION: "Requires action", NOT_CLEARED: "Not cleared",
  REJECTED: "Rejected", CLEARED: "Cleared", NOT_APPLICABLE: "Not required", HELD: "Not cleared",
};
/** a process's overall word */
export const OVERALL_WORD: Record<string, string> = {
  IN_PROGRESS: "In progress", PARTIALLY_CLEARED: "Partly cleared", PENDING_ACTION: "Requires action", NOT_CLEARED: "Not cleared",
  REJECTED: "Rejected", CLEARED: "Cleared", COMPLETED: "Completed", CANCELLED: "Cancelled", NOT_STARTED: "Not started",
};
export type PilKind = "grey" | "info" | "ok" | "bad" | "warn";
/** the pill colour of a word: cleared green, held red, asked amber, waiting and not required grey */
export function stateKind(s: string | null | undefined): PilKind {
  switch (s) {
    case "CLEARED": case "COMPLETED": return "ok";
    case "NOT_CLEARED": case "REJECTED": return "bad";
    case "REQUIRES_ACTION": case "PENDING_ACTION": return "warn";
    case "PENDING": case "UNDER_REVIEW": case "IN_PROGRESS": case "PARTIALLY_CLEARED": return "info";
    default: return "grey";
  }
}
export const stateWord = (s: string | null | undefined) => (s ? STATE_WORD[s] ?? OVERALL_WORD[s] ?? s.replace(/_/g, " ").toLowerCase() : "—");
/** the one-character mark a compact table uses for a stage */
export function stateMark(s: string): string {
  switch (s) {
    case "CLEARED": return "✓";
    case "NOT_APPLICABLE": return "—";
    case "NOT_CLEARED": case "REJECTED": return "✗";
    case "REQUIRES_ACTION": return "!";
    case "WAITING": return "·";
    default: return "○";
  }
}
export const CONDITION_WORD: Record<string, string> = {
  ALWAYS: "Every student",
  HOSTEL_THIS_SESSION: "Only a student who applied for or was allocated a hostel in the session",
  HOSTEL_EVER_ALLOCATED: "Only a student who was ever allocated a hostel room",
};
export const EMPLOYMENT: [string, string][] = [
  ["EMPLOYED", "Employed"], ["SELF_EMPLOYED", "Self-employed"], ["SEEKING", "Seeking work"], ["FURTHER_STUDY", "Further study"],
  ["NATIONAL_SERVICE", "National service (NYSC)"], ["OTHER", "Other"],
];
/** the decisions an office gives on a stage, in the order the desk offers them */
export const DECISIONS: { state: string; label: string; needsReason: string | null }[] = [
  { state: "CLEARED", label: "Clear", needsReason: null },
  { state: "UNDER_REVIEW", label: "Under review", needsReason: null },
  { state: "REQUIRES_ACTION", label: "Requires action", needsReason: "What the student must do" },
  { state: "NOT_CLEARED", label: "Not cleared", needsReason: "What is outstanding" },
  { state: "REJECTED", label: "Reject", needsReason: "The reason" },
];

/** the public path the certificate's QR carries — the reference's own slashes kept as path segments (FCLR/2026/000012) */
export function clearanceVerifyPath(reference: string, code: string | null): string {
  return `/verify/clearance/${reference.split("/").map(encodeURIComponent).join("/")}${code ? `?c=${encodeURIComponent(code)}` : ""}`;
}

/** a student's number as the desk shows it: matric first, then admission, JAMB, application */
export function studentNumber(r: { matric_no?: string | null; admission_no?: string | null; jamb_reg_no?: string | null; application_no?: string | null }): string {
  return r.matric_no || r.admission_no || r.jamb_reg_no || r.application_no || "—";
}
