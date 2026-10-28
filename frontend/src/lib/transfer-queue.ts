/**
 * V686: the inter-departmental transfer queue, and the applications the old portal approved freed from it together. The database
 * restores each student (people.free_old_portal_transfers → restore_approved_transfer); these are the queue's states and the words of
 * what each freed application came to. Node-tested.
 */

/** an application still in the queue: not yet effected, declined or withdrawn */
export const QUEUE_STATES = ["APPLIED", "FROM_OK", "TO_OK", "REG_OK", "APPROVED", "RECOMMENDED"] as const;

export function inQueue(state: string): boolean {
  return (QUEUE_STATES as readonly string[]).includes(state);
}

export type FreedOutcome = "MOVED" | "RECORDED" | "REFUSED";

export interface Freed {
  application_id: string; student_id: string | null; matric_no: string | null; name: string | null; from_programme: string | null; to_programme: string | null;
  to_level: number | null; outcome: FreedOutcome; swap_ref: string | null; detail: string | null;
}

export const OUTCOME_WORDS: Record<FreedOutcome, [string, "ok" | "info" | "bad"]> = {
  MOVED: ["Moved", "ok"], RECORDED: ["Recorded — already on the programme", "info"], REFUSED: ["Not freed", "bad"],
};

/** the reason the office gives, ready to change */
export const DEFAULT_REASON = "Transfer approved on the old portal; restored without a new application or approvals";

/** what a freeing came to, in one line */
export function freedSummary(rows: Freed[]): string {
  const n = (o: FreedOutcome) => rows.filter((r) => r.outcome === o).length;
  const parts = [`${n("MOVED")} moved to the programme applied for`];
  if (n("RECORDED")) parts.push(`${n("RECORDED")} already on it (recorded)`);
  if (n("REFUSED")) parts.push(`${n("REFUSED")} not freed — see the reason`);
  return parts.join(" · ");
}

/** a refusal's words without its code ("PTQ_NOT_QUEUED: the application is …" → "the application is …") */
export function refusalWords(detail: string | null | undefined): string {
  if (!detail) return "";
  const m = /^[A-Z][A-Z0-9_]+:\s*([\s\S]*)$/.exec(detail);
  return (m ? m[1] : detail).trim();
}
