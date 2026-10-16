/**
 * How course registration is approved (V491): HOD_APPROVAL_REQUIRED or AUTO_APPROVAL by session and semester, with whether a
 * student may reset the registration and whether the examination card follows approval; the figures the Academic Office and the
 * Directorate of ICT read; and the words the student's screens use. The server decides all of it — this only says it.
 */

export type ApprovalMode = "HOD_APPROVAL_REQUIRED" | "AUTO_APPROVAL";

export interface ApprovalRule {
  mode: ApprovalMode;
  allow_student_reset: boolean;
  card_on_approval: boolean;
}

export interface ResetState {
  allowed: boolean;
  why: string | null;
  history: { reset_at: string; previous_status: string; course_count: number; units: number; source: string }[];
}

export interface RuleRow {
  id: string; session: string | null; semester: number | null; mode: ApprovalMode; allow_student_reset: boolean; card_on_approval: boolean;
  reason: string; set_at: string; set_by: string | null; set_office: string | null;
}
export interface Rules { rules: RuleRow[]; sessions: string[]; current: string | null }

export interface Overview {
  registered: number; approved: number; auto_approved: number; hod_approved: number; pending: number; review: number; reset: number;
  reregistered: number; draft: number; cards_issued: number; session: string; semester: number | null;
  rule: ApprovalRule & { session: string | null; semester: number | null; reason: string | null; set_at: string | null; set_by: string | null; applies_as: string };
}

export interface OverviewRow {
  registration_id: string; student_id: string; full_name: string; matric_no: string | null; programme: string | null; dept_code: string | null;
  faculty_code: string | null; level: number | null; session: string; semester: number; status: string; approval_mode: string | null;
  submitted_at: string | null; approved_at: string | null; review_reason: string | null; resets: number; last_reset_at: string | null;
  reregistered: boolean; card_times: number | null; courses: number;
  /** V503: the load that binds the student (the curriculum's minimum, the level's maximum, a SIWES or CCE load) and the units carried */
  curriculum?: string | null; load_basis?: string | null; min_units?: number | null; max_units?: number | null; units?: number | null;
}

/** where a student's minimum comes from, in the words of the lists */
export function loadWord(r: Pick<OverviewRow, "curriculum" | "load_basis">): string {
  if (r.load_basis === "SIWES") return "SIWES";
  if (r.load_basis === "CCE") return "CCE load";
  if (r.load_basis === "CURRICULUM" && r.curriculum) return r.curriculum;
  return "Level";
}

export const MODE_WORD: Record<ApprovalMode, string> = {
  AUTO_APPROVAL: "Automatic approval",
  HOD_APPROVAL_REQUIRED: "HOD approval required",
};

/** the figures, in the order the screen shows them, each the list it opens */
export const FIGURES: { key: keyof Overview; kind: string; label: string }[] = [
  { key: "registered", kind: "ALL", label: "Total registered" },
  { key: "auto_approved", kind: "AUTO_APPROVED", label: "Auto-approved" },
  { key: "hod_approved", kind: "HOD_APPROVED", label: "Approved by a Head" },
  { key: "pending", kind: "PENDING", label: "Pending" },
  { key: "review", kind: "REVIEW", label: "Requires review" },
  { key: "reset", kind: "RESET", label: "Reset" },
  { key: "reregistered", kind: "REREGISTERED", label: "Re-registered" },
  { key: "cards_issued", kind: "CARDS_ISSUED", label: "Exam cards printed or downloaded" },
];

/** V505: the list a figure opens that carries no count in the overview (read after the page) */
export const LIST_LABELS: Record<string, string> = { BELOW_MINIMUM: "Below the minimum" };

export const isApproved = (status: string | null | undefined) => status === "APPROVED" || status === "LOCKED";

/** the registration's state as the student reads it: never "with your Head of Department" while approval is automatic */
export function statusLine(status: string | null | undefined, mode: ApprovalMode | null | undefined, reviewReason: string | null | undefined): string {
  if (!status) return "Not registered";
  if (isApproved(status)) return "Approved";
  if (status === "SUBMITTED") {
    if (mode === "AUTO_APPROVAL") return reviewReason ? "Requires review" : "Submitted";
    return "Submitted, with your Head of Department";
  }
  if (status === "RETURNED") return "Returned to you";
  return "Draft";
}

/** a reason the server gave, without its code: "REG_FEES_NOT_STATED: the school fees … " → "The school fees …" */
export function reasonWords(reason: string | null | undefined): string {
  if (!reason) return "";
  const t = reason.replace(/^[A-Z][A-Z_]+:\s*/, "").trim();
  return t ? t.charAt(0).toUpperCase() + t.slice(1) : "";
}

/** the semester in words */
export const semesterWord = (n: number | null | undefined) => (n === 1 ? "First semester" : n === 2 ? "Second semester" : n === 3 ? "Third semester" : "Every semester");
