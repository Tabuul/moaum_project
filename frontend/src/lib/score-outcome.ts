/** A score sheet upload's outcome, as the old portal writes it (21 October 2026, V619). A candidate who did not sit is "ABS" there
 *  (or "AB", "ABSENT", "ABS (F)") — in the Outcome column, or in place of the mark itself. That is ABSENT on the register: an F,
 *  counted and owed. A blank outcome is GRADED; anything else is read as written and checked against the register's outcomes.
 *  Node-tested. */

const ABSENCE = new Set(["ABS", "AB", "ABSENT", "ABSF", "ABSENTF"]);

/** "ABS", "Abs (F)", "absent" … → true */
export function isAbsence(cell: string | null | undefined): boolean {
  return ABSENCE.has(String(cell ?? "").toUpperCase().replace(/[^A-Z]/g, ""));
}

/** the outcome of an uploaded row: the Outcome cell as written (blank = GRADED, an ABS = ABSENT), or ABSENT where a mark cell reads
 *  ABS and no mark cell carries a number (an "AB" beside an exam score is not an absence from the examination) */
export function uploadedOutcome(outcomeCell: string | null | undefined, ca: string | null | undefined, exam: string | null | undefined): string {
  const written = String(outcomeCell ?? "").trim().toUpperCase();
  if (written && isAbsence(written)) return "ABSENT";
  if (written && written !== "GRADED") return written;
  const marks = [ca, exam].map((c) => String(c ?? "").trim());
  if (marks.some((c) => /[0-9]/.test(c))) return "GRADED";
  return marks.some((c) => isAbsence(c)) ? "ABSENT" : "GRADED";
}
