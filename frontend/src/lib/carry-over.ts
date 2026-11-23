/** V663: the carry-over picker — the student's earlier courses as the server reads them (registration.carry_over_candidates), and the
 *  pure work of showing them: which a view shows, grouped by level and semester, what is ticked and what it adds up to, and what an
 *  add answered. The server decides every course; the screen only shows. */

import type { SpilloverQuote } from "./spillover";
import { shownCode } from "./course-code.ts";
import { SIWES_LOCK_PILL, SIWES_LOCK_TITLE, siwesLockKind, type SiwesLockKind } from "./siwes.ts";

export type CarryStatus = "OUTSTANDING" | "NO_RESULT" | "NO_RECORD" | "AWAITED" | "CLEARED" | "ALREADY_REGISTERED" | "NOT_OWED";

export interface CarryRow {
  course_id: string; course_code: string; shown_code: string; title: string; units: number; level: number; course_semester: number;
  both_semesters: boolean; course_group: "GST" | "EPS" | "OTHER"; status: CarryStatus; origin_session: string | null; origin_semester: number | null;
  last_grade: string | null; offering_id: string | null; selectable: boolean; reason: string;
  /** V691: a GST/EPS course the GST fee holds: added, it would be refused until the fee is paid — and what the fee comes to */
  gst_held?: boolean; gst_to_pay?: number | null;
  /** V777: a SIWES course (every one carries the SIWES fee) the fee holds: added, it would be refused until the fee is paid, or because
   *  it cannot be paid for at all — and the database's words (the first word their code: SIWES_UNPAID, SIWES_FEE_NOT_SET,
   *  SIWES_NOT_IN_REACH), read with lib/siwes siwesLockKind and never shown whole */
  siwes_held?: boolean; siwes_gate?: string | null;
}

