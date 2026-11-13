/**
 * V656: deleting staff — teaching and non-academic. The database decides per person: tied to nothing, deleted permanently; tied to
 * any record (a class taught, a score, a sign-in, a change made on the portal…), deactivated — off every list, sign-in closed,
 * offices ended, everything they did kept — and restorable. This file holds the words and the arithmetic the screens share.
 */

export type RemovalMode = "AUTO" | "DEACTIVATE" | "REMOVE";

export interface Tie { kind: string; label: string; n: number }

/** one person in a preview or a removal, as iam.remove_staff answers */
export interface RemovalRow {
  person_id: string; staff_number: string | null; name: string | null; category: "ACADEMIC" | "NON_ACADEMIC" | null;
  ties: Tie[]; outcome: string; detail: string | null; applied: boolean; change_id: string | null;
}

export interface RemovalResult { removed: number; deactivated: number; refused: number; rows: RemovalRow[] }

/** a line of the removed-staff record, as iam.staff_changes answers */
export interface StaffChange {
  id: string; person_id: string; staff_number: string | null; name: string; category: "ACADEMIC" | "NON_ACADEMIC" | null;
  action: "STAFF_REMOVED" | "STAFF_DEACTIVATED" | "STAFF_RESTORED"; reason_code: string; reason_words: string | null; reason: string | null;
  ties: Tie[]; actor_name: string | null; actor_office: string | null; at: string; restorable: boolean; restored_at: string | null;
}

/** the person a screen hands to the delete dialog */
export interface StaffPick { id: string; name: string; staffNumber: string | null }

export const REMOVE_REASONS: [string, string][] = [
  ["ADDED_IN_ERROR", "Added in error"],
  ["DUPLICATE", "A duplicate record"],
  ["LEFT_SERVICE", "Left the University (resigned, retired, transferred, contract ended)"],
  ["DECEASED", "Deceased"],
  ["OTHER", "Other (describe)"],
];

export const RESTORE_REASONS: [string, string][] = [
  ["DEACTIVATED_IN_ERROR", "Deactivated in error"],
  ["RETURNED_TO_SERVICE", "Returned to service"],
  ["OTHER", "Other (describe)"],
];

export const MODES: [RemovalMode, string, string][] = [
  ["AUTO", "Delete where possible, deactivate the rest", "Recommended: a person tied to no record is deleted; anyone tied to records is deactivated and kept."],
  ["DEACTIVATE", "Deactivate only", "Everyone is kept on record and can be restored; nobody is deleted."],
  ["REMOVE", "Delete only", "Only people tied to no record are deleted; the rest are left as they are."],
];

/** what each outcome means to the officer: its words and the badge it wears */
export const OUTCOME: Record<string, { word: string; kind: "grey" | "info" | "ok" | "bad" | "warn" }> = {
  REMOVE: { word: "Deleted permanently", kind: "bad" },
  DEACTIVATE: { word: "Deactivated (kept on record)", kind: "warn" },
  CANNOT_REMOVE: { word: "Cannot be deleted", kind: "grey" },
  HOLDS_OFFICE: { word: "Holds another office", kind: "grey" },
  IS_STUDENT: { word: "Also a student", kind: "grey" },
  SELF: { word: "That is you", kind: "grey" },
  NOT_PERMITTED: { word: "Not your office's to change", kind: "grey" },
  NOT_STAFF: { word: "Not on the staff register", kind: "grey" },
  NOT_FOUND: { word: "Not found", kind: "grey" },
  ALREADY_ENDED: { word: "Already deactivated", kind: "grey" },
};

export const ACTION_WORD: Record<StaffChange["action"], string> = {
  STAFF_REMOVED: "Deleted",
  STAFF_DEACTIVATED: "Deactivated",
  STAFF_RESTORED: "Restored",
};

export function outcomeWord(outcome: string, applied = false): string {
  const o = OUTCOME[outcome];
  if (!o) return outcome;
  if (!applied && outcome === "REMOVE") return "Will be deleted permanently";
  if (!applied && outcome === "DEACTIVATE") return "Will be deactivated (kept on record)";
  return o.word;
}

/** how a set of people comes out: deleted, deactivated, left as they are */
export function tally(rows: RemovalRow[]): { remove: number; deactivate: number; refused: number } {
  let remove = 0, deactivate = 0;
  for (const r of rows) {
    if (r.outcome === "REMOVE") remove++;
    else if (r.outcome === "DEACTIVATE") deactivate++;
  }
  return { remove, deactivate, refused: rows.length - remove - deactivate };
}

/** the preview in one line */
export function summaryLine(t: { remove: number; deactivate: number; refused: number }): string {
  const parts: string[] = [];
  if (t.remove) parts.push(`${t.remove} will be deleted permanently`);
  if (t.deactivate) parts.push(`${t.deactivate} will be deactivated and kept`);
  if (t.refused) parts.push(`${t.refused} cannot be changed`);
  return parts.length ? parts.join(" · ") : "Nothing to change";
}

/** the confirm button's words */
export function confirmLabel(t: { remove: number; deactivate: number }): string {
  if (t.remove && t.deactivate) return `Delete ${t.remove} and deactivate ${t.deactivate}`;
  if (t.remove) return `Delete ${t.remove} permanently`;
  if (t.deactivate) return `Deactivate ${t.deactivate}`;
  return "Nothing to change";
}

/** what is wrong with a reason before it is sent; null when it will do (the database says the same) */
export function reasonProblem(code: string, text: string, allowed: [string, string][] = REMOVE_REASONS): string | null {
  if (!code || !allowed.some(([c]) => c === code)) return "Choose the reason.";
  if (code === "OTHER" && text.trim().length < 10) return "Describe the reason in a few words.";
  return null;
}

/** the ties in one line, for a table cell */
export function tiesText(ties: Tie[]): string {
  if (!ties.length) return "No records";
  return ties.map((t) => (t.kind === "ACTED" || t.kind === "SIGNED_IN" || t.n <= 1 ? t.label : `${t.label} (${t.n >= 1000 ? "1,000+" : t.n})`)).join(" · ");
}

/** a staff id typed into an add form that belongs to someone deactivated: they are restored, not added again. V750: a junior's
 *  JP number is a series of its own — JP858 is not P858's holder */
export function deactivatedHolder(pno: string, changes: StaffChange[]): StaffChange | null {
  const digits = pno.replace(/\D/g, "");
  if (!digits) return null;
  const jp = /^\s*JP/i.test(pno);
  return changes.find((c) => c.restorable && (c.staff_number ?? "").replace(/\D/g, "") === digits && /^\s*JP/i.test(c.staff_number ?? "") === jp) ?? null;
}

/** dd/mm/yyyy, as the staff upload reads a date, from the yyyy-mm-dd a date field gives */
export function ddmmyyyy(iso: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso.trim());
  return m ? `${m[3]}/${m[2]}/${m[1]}` : "";
}
