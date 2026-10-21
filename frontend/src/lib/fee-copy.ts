/** V506: a session's fee lines copied from another (finance.copy_session_fees) — each line's scope in words and what copying it
 *  does, as the Fee Setup preview reads them. Node-tested. */

export type CopyAction = "COPY" | "KEPT";

/** one fee line of the source session and what copying it into the target does */
export interface CopyLine {
  item: string; kind: string; amount: number | string; level: number | null; entry_mode: string | null; faculty_code: string | null;
  programme_code: string | null; fee_group: string | null; semester: number | null; indigene: string | null; spillover: boolean; ord: number;
  /** V613: the spillover year the line is for (1, 2, 3), null for any */
  spill_year?: number | null;
  target_amount: number | string | null; action: CopyAction;
}

export const COPY_ACTION: Record<CopyAction, [string, "ok" | "grey"]> = {
  COPY: ["Copied", "ok"],
  KEPT: ["Already stated: kept", "grey"],
};

const KIND: Record<string, string> = { FEE: "", LATE_PAYMENT: "Late payment", LATE_REGISTRATION: "Late registration" };
const SEMESTER: Record<number, string> = { 1: "First semester", 2: "Second semester", 3: "Third semester" };

/** V613: a line's level in words — "200 Level"; a spillover line's level is the programme's final level and its year the spillover
 *  year: "400 Level (SP1)", "400 Level (spillover)" for any year, "Spillover (SP2)" for every programme, "Spillover" for any */
export function levelWords(level: number | null | undefined, spillover: boolean, spillYear?: number | null): string | null {
  if (!spillover) return level ? `${level} Level` : null;
  const base = level ? `${level} Level` : "Spillover";
  return spillYear ? `${base} (SP${spillYear})` : level ? `${base} (spillover)` : base;
}

/** who a line charges, in words: its fee group, level (or spillover and its year), entry mode, faculty, programme, indigeneship and semester */
export function copyScope(l: CopyLine): string {
  return [
    KIND[l.kind] ?? l.kind,
    l.fee_group ? `Group ${l.fee_group}` : null,
    levelWords(l.level, l.spillover, l.spill_year),
    l.entry_mode === "CCE" ? "CCE (part-time)" : l.entry_mode,
    l.faculty_code ? `Faculty ${l.faculty_code}` : null,
    l.programme_code ? `Programme ${l.programme_code}` : null,
    l.indigene === "INDIGENE" ? "Indigene" : l.indigene === "NON_INDIGENE" ? "Non-indigene" : null,
    l.semester ? SEMESTER[l.semester] ?? `Semester ${l.semester}` : null,
  ].filter(Boolean).join(" · ") || "Every student";
}
