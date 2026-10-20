/** V574: duplicate programmes merged into one — the merges the database proposes, a mapping read from a spreadsheet, and the
 *  merges sent a few at a time so each request stays short. Node-tested. */

export type MergeKind = "SAME_NAME" | "EXACT" | "ONLY" | "CHOOSE" | "NONE" | "TWIN";
export interface MergeSuggestion {
  step: number; kind: MergeKind; from_code: string; from_name: string; from_students: number; to_code: string | null; to_name: string | null; why: string;
  /** the department's programmes of the degree, when the School chooses (JSON text) */
  choices: string | null;
}
export interface MergeProgramme { code: string; name: string; award: string | null; dept_code: string | null; faculty_code: string | null; students: number }
export interface MergePair { from: string; to: string }
export interface MergeEffect { from: string; to: string; fromName?: string; toName?: string; students?: number; moved?: Record<string, number>; kept?: Record<string, number>; refused?: string }
export interface MergeRecord {
  id: string; from_code: string; from_name: string; to_code: string; to_name: string; reason: string; students: number; moved: string; kept: string;
  merged_at: string; merged_office: string | null; merged_by_name: string | null; undone_at: string | null; undo_reason: string | null; undone_by_name: string | null;
  may_undo: boolean;
}

/** what each kind of suggestion means, and whether it is ticked when the screen opens */
export const KIND: Record<MergeKind, { label: string; tone: "ok" | "info" | "warn" | "grey"; ticked: boolean }> = {
  SAME_NAME: { label: "Same name, same department", tone: "ok", ticked: true },
  EXACT: { label: "The School's programme of the same name", tone: "ok", ticked: true },
  TWIN: { label: "Twin in the School's catalogue", tone: "ok", ticked: true },
  ONLY: { label: "The department's only one: check the name", tone: "warn", ticked: false },
  CHOOSE: { label: "The School chooses", tone: "info", ticked: false },
  NONE: { label: "No programme of its degree in the department", tone: "grey", ticked: false },
};

/** the choices a suggestion offers, read from its JSON text */
export function choicesOf(s: Pick<MergeSuggestion, "choices">): { code: string; name: string }[] {
  if (!s.choices) return [];
  try {
    const v = JSON.parse(s.choices) as { code: string; name: string }[];
    return Array.isArray(v) ? v.filter((x) => x && x.code) : [];
  } catch {
    return [];
  }
}

/** the pairs in the order they must run: codes of one name first, then into the catalogue, then the catalogue's twins */
export function orderedPairs(rows: { step: number; from: string; to: string }[]): MergePair[] {
  return [...rows].sort((a, b) => a.step - b.step).map(({ from, to }) => ({ from, to }));
}

/** the pairs in chunks of n, in order */
export function chunks<T>(xs: T[], n: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < xs.length; i += Math.max(1, n)) out.push(xs.slice(i, i + Math.max(1, n)));
  return out;
}

const norm = (s: string) => s.toLowerCase().replace(/[^a-z]/g, "");
/** a mapping read from a spreadsheet the School edited: the old code and the code it is merged into, by their column names
 *  ("Old code" / "From", "Merge into" / "To"); a row with no target is left out */
export function readMapping(grid: string[][]): { pairs: MergePair[]; problem: string | null } {
  const hi = grid.slice(0, 20).findIndex((r) => {
    const cs = r.map((c) => norm(String(c ?? "")));
    return cs.some((c) => c === "oldcode" || c === "from" || c === "fromcode") && cs.some((c) => c === "mergeinto" || c === "to" || c === "tocode" || c === "mergeintocode");
  });
  if (hi < 0) return { pairs: [], problem: "No header naming an “Old code” column and a “Merge into” column was found in the first 20 rows." };
  const head = grid[hi].map((c) => norm(String(c ?? "")));
  const from = head.findIndex((c) => c === "oldcode" || c === "from" || c === "fromcode");
  const to = head.findIndex((c) => c === "mergeinto" || c === "to" || c === "tocode" || c === "mergeintocode");
  const pairs: MergePair[] = [];
  for (const r of grid.slice(hi + 1)) {
    const f = String(r[from] ?? "").trim().toUpperCase();
    const t = String(r[to] ?? "").trim().toUpperCase();
    if (f && t && f !== t) pairs.push({ from: f, to: t });
  }
  return { pairs, problem: pairs.length ? null : "The file names no old code with a code to merge it into." };
}

/** the rows moved by a merge, in words: "34 students, 2 fee lines" */
export function movedWords(moved: Record<string, number> | undefined): string {
  if (!moved) return "nothing";
  const words: Record<string, [string, string]> = {
    "people.student.programme_code": ["student", "students"], "admissions.pg_application.programme_code": ["application", "applications"],
    "finance.fee_schedule.programme_code": ["fee line", "fee lines"], "catalogue.course_offer.programme_code": ["course offered", "courses offered"],
    "ref.programme_alias.programme_code": ["earlier merge", "earlier merges"],
  };
  const parts = Object.entries(moved).filter(([, n]) => Number(n) > 0).map(([k, n]) => {
    const w = words[k];
    return w ? `${n} ${Number(n) === 1 ? w[0] : w[1]}` : `${n} ${k.replace(/^[a-z]+\./, "").replace(/\.[a-z_]+$/, "").replace(/_/g, " ")}`;
  });
  return parts.length ? parts.join(", ") : "nothing";
}
