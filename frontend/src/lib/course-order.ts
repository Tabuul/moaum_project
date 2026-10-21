/**
 * Flexible course registration (V504): the University's order of a registration's courses and the words of the engine's answers.
 *
 * The order is CARRY-OVER (with the deferred and outstanding courses), then GST, then CORE, then ELECTIVE — registration.entry_rank
 * on the server. The API sends each entry's category (registration.entry_category) and the entries in that order; this mirror
 * orders a list that carries only the entry type (the examination card's courses, V501) and keeps the server's order within a
 * category, so the screen, the course form, the card and their PDFs list the same courses in the same order.
 */
export type CourseCategory = "CARRY_OVER" | "GST" | "CORE" | "ELECTIVE";

export const CATEGORIES: CourseCategory[] = ["CARRY_OVER", "GST", "CORE", "ELECTIVE"];

export const CATEGORY_LABEL: Record<CourseCategory, string> = { CARRY_OVER: "Carry-over", GST: "GST", CORE: "Core", ELECTIVE: "Elective" };

const RANK: Record<CourseCategory, number> = { CARRY_OVER: 1, GST: 2, CORE: 3, ELECTIVE: 4 };

export interface Categorised {
  category?: string | null; entryType?: string | null; entry_type?: string | null; kind?: string | null; basis?: string | null; gst_eps?: boolean | null;
}

/** the category: the server's where it sent one, else as registration.entry_category reads the entry type and the course's kind */
export function courseCategory(e: Categorised): CourseCategory {
  if (e.category && e.category in RANK) return e.category as CourseCategory;
  const t = (e.entryType ?? e.entry_type ?? "").toUpperCase();
  const k = (e.kind ?? "").toUpperCase();
  const b = (e.basis ?? "").toUpperCase();
  if (t === "CARRYOVER" || t === "DEFERRED" || t === "REPEAT" || b === "CARRYOVER" || b === "DEFERRED") return "CARRY_OVER";
  if (t === "GST" || k === "GST" || b === "GST" || e.gst_eps === true) return "GST";
  // the programme's own setup decides core or elective (course_offer.basis); without one, the entry's type, then the course's kind
  if (["CORE", "ELECTIVE", "BORROWED", "RESEARCH", "DEFICIENCY"].includes(b)) return b === "ELECTIVE" ? "ELECTIVE" : "CORE";
  if (t === "ELECTIVE" || (!t && k === "ELECTIVE")) return "ELECTIVE";
  return "CORE";
}

/** V512: a GST or EPS course's office, as its code names it */
export function gstOffice(code: string | null | undefined): "GST" | "EPS" {
  return /^(MOAU-|BSU-)?EPS/.test(code ?? "") ? "EPS" : "GST";
}

/** V512: the category's word — a GST/EPS carry-over is listed under carry-over and named with its office ("Carry-over · GST"),
 *  the classification kept for the fee, the permit and the reports */
export function categoryWords(e: Categorised & { courseCode?: string | null; course_code?: string | null }): string {
  const c = courseCategory(e);
  const gst = (e.kind ?? "").toUpperCase() === "GST" || e.gst_eps === true;
  return c === "CARRY_OVER" && gst ? `${CATEGORY_LABEL[c]} · ${gstOffice(e.courseCode ?? e.course_code)}` : CATEGORY_LABEL[c];
}

export function categoryRank(e: Categorised): number {
  return RANK[courseCategory(e)];
}

/** the rows in the University's order; a stable sort, so the server's order within a category (deferred after carry-over, then
 *  the code) is kept */
export function inUniversityOrder<T extends Categorised>(rows: T[]): T[] {
  return rows.map((r, i) => ({ r, i })).sort((a, b) => categoryRank(a.r) - categoryRank(b.r) || a.i - b.i).map((x) => x.r);
}

/** the engine's refusal code ("REG_HIGHER_LEVEL: …" → "REG_HIGHER_LEVEL") */
export function refusalCode(refusal: string | null | undefined): string | null {
  const m = /^([A-Z][A-Z0-9_]+):/.exec(refusal ?? "");
  return m ? m[1] : null;
}

