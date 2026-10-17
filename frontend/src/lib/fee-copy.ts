/** V506: a session's fee lines copied from another (finance.copy_session_fees) — each line's scope in words and what copying it
 *  does, as the Fee Setup preview reads them. Node-tested. */

export type CopyAction = "COPY" | "KEPT";

/** one fee line of the source session and what copying it into the target does */
export interface CopyLine {
  item: string; kind: string; amount: number | string; level: number | null; entry_mode: string | null; faculty_code: string | null;
  programme_code: string | null; fee_group: string | null; semester: number | null; indigene: string | null; spillover: boolean; ord: number;
  target_amount: number | string | null; action: CopyAction;
}

export const COPY_ACTION: Record<CopyAction, [string, "ok" | "grey"]> = {
  COPY: ["Copied", "ok"],
  KEPT: ["Already stated: kept", "grey"],
};

const KIND: Record<string, string> = { FEE: "", LATE_PAYMENT: "Late payment", LATE_REGISTRATION: "Late registration" };
const SEMESTER: Record<number, string> = { 1: "First semester", 2: "Second semester", 3: "Third semester" };

/** who a line charges, in words: its fee group, level (or spillover), entry mode, faculty, programme, indigeneship and semester */
export function copyScope(l: CopyLine): string {
  return [
    KIND[l.kind] ?? l.kind,
    l.fee_group ? `Group ${l.fee_group}` : null,
    l.spillover ? "Spillover" : l.level ? `${l.level} Level` : null,
    l.entry_mode === "CCE" ? "CCE (part-time)" : l.entry_mode,
    l.faculty_code ? `Faculty ${l.faculty_code}` : null,
    l.programme_code ? `Programme ${l.programme_code}` : null,
    l.indigene === "INDIGENE" ? "Indigene" : l.indigene === "NON_INDIGENE" ? "Non-indigene" : null,
    l.semester ? SEMESTER[l.semester] ?? `Semester ${l.semester}` : null,
  ].filter(Boolean).join(" · ") || "Every student";
}
