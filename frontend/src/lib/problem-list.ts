/**
 * V681: a refusal that names many things at once — "the postgraduate rows do not agree with their stages (24 rows of 2 programmes) —
 * C12916 …: …; C93757 …: …; nothing was changed" — read as its lead, one entry a programme, and what follows the entries, so the
 * window can list the entries one a line. Only the first " — " ends the lead: an entry may carry its own (a stage's label, 900 C — Year 3).
 * Null when the detail is not written that way.
 */
export interface ListedProblem { lead: string; items: string[]; tail: string }

export function listedProblem(detail: string | null | undefined): ListedProblem | null {
  if (!detail) return null;
  const at = detail.indexOf(" — ");
  if (at < 0) return null;
  const lead = detail.slice(0, at).trim();
  let rest = detail.slice(at + 3);
  let tail = "";
  const end = rest.match(/;\s*(nothing was changed[^;]*)$/i);
  if (end && end.index !== undefined) {
    tail = end[1].trim();
    rest = rest.slice(0, end.index);
  }
  const items = rest.split(/;\s+/).map((s) => s.trim()).filter(Boolean);
  return lead && items.length ? { lead, items, tail } : null;
}

/** the refusals written as a list of entries */
export const LISTED_PROBLEMS = new Set(["FEE_STRUCTURE_PG"]);