/** the engine's refusal in words, without its code */
export function refusalText(refusal: string | null | undefined): string {
  return (refusal ?? "").replace(/^[A-Z][A-Z0-9_]+:\s*/, "");
}

const STATUS: Record<string, string> = {
  REG_ALREADY_PASSED: "Already passed",
  REG_ALREADY_ADDED: "Already added",
  REG_ALREADY_REGISTERED: "Registered in another semester",
  REG_RESULT_AWAITED: "Result pending",
  REG_NOT_OFFERED_SEMESTER: "Not offered this semester",
  REG_NOT_OFFERED_SESSION: "Not offered this session",
  REG_HIGHER_LEVEL: "Higher level",
  REG_PREREQUISITE: "Prerequisite not passed",
  REG_NOT_AVAILABLE: "Not available to you",
  REG_OTHER_CURRICULUM: "Other curriculum",
  REG_OTHER_CODE_FAMILY: "Other code family",
  REG_OTHER_CATEGORY: "Postgraduate only",
  REG_SIWES_SEMESTER: "SIWES semester",
  REG_COURSE_INACTIVE: "No longer taught",
  REG_COURSE_UNKNOWN: "Unknown course",
  REG_OTHER_COURSES_OFF: "Closed for now",
};

/** a short status for a course the search found: Available, on the list already, or why not. A carry-over that runs in the
 *  semester is put on the registration by the engine itself, so it is never added by hand */
export function courseStatus(c: { refusal?: string | null; on_registration?: boolean; recommended?: boolean | null; category?: string | null; gstHeld?: string | null }): { label: string; ok: boolean } {
  if (c.on_registration) return { label: "Already added", ok: false };
  // V512: a GST/EPS course — a carry-over too — waits for the GST fee
  if (!c.refusal && c.gstHeld) return { label: "GST/EPS payment required", ok: false };
  if (!c.refusal && c.category === "CARRY_OVER" && c.recommended) return { label: "Added automatically", ok: false };
  if (!c.refusal && c.recommended) return { label: "On your list", ok: true };
  if (!c.refusal) return { label: "Available", ok: true };
  const code = refusalCode(c.refusal);
  return { label: (code && STATUS[code]) || "Not available", ok: false };
}

const ADDED_AS: Record<string, string> = {
  PROGRAMME_OTHER_LEVEL: "Your programme, another level",
  UNIVERSITY_GST: "University GST course",
  UNIVERSITY_EPS: "University EPS course",
  DEPARTMENT: "Your department",
  FACULTY: "Your faculty",
  // V611: an earlier course whose result is not on the portal (the old portal's), carried over on the student's word
  CARRY_OVER_DECLARED: "A carry-over you declared (no result on the portal)",
};

export function addedAsLabel(a: string | null | undefined): string | null {
  return a ? ADDED_AS[a] ?? a : null;
}

export interface SearchParams { session: string; semester: number; q?: string; level?: number | null; dept?: string | null; faculty?: string | null; category?: string | null; page?: number }

/** the search's query string — the term trimmed and capped; the engine judges, the browser only asks */
export function searchQuery(p: SearchParams): string {
  const u = new URLSearchParams({ session: p.session, semester: String(p.semester) });
  const q = (p.q ?? "").trim().replace(/\s+/g, " ").slice(0, 60);
  if (q) u.set("q", q);
  if (p.level) u.set("level", String(p.level));
  if (p.dept) u.set("dept", p.dept);
  if (p.faculty) u.set("faculty", p.faculty);
  if (p.category) u.set("category", p.category);
  if (p.page) u.set("page", String(p.page));
  return u.toString();
}

/** what adding a course does to the units: the new total, and whether it passes the maximum */
export function unitsAfter(total: number, units: number, max: number): { total: number; over: boolean } {
  return { total: total + units, over: total + units > max };
}
