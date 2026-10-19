/**
 * V505, V567: the examination cards withheld — every course registration whose card the card's own rule refuses, and why — for
 * Exams & Records, the Bursary and the Registry. The server decides; this only says it. Since V567 the card asks only for the
 * session's school fees paid and the courses registered.
 */

export type WithheldCode = "EXAM_CARD_NOT_PAID" | "EXAM_CARD_NOT_SUBMITTED" | "EXAM_CARD_NO_COURSES";

export interface WithheldRow {
  registration_id: string; student_id: string; full_name: string; matric_no: string | null; programme: string | null; dept_code: string | null;
  faculty_code: string | null; level: number | null; semester: number; code: WithheldCode; reason: string;
}

export interface Withheld {
  session: string; semester: number | null; current: string | null; sessions: string[];
  counts: Record<WithheldCode, number>; total: number; page: number; size: number; rows: WithheldRow[];
  computedAt: string; refreshing: boolean;
}

/** the reasons in the order the screen shows them, with the word each tile carries and who acts on it */
export const WITHHELD_REASONS: { code: WithheldCode; label: string; who: string }[] = [
  { code: "EXAM_CARD_NOT_PAID", label: "School fees not paid", who: "The student pays; a bank or Quickteller payment counts once Interswitch reports it" },
  { code: "EXAM_CARD_NOT_SUBMITTED", label: "Registration not submitted", who: "The student submits the course registration" },
  { code: "EXAM_CARD_NO_COURSES", label: "No course on the registration", who: "The student or the department adds the courses" },
];

export function reasonLabel(code: string): string {
  return WITHHELD_REASONS.find((r) => r.code === code)?.label ?? code;
}

/** "counted 10:42" — when the list was worked out */
export function countedAt(iso: string | null | undefined): string {
  if (!iso) return "";
  return `counted ${new Date(iso).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" })}`;
}
