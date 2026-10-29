/**
 * V702: the students held a level behind after a change of department (V696), for the Bursary — charged the held level's fee, beside
 * what the session would charge without the hold (GET /api/v1/finance/department-change-fees). The server decides; this only says it.
 */

export interface HeldFeeRow {
  studentId: string; number: string | null; studentName: string; programmeCode: string; programme: string | null; deptCode: string | null;
  facultyCode: string | null; heldLevel: number; unheldLevel: number; heldSpillover: string | null;
  chargedHeld: number; chargedUnheld: number; difference: number;
}
export interface HeldFees {
  session: string; students: number; chargedHeld: number; chargedUnheld: number; higher: number; higherBy: number; lower: number; lowerBy: number;
  rows: HeldFeeRow[];
}

export const naira = (n: number | string | null | undefined) => (n == null ? "—" : `₦${Number(n).toLocaleString("en-NG", { maximumFractionDigits: 0 })}`);

/** the difference in words: what the hold costs the student, saves them, or neither */
export function differenceWords(d: number): string {
  if (d > 0) return `${naira(d)} more held`;
  if (d < 0) return `${naira(-d)} less held`;
  return "The same";
}

const spill = (s: string | null) => (s && s.startsWith("SPILLOVER") ? s.replace("SPILLOVER_YEAR_", "SP").replace("SPILLOVER_LIMIT_REACHED", "beyond the limit") : "");

export const HELD_HEADERS = ["Student", "Matric No.", "Programme", "Level held", "Spillover held", "Level without the hold", "Charged held", "Charged without the hold", "Difference"];

/** one student as an export row (S/N is added by the export) */
export function heldCells(r: HeldFeeRow): (string | number)[] {
  return [r.studentName, r.number ?? "", r.programme ?? r.programmeCode, r.heldLevel, spill(r.heldSpillover), r.unheldLevel,
    Number(r.chargedHeld), Number(r.chargedUnheld), Number(r.difference)];
}

/** the rows narrowed to a search and to those the hold changes ("changed") or all */
export function narrowHeld(rows: HeldFeeRow[], q: string, only: "all" | "changed" | "higher" | "lower"): HeldFeeRow[] {
  const t = q.trim().toLowerCase();
  return rows.filter((r) => (!t || r.studentName.toLowerCase().includes(t) || (r.number ?? "").toLowerCase().includes(t) || r.programmeCode.toLowerCase().includes(t)
    || (r.programme ?? "").toLowerCase().includes(t))
    && (only === "all" || (only === "changed" && Number(r.difference) !== 0) || (only === "higher" && Number(r.difference) > 0) || (only === "lower" && Number(r.difference) < 0)));
}
