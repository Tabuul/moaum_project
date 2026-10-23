/** V648: the school fees setup — a line's use, removing or archiving it, its versions — as /api/v1/finance answers them */

export type UsedBy = "NONE" | "STUDENTS" | "INVOICE" | "PAYMENT" | "LEDGER";
export type Outcome = "REMOVED" | "ARCHIVED" | "CANNOT_REMOVE" | "ALREADY_ARCHIVED" | "NOT_FOUND";
export type RemoveMode = "REMOVE" | "DEACTIVATE" | "AUTO";
export type LineStatus = "ACTIVE" | "ARCHIVED" | "REPLACED";

export interface LineUsage {
  line_id: string; session: string; active: boolean; stated_at: string | null; students: number; references_generated: number; references_open: number;
  references_paid: number; amount_paid: number | string; ledger_entries: number; used_by: UsedBy; removable: boolean; message: string;
}

export interface RemovalRow {
  line_id: string; session: string | null; item: string | null; amount: number | string | null; level: number | null; faculty_code: string | null;
  programme_code: string | null; semester: number | null; entry_mode: string | null; active: boolean; used_by: UsedBy | null; students: number | null;
  references_generated: number | null; references_paid: number | null; amount_paid: number | string | null; ledger_entries: number | null; outcome: Outcome; message: string;
}

export interface RemovalAnswer {
  applied: boolean; mode: RemoveMode; selected: number; REMOVED: number; ARCHIVED: number; CANNOT_REMOVE: number; ALREADY_ARCHIVED: number; NOT_FOUND: number;
  rows: RemovalRow[];
}

export interface LineVersion {
  version: number; line_id: string; at: string; action: "CREATED" | "EDITED" | "VERSIONED" | "REPLACED" | "DEACTIVATED" | "REACTIVATED" | "REMOVED";
  by_id: string | null; by_name: string | null; office: string | null; reason: string | null; item: string | null; amount: number | string | null; level: number | null;
  entry_mode: string | null; faculty_code: string | null; programme_code: string | null; semester: number | null; kind: string | null; spillover: boolean;
  spill_year: number | null; ended: boolean;
}

export interface RemovedLine {
  id: string; at: string; reason_code: string | null; reason_words: string | null; reason: string | null; office: string | null; by_name: string | null;
  item: string | null; amount: number | string | null; level: number | null; entry_mode: string | null; faculty_code: string | null; faculty_name: string | null;
  programme_code: string | null; programme_name: string | null; department_name: string | null; programme_faculty_name?: string | null; semester: number | null; spillover: boolean;
  spill_year: number | null; kind: string | null; indigene: string | null; batch: string | null;
}

export interface EditAnswer { outcome: "EDITED" | "VERSIONED" | "UNCHANGED"; line_id: string; previous_id: string | null; used_by: UsedBy | null; message: string }

/** the reasons a line is removed or archived; Other is described */
export const REMOVE_REASONS: [string, string][] = [
  ["ADDED_IN_ERROR", "Added in error"], ["WRONG_LEVEL", "Wrong level"], ["DUPLICATE", "Duplicate fee structure"], ["WRONG_PROGRAMME", "Wrong programme"],
  ["WRONG_FACULTY", "Wrong faculty"], ["WRONG_SESSION", "Wrong session"], ["WRONG_SEMESTER", "Wrong semester"], ["REPLACED", "Replaced by corrected structure"],
  ["OTHER", "Other"],
];

export const USED_WORDS: Record<UsedBy, [string, "ok" | "warn" | "bad" | "grey" | "info"]> = {
  NONE: ["Never used", "grey"], STUDENTS: ["Charged to students", "info"], INVOICE: ["Used by invoices", "warn"], PAYMENT: ["Used by payments", "bad"],
  LEDGER: ["Used by the ledger", "bad"],
};

export const STATUS_WORDS: Record<LineStatus | "REMOVED", [string, "ok" | "warn" | "bad" | "grey" | "info"]> = {
  ACTIVE: ["Active", "ok"], ARCHIVED: ["Archived", "grey"], REPLACED: ["Replaced", "grey"], REMOVED: ["Removed", "bad"],
};

export const VERSION_WORDS: Record<LineVersion["action"], string> = {
  CREATED: "Created", EDITED: "Edited", VERSIONED: "New version (corrected line)", REPLACED: "Replaced by a corrected line", DEACTIVATED: "Deactivated (archived)",
  REACTIVATED: "Reactivated", REMOVED: "Removed",
};

/** a reason is given, and described when it is Other */
export function reasonReady(code: string, words: string): boolean {
  return !!code && (code !== "OTHER" || words.trim().length >= 10);
}

/** the levels a fee line may name for the programmes chosen, else the faculty's, else every programme's — the programme structure
 *  (finance.fee_levels_of), never a fixed list; a programme list without levels (an older API) gives 100 to 900 */
export function levelsFor(programmes: { code: string; faculty_code: string; levels?: number[] | null }[], faculty: string, chosen: string[]): number[] {
  const pool = chosen.length ? programmes.filter((p) => chosen.includes(p.code)) : faculty ? programmes.filter((p) => p.faculty_code === faculty) : programmes;
  const all = new Set<number>();
  for (const p of pool) for (const l of p.levels ?? []) all.add(l);
  if (!all.size && !pool.some((p) => p.levels)) return [100, 200, 300, 400, 500, 600, 700, 800, 900];
  return [...all].sort((a, b) => a - b);
}

/** what removing would do, in the words the confirmation reads: "3 fee structures selected · 2 can be removed · 1 has financial
 *  dependencies and will be archived instead" */
export function previewWords(a: Pick<RemovalAnswer, "selected" | "REMOVED" | "ARCHIVED" | "CANNOT_REMOVE" | "ALREADY_ARCHIVED" | "NOT_FOUND">): string[] {
  const s = (n: number, one: string, many: string) => `${n.toLocaleString()} ${n === 1 ? one : many}`;
  const out = [s(a.selected, "fee structure selected", "fee structures selected")];
  if (a.REMOVED) out.push(`${s(a.REMOVED, "can", "can")} be removed`);
  if (a.ARCHIVED) out.push(`${s(a.ARCHIVED, "has financial dependencies or charges students and will be archived instead", "have financial dependencies or charge students and will be archived instead")}`);
  if (a.CANNOT_REMOVE) out.push(`${s(a.CANNOT_REMOVE, "cannot be removed (used by financial records)", "cannot be removed (used by financial records)")}`);
  if (a.ALREADY_ARCHIVED) out.push(`${s(a.ALREADY_ARCHIVED, "is archived already", "are archived already")}`);
  if (a.NOT_FOUND) out.push(`${s(a.NOT_FOUND, "is no longer on the schedule", "are no longer on the schedule")}`);
  return out;
}
