/**
 * V505: the examination cards withheld — every approved registration whose card the card's own rule refuses, and why — for
 * Exams & Records, the Bursary and the Registry. The server decides; this only says it.
 */

export type WithheldCode = "EXAM_CARD_NOT_CLEARED" | "EXAM_CARD_NOT_RELEASED" | "EXAM_CARD_NO_COURSES" | "EXAM_CARD_NOT_IN_STUDY";

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
  { code: "EXAM_CARD_NOT_CLEARED", label: "Not cleared by the Bursary", who: "The student settles the fees the scheme requires" },
  { code: "EXAM_CARD_NOT_RELEASED", label: "Cards not yet released", who: "Exams & Records releases the cards" },
  { code: "EXAM_CARD_NO_COURSES", label: "No course on the registration", who: "The student or the department adds the courses" },
  { code: "EXAM_CARD_NOT_IN_STUDY", label: "Not in study", who: "The Registry" },
];

export function reasonLabel(code: string): string {
  return WITHHELD_REASONS.find((r) => r.code === code)?.label ?? code;
}

/** "counted 10:42" — when the list was worked out */
export function countedAt(iso: string | null | undefined): string {
  if (!iso) return "";
  return `counted ${new Date(iso).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" })}`;
}
