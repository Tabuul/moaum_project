/**
 * The minimum course registration load by curriculum (V495): CCMAS and BMAS each have a standing minimum, and a session's or a
 * semester's own where it differs; the Directorate of ICT sets it with a reason. The registration engine reads it at every
 * submission, add and drop; the screens only say it.
 */

export interface InForce {
  curriculum: string; min_units: number | null; applies_as: "SEMESTER" | "SESSION" | "STANDING" | "NONE"; rule_session: string | null;
  rule_semester: number | null; reason: string | null; set_at: string | null; set_by: string | null; set_office: string | null; students: number;
}
export interface LoadRule {
  id: string; curriculum: string; session: string | null; semester: number | null; min_units: number; reason: string; set_at: string;
  set_by: string | null; set_office: string | null;
}
export interface LoadChange {
  id: string; event: string; curriculum: string; session: string | null; semester: number | null; before_units: number | null;
  after_units: number | null; reason: string | null; changed_at: string; changed_by: string | null; changed_office: string | null;
}
export interface LoadRules {
  session: string | null; semester: number | null; current: string | null; sessions: string[]; inForce: InForce[]; rules: LoadRule[];
  maxima: { level: number; applies_to: string; min_units: number; max_units: number }[]; history: LoadChange[];
}
export interface BelowRow {
  registration_id: string; student_id: string; full_name: string; matric_no: string | null; programme: string | null; dept_code: string | null;
  level: number; semester: number; status: string; curriculum: string | null; basis: string; min_units: number; max_units: number; units: number;
}

/** where a minimum comes from, in words */
export const APPLIES_WORD: Record<InForce["applies_as"], string> = {
  SEMESTER: "This semester's own",
  SESSION: "This session's own",
  STANDING: "The standing rule",
  NONE: "Not set",
};

/** a change in the log, in words: "SET", "CHANGED", "REMOVED" */
export function changeWord(event: string): string {
  return event.replace(/^COURSE_REGISTRATION_MIN_CREDIT_/, "").toLowerCase().replace(/^./, (c) => c.toUpperCase());
}

/** what a minimum entered on the form is, or why it cannot be saved — the server checks it again */
export function minimumProblem(raw: string, ceiling: number | null): string | null {
  const t = raw.trim();
  if (!t) return "Enter the minimum credit units.";
  if (!/^-?\d+$/.test(t)) return "Minimum credit units must be a whole number.";
  const n = Number(t);
  if (n <= 0) return "Minimum credit units must be greater than zero.";
  if (ceiling != null && n > ceiling) return `Minimum credit units cannot exceed the maximum of ${ceiling} credit units.`;
  return null;
}
