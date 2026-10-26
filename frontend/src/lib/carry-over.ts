/** V663: the carry-over picker — the student's earlier courses as the server reads them (registration.carry_over_candidates), and the
 *  pure work of showing them: which a view shows, grouped by level and semester, what is ticked and what it adds up to, and what an
 *  add answered. The server decides every course; the screen only shows. */

export type CarryStatus = "OUTSTANDING" | "NO_RESULT" | "NO_RECORD" | "AWAITED" | "CLEARED" | "ALREADY_REGISTERED" | "NOT_OWED";

export interface CarryRow {
  course_id: string; course_code: string; shown_code: string; title: string; units: number; level: number; course_semester: number;
  both_semesters: boolean; course_group: "GST" | "EPS" | "OTHER"; status: CarryStatus; origin_session: string | null; origin_semester: number | null;
  last_grade: string | null; offering_id: string | null; selectable: boolean; reason: string;
}

export interface CarryList {
  student: { name: string; matricNo: string | null; programme: string | null; level: number };
  session: string; semester: number; rows: CarryRow[];
}

export interface CarryResult { courseId: string; courseCode?: string; title?: string; units?: number; level?: number; added: boolean; code?: string; message?: string; offering?: string | null }

export const STATUS_WORD: Record<CarryStatus, string> = {
  OUTSTANDING: "CARRY-OVER", NO_RESULT: "NO RESULT ON PORTAL", NO_RECORD: "NO RECORD ON PORTAL", AWAITED: "RESULT PENDING",
  CLEARED: "CLEARED", ALREADY_REGISTERED: "ALREADY REGISTERED", NOT_OWED: "NOT A CARRY-OVER",
};

export const STATUS_KIND: Record<CarryStatus, "bad" | "warn" | "grey" | "ok" | "info"> = {
  OUTSTANDING: "bad", NO_RESULT: "warn", NO_RECORD: "warn", AWAITED: "info", CLEARED: "ok", ALREADY_REGISTERED: "info", NOT_OWED: "grey",
};

/** a course the student owes by the record or may declare: what "Only outstanding" shows */
export const OWED: CarryStatus[] = ["OUTSTANDING", "NO_RESULT", "NO_RECORD"];

export interface CarryFilter { view: "OUTSTANDING" | "ALL"; q: string; level: number | null; semester: number | null; group: "" | "GST" | "EPS" | "OTHER" }

export const NO_FILTER: CarryFilter = { view: "OUTSTANDING", q: "", level: null, semester: null, group: "" };

export const semesterWord = (n: number | null | undefined) => (n === 2 ? "Second" : n === 3 ? "Third" : "First");

/** the view to open on: the outstanding ones, or every earlier course when the record states none outstanding */
export function openingView(rows: CarryRow[]): CarryFilter["view"] {
  return rows.some((r) => r.status === "OUTSTANDING") ? "OUTSTANDING" : "ALL";
}

/** the rows a view and its filters show; a search reads the code (with or without its space), the title, the level and the semester */
export function filterRows(rows: CarryRow[], f: CarryFilter): CarryRow[] {
  const term = f.q.trim().toLowerCase();
  const compact = term.replace(/\s+/g, "");
  return rows.filter((r) => {
    if (f.view === "OUTSTANDING" && !OWED.includes(r.status)) return false;
    if (f.level != null && r.level !== f.level) return false;
    if (f.semester != null && !(r.course_semester === f.semester || r.both_semesters)) return false;
    if (f.group && r.course_group !== f.group) return false;
    if (!term) return true;
    const hay = [r.shown_code, r.course_code, r.title, `${r.level}`, `${r.level} level`, `${semesterWord(r.course_semester).toLowerCase()} semester`].join(" ").toLowerCase();
    return hay.includes(term) || r.shown_code.replace(/\s+/g, "").toLowerCase().includes(compact);
  });
}

/** the levels the student's earlier courses sit at, lowest first — only these are offered as filters */
export function levelsOf(rows: CarryRow[]): number[] {
  return [...new Set(rows.map((r) => r.level))].sort((a, b) => a - b);
}

/** the rows by level, then by semester, in the order they print */
export function groupRows(rows: CarryRow[]): { level: number; semesters: { semester: number; rows: CarryRow[] }[] }[] {
  const out: { level: number; semesters: { semester: number; rows: CarryRow[] }[] }[] = [];
  for (const level of levelsOf(rows)) {
    const atLevel = rows.filter((r) => r.level === level);
    const sems = [...new Set(atLevel.map((r) => r.course_semester))].sort((a, b) => a - b);
    out.push({ level, semesters: sems.map((semester) => ({ semester, rows: atLevel.filter((r) => r.course_semester === semester).sort((a, b) => a.shown_code.localeCompare(b.shown_code)) })) });
  }
  return out;
}

/** what is ticked: the number of courses and their units, and how many from each level */
export function selection(rows: CarryRow[], picked: Set<string>): { count: number; units: number; byLevel: [number, number][] } {
  const chosen = rows.filter((r) => picked.has(r.course_id) && r.selectable);
  const byLevel = levelsOf(chosen).map((l) => [l, chosen.filter((r) => r.level === l).length] as [number, number]);
  return { count: chosen.length, units: chosen.reduce((n, r) => n + (r.units ?? 0), 0), byLevel };
}

/** the answer of an add, in words: all added, some added and some not, or none */
export function outcomeWords(results: CarryResult[]): { title: string; kind: "ok" | "bad" | "warn" } {
  const added = results.filter((r) => r.added).length;
  const refused = results.length - added;
  if (!refused) return { title: `${added} carry-over course${added === 1 ? " has" : "s have"} been added successfully.`, kind: "ok" };
  if (!added) return { title: `${refused === 1 ? "The course" : `The ${refused} courses`} could not be added. Review the reasons below.`, kind: "bad" };
  return { title: `${added} course${added === 1 ? "" : "s"} added successfully · ${refused} course${refused === 1 ? "" : "s"} could not be added`, kind: "warn" };
}

/** the carry-overs on a registration, for the summary: count, units, by level and semester of origin */
export function carrySummary(entries: { units: number; level?: number | null; semester?: number | null }[]): { count: number; units: number; byLevel: [number, number][] } {
  const levels = [...new Set(entries.map((e) => e.level ?? 0).filter((l) => l > 0))].sort((a, b) => a - b);
  return {
    count: entries.length,
    units: entries.reduce((n, e) => n + (e.units ?? 0), 0),
    byLevel: levels.map((l) => [l, entries.filter((e) => e.level === l).length] as [number, number]),
  };
}