export interface CarryList {
  student: { name: string; matricNo: string | null; programme: string | null; level: number };
  session: string; semester: number; rows: CarryRow[];
  /** V682: a spillover student: what registering a course in the semester costs (null for anyone else) */
  fee?: SpilloverQuote | null;
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

/** V691, V777: a course that may be ticked — one the student may add, and not a GST/EPS course the GST fee holds, nor a SIWES course
 *  the SIWES fee holds */
export const tickable = (r: CarryRow) => r.selectable && !r.gst_held && !r.siwes_held;

/** V691: the GST fee the shown courses wait for, once (one payment covers GST and EPS), or null when none waits */
export function gstHeld(rows: CarryRow[]): { count: number; toPay: number | null } | null {
  const held = rows.filter((r) => r.gst_held);
  if (!held.length) return null;
  const amounts = held.map((r) => Number(r.gst_to_pay)).filter((n) => Number.isFinite(n) && n > 0);
  return { count: held.length, toPay: amounts.length ? Math.max(...amounts) : null };
}

/* ── V777: every SIWES course carries the SIWES fee, paid once a session on the SIWES page before the course is added ── */

/** the SIWES courses the SIWES fee holds, by what holds them: the fee unpaid, the fee not yet published, or a course that is not
 *  open to the student (their programme carries no SIWES course at their level, so the fee cannot be paid for it) */
export interface SiwesWait { count: number; unpaid: number; notPublished: number; notOpen: number }

/** V777: the shown courses the SIWES fee holds, counted by kind of hold (the fee is paid once, so one note says it), or null when none is held */
export function siwesHeld(rows: CarryRow[]): SiwesWait | null {
  const kinds = rows.filter((r) => r.siwes_held).map((r) => siwesLockKind(r.siwes_gate));
  if (!kinds.length) return null;
  const n = (k: SiwesLockKind) => kinds.filter((x) => x === k).length;
  return { count: kinds.length, unpaid: n("UNPAID"), notPublished: n("FEE_NOT_SET"), notOpen: n("NOT_IN_REACH") };
}

/** the notes over the picker for the SIWES courses it holds — one for each kind of hold, the fee unpaid first (the only one that
 *  links to the SIWES page, where the fee is paid); the titles are those of Course Registration's own notes (lib/siwes siwesLockNotes) */
export function siwesWaitNotes(w: SiwesWait | null): { kind: "bad" | "info"; title: string; words: string; pay: boolean }[] {
  if (!w) return [];
  const courses = (n: number, first = true) => (n === 1 ? `${first ? "A" : "a"} SIWES course below is` : `${n} SIWES courses below are`);
  const out: { kind: "bad" | "info"; title: string; words: string; pay: boolean }[] = [];
  if (w.unpaid) {
    out.push({ kind: "bad", pay: true, title: "SIWES fee first",
      words: `${courses(w.unpaid)} added once the SIWES fee is paid. It is paid once a session, on your SIWES page, whichever SIWES course you add.` });
  }
  if (w.notPublished) {
    out.push({ kind: "info", pay: false, title: "SIWES fee not published yet",
      words: `The Bursary has not published the SIWES fee for this session; ${courses(w.notPublished, false)} added once it is published and paid.` });
  }
  if (w.notOpen) {
    out.push({ kind: "info", pay: false, title: "SIWES course not open to you",
      words: `${w.notOpen === 1 ? "A SIWES course below cannot be added" : `${w.notOpen} SIWES courses below cannot be added`}: your programme carries no SIWES course at your level, `
        + `so the fee cannot be paid for ${w.notOpen === 1 ? "it" : "them"}. Ask the Academic Office.` });
  }
  return out;
}

/** the pill on a held SIWES row, and the line under its title, in plain words (never a code); null for a row nothing holds. The fee unpaid
 *  reads "SIWES fee first", as the GST fee does on this screen; the other holds read as Course Registration's rows do */
export function siwesRowWords(r: Pick<CarryRow, "siwes_held" | "siwes_gate">): { pill: string; line: string } | null {
  if (!r.siwes_held) return null;
  const kind = siwesLockKind(r.siwes_gate);
  return kind === "UNPAID"
    ? { pill: "SIWES fee first", line: "Pay the SIWES fee on your SIWES page, then add this course." }
    : { pill: SIWES_LOCK_PILL[kind], line: `${SIWES_LOCK_TITLE[kind]}.` };
}

/** the SIWES courses an add refused for the fee, from its answers (the database's code of each refusal): the same counts as siwesHeld,
 *  for the note over the answers — a fee paid, or a window closed, between the list and the add */
export function siwesRefused(results: CarryResult[]): SiwesWait | null {
  const refused = results.filter((x) => !x.added);
  const n = (code: string) => refused.filter((x) => x.code === code).length;
  const w = { unpaid: n("SIWES_UNPAID"), notPublished: n("SIWES_FEE_NOT_SET"), notOpen: n("SIWES_NOT_IN_REACH") };
  const count = w.unpaid + w.notPublished + w.notOpen;
  return count ? { count, ...w } : null;
}

/** what is ticked: the number of courses and their units, and how many from each level */
export function selection(rows: CarryRow[], picked: Set<string>): { count: number; units: number; byLevel: [number, number][] } {
  const chosen = rows.filter((r) => picked.has(r.course_id) && tickable(r));
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

/* ── V666: a carry-over once per course, every attempt kept ── */

/** a course owed now, as registration.carryovers gives it: once each, its last failure, how many failed attempts are owed, the first */
export interface OwedCourse { course_code: string; title: string; units: number; failed_in: string; attempts?: number | null; first_failed_in?: string | null }

export type AttemptResult = "PASSED" | "FAILED" | "AWAITED" | "NO_RESULT" | "REGISTERED";

/** one attempt of a course the student has failed on a published result (registration.carryover_history); course_code is the
 *  catalogue's key the attempts are grouped under, code_as_taken the code that attempt was taken under where the record keeps one
 *  (V771), title the attempt's own title as taken, course_title the course as the catalogue holds it now (the heading its attempts
 *  sit under, V771) */
export interface HistoryRow {
  course_code: string; title: string; session: string; semester: number; grade: string | null; result: AttemptResult; owed: boolean;
  code_as_taken?: string | null; course_title?: string | null;
}

/** the code an attempt is shown under: the code it was taken under where the record keeps one, else the course's own */
export const attemptCode = (h: Pick<HistoryRow, "course_code" | "code_as_taken">) => shownCode(h.code_as_taken ?? h.course_code);

/** what GET /api/v1/me/carryovers/history answers */
export interface CarryHistory { owed: OwedCourse[]; history: HistoryRow[] }

export const RESULT_WORD: Record<AttemptResult, string> = {
  PASSED: "Passed", FAILED: "Failed", AWAITED: "Result awaited", NO_RESULT: "No result on the portal", REGISTERED: "Registered, no result yet",
};

export const RESULT_KIND: Record<AttemptResult, "ok" | "bad" | "info" | "warn" | "grey"> = {
  PASSED: "ok", FAILED: "bad", AWAITED: "info", NO_RESULT: "warn", REGISTERED: "grey",
};

/** "Failed in 2024/2025 semester 1", or "Failed 2 times: first 2024/2025 semester 1, last 2025/2026 semester 1" */
export function attemptsWords(c: OwedCourse): string {
  const n = c.attempts ?? 1;
  if (n <= 1 || !c.first_failed_in || c.first_failed_in === c.failed_in) return `Failed in ${c.failed_in}`;
  return `Failed ${n} times: first ${c.first_failed_in}, last ${c.failed_in}`;
}

/** an attempt in a few words: "2024/2025 semester 1 — F" or "2026/2027 semester 1 — Registered, no result yet"; an attempt taken
 *  under another code than the course is shown under says it: "2023/2024 semester 1 as CMP 301 — F" */
export function attemptWord(h: HistoryRow): string {
  const code = attemptCode(h);
  return `${h.session} semester ${h.semester}${code !== shownCode(h.course_code) ? ` as ${code}` : ""} — ${h.result === "FAILED" || h.result === "PASSED" ? (h.grade ?? RESULT_WORD[h.result]) : RESULT_WORD[h.result]}`;
}

/** the history by course, in the order given: each course with every attempt, owed now or cleared — headed by the course as the
 *  catalogue holds it now (an older reader without course_title gives the first attempt's title); each attempt keeps its own */
export function historyByCourse(rows: HistoryRow[]): { course_code: string; title: string; owed: boolean; attempts: HistoryRow[] }[] {
  const out = new Map<string, { course_code: string; title: string; owed: boolean; attempts: HistoryRow[] }>();
  for (const r of rows) {
    const c = out.get(r.course_code) ?? { course_code: r.course_code, title: r.course_title ?? r.title, owed: r.owed, attempts: [] };
    c.attempts.push(r);
    c.owed = c.owed || r.owed;
    out.set(r.course_code, c);
  }
  return [...out.values()];
}
