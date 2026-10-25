/** V652: the course registration report — one row a student and course, the summary by every dimension and the course-by-course
 *  figures, read from /api/v1/reports/course-registrations; the attendance sheets issued from it. Pure helpers: the query a view
 *  sends, the words a code prints as, the columns an export writes. */

export interface RegRow {
  student_id: string; matric_no: string | null; jamb_no: string | null; full_name: string; sex: string | null;
  faculty_code: string; faculty: string; dept_code: string; department: string; programme_code: string; programme: string;
  programme_category: string | null; admission_route: string | null; study_mode: string | null; centre_code: string | null;
  level: number | null; session: string; semester: number; registration_id: string; registration_status: string;
  submitted_at: string | null; approved_at: string | null; offering_id: string; course_code: string; shown_code: string; course_title: string;
  units: number; category: string; course_kind: string | null; curriculum: string | null; course_dept: string | null;
  entry_type: string | null; entry_status: string | null; carry_over: boolean; added_as: string | null;
  holds_card: boolean; holds_permit: boolean; eligible: boolean; fees_paid?: boolean | null;
}

export interface RegPage { session: string; semester: number | null; page: number; size: number; total: number; scope: ReportScope; rows: RegRow[] }

export interface ReportScope { office: string; faculty: string | null; department: string | null; programme: string | null; courses: string | null }

export interface SummaryRow {
  dimension: string; key: string | null; label: string | null; registrations: number; students: number; male: number; female: number;
  other_sex: number; carry_over: number; eligible: number;
}

export interface CourseRow {
  offering_id: string; course_code: string; shown_code: string; course_title: string; units: number; category: string; curriculum: string | null;
  course_dept: string | null; semester: number; students: number; male: number; female: number; other_sex: number; carry_over: number; eligible: number;
  sheet_reference: string | null; sheets: number; present: number; absent: number; manual_present: number; pending: number;
}

export interface RegFilters {
  category: string; curriculum: string; sex: string; reg: string; eligible: string; course: string; offering: string; q: string; from: string; to: string; dropped: boolean;
}

export const NO_FILTERS: RegFilters = { category: "", curriculum: "", sex: "", reg: "", eligible: "", course: "", offering: "", q: "", from: "", to: "", dropped: false };

export const CATEGORIES: [string, string, string][] = [
  ["GST", "GST courses", "General Studies courses, kept by the GST office"],
  ["EPS", "EPS courses", "Entrepreneurship courses, kept by the EPS office"],
  ["DEPARTMENTAL", "Departmental courses", "courses of the student's own department"],
  ["FACULTY", "Faculty courses", "courses of another department of the student's faculty"],
  ["OTHER", "Other university courses", "courses of a department outside the student's faculty"],
  ["CARRY_OVER", "Carry-over courses", "a course registered again after it was failed or not taken"],
  ["OTHER_COURSES", "Other courses (not GST or EPS)", "every course that is not GST or EPS: departmental, faculty, BMAS, CCMAS, carry-over"],
];

export const CATEGORY_WORD: Record<string, string> = Object.fromEntries(CATEGORIES.map(([k, w]) => [k, w]));

export const REG_STATUSES: [string, string][] = [
  ["SUBMITTED", "Submitted"], ["APPROVED", "Approved"], ["LOCKED", "Locked"], ["DRAFT", "Draft"], ["RETURNED", "Returned"],
];

export const DIMENSIONS: [string, string][] = [
  ["FACULTY", "Faculty"], ["DEPARTMENT", "Department"], ["PROGRAMME", "Programme"], ["LEVEL", "Level"], ["SEX", "Sex"], ["CATEGORY", "Category"], ["COURSE", "Course"],
];

export const SEX_WORD: Record<string, string> = { M: "Male", F: "Female", U: "Not stated" };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export const words = (s: string | null | undefined) => (s ? s.replace(/_/g, " ").toLowerCase().replace(/^./, (c) => c.toUpperCase()) : "");

export const semWord = (n: number | string | null | undefined) => (Number(n) === 2 ? "Second" : Number(n) === 3 ? "Third" : "First");

/** the filters as they ride in the address: only what is set */
export function readFilters(params: Record<string, string | string[] | undefined>): RegFilters {
  const s = (k: string) => (typeof params[k] === "string" ? (params[k] as string).trim() : "");
  const pick = (v: string, allowed: string[]) => (allowed.includes(v.toUpperCase()) ? v.toUpperCase() : "");
  const date = (v: string) => (/^\d{4}-\d{2}-\d{2}$/.test(v) ? v : "");
  return {
    category: pick(s("category"), CATEGORIES.map(([k]) => k)),
    curriculum: pick(s("curriculum"), ["BMAS", "CCMAS"]),
    sex: pick(s("sex"), ["M", "F", "U"]),
    reg: pick(s("reg"), REG_STATUSES.map(([k]) => k)),
    eligible: pick(s("eligible"), ["YES", "NO"]),
    course: /^[A-Za-z][A-Za-z0-9 /-]{1,23}$/.test(s("course")) ? s("course").toUpperCase() : "",
    offering: UUID.test(s("offering")) ? s("offering").toLowerCase() : "",
    q: s("q").slice(0, 80),
    from: date(s("from")),
    to: date(s("to")),
    dropped: s("dropped") === "1",
  };
}

/** the API query for a scope and the filters: the session and semester, the faculty, department, programme and level, then each filter set */
export function regQuery(scope: { session: string; sem: string; fac: string; dept: string; prog: string; level: string }, f: RegFilters): URLSearchParams {
  const p = new URLSearchParams();
  if (scope.session) p.set("session", scope.session);
  if (scope.sem && scope.sem !== "0") p.set("semester", scope.sem);
  if (scope.fac) p.set("fac", scope.fac);
  if (scope.dept) p.set("dept", scope.dept);
  if (scope.prog) p.set("prog", scope.prog);
  if (scope.level) p.set("level", scope.level);
  if (f.category) p.set("category", f.category);
  if (f.curriculum) p.set("curriculum", f.curriculum);
  if (f.sex) p.set("sex", f.sex);
  if (f.reg) p.set("reg", f.reg);
  if (f.eligible) p.set("eligible", f.eligible);
  if (f.course) p.set("course", f.course);
  if (f.offering) p.set("offering", f.offering);
  if (f.q) p.set("q", f.q);
  if (f.from) p.set("from", f.from);
  if (f.to) p.set("to", f.to);
  if (f.dropped) p.set("dropped", "true");
  return p;
}

/** the filters in words, for an export's facts */
export function filterLines(f: RegFilters): [string, string][] {
  const out: [string, string][] = [];
  if (f.category) out.push(["Category", CATEGORY_WORD[f.category] ?? f.category]);
  if (f.curriculum) out.push(["Curriculum", f.curriculum]);
  if (f.sex) out.push(["Sex", SEX_WORD[f.sex] ?? f.sex]);
  if (f.reg) out.push(["Registration", words(f.reg)]);
  if (f.eligible) out.push(["Card or permit", f.eligible === "YES" ? "Held" : "Not held"]);
  if (f.course) out.push(["Course", f.course]);
  if (f.offering && !f.course) out.push(["Course", "One class"]);
  if (f.q) out.push(["Search", f.q]);
  if (f.from || f.to) out.push(["Registered", `${f.from || "…"} to ${f.to || "…"}`]);
  if (f.dropped) out.push(["Dropped courses", "Included"]);
  return out;
}

/** whether a student holds what the examination asks: the GST & EPS permit for a general course, the examination card otherwise */
export function eligibilityWord(r: Pick<RegRow, "category" | "holds_card" | "holds_permit" | "eligible">): string {
  const general = r.category === "GST" || r.category === "EPS";
  return general ? (r.holds_permit ? "Permit" : "No permit") : (r.holds_card ? "Card" : "No card");
}

/** the columns of the student-and-course export, in the order the University asked for */
export const ROW_COLUMNS: [string, (r: RegRow) => string | number][] = [
  ["Matriculation Number", (r) => r.matric_no ?? ""],
  ["JAMB Number", (r) => r.jamb_no ?? ""],
  ["Student Name", (r) => r.full_name],
  ["Sex", (r) => SEX_WORD[r.sex || "U"] ?? ""],
  ["Faculty", (r) => r.faculty],
  ["Department", (r) => r.department],
  ["Programme", (r) => r.programme],
  ["Level", (r) => r.level ?? ""],
  ["Session", (r) => r.session],
  ["Semester", (r) => semWord(r.semester)],
  ["Course Code", (r) => r.shown_code],
  ["Course Title", (r) => r.course_title],
  ["Units", (r) => r.units],
  ["Course Type", (r) => r.course_kind ?? ""],
  ["Category", (r) => CATEGORY_WORD[r.category] ?? words(r.category)],
  ["Curriculum", (r) => r.curriculum ?? ""],
  ["Carry-over", (r) => (r.carry_over ? "Yes" : "No")],
  ["Registration Status", (r) => words(r.registration_status)],
  ["Submitted", (r) => (r.submitted_at ? new Date(r.submitted_at).toLocaleDateString("en-GB") : "")],
  ["Approved", (r) => (r.approved_at ? new Date(r.approved_at).toLocaleDateString("en-GB") : "")],
  ["Card or Permit", (r) => eligibilityWord(r)],
];

export const COURSE_COLUMNS: [keyof CourseRow, string][] = [
  ["students", "Registered"], ["male", "Male"], ["female", "Female"], ["carry_over", "Carry-over"], ["eligible", "Card or permit"],
  ["present", "Present"], ["absent", "Absent"], ["manual_present", "Manual present"], ["pending", "Pending verification"],
];

/** the manual lines an attendance sheet may print: the presets, else a custom number from 0 to 60 */
export const MANUAL_PRESETS = [5, 10, 15, 20, 25];

export function manualLines(choice: string, custom: string): number | null {
  if (choice !== "custom") {
    const n = Number(choice);
    return MANUAL_PRESETS.includes(n) ? n : null;
  }
  if (!/^\d{1,2}$/.test(custom.trim())) return null;
  const n = Number(custom.trim());
  return n >= 0 && n <= 60 ? n : null;
}

/** the summary's rows of one dimension, the largest first; the whole as its own row */
export function dimensionRows(rows: SummaryRow[], dimension: string): SummaryRow[] {
  return rows.filter((r) => r.dimension === dimension).sort((a, b) => b.registrations - a.registrations || String(a.label).localeCompare(String(b.label)));
}

export function totalRow(rows: SummaryRow[]): SummaryRow | null {
  return rows.find((r) => r.dimension === "TOTAL") ?? null;
}

/** the label a dimension's key prints as: a sex in words, a level as "300 Level", a category in words */
export function dimensionLabel(dimension: string, r: SummaryRow): string {
  if (dimension === "SEX") return SEX_WORD[r.key || "U"] ?? "Not stated";
  if (dimension === "LEVEL") return r.key ? `${r.key} Level` : "No level";
  if (dimension === "CATEGORY") return CATEGORY_WORD[r.key ?? ""] ?? words(r.key);
  return r.label ?? r.key ?? "—";
}

/** the filter a dimension's row narrows to when it is opened */
export function drill(dimension: string, key: string | null): Record<string, string> {
  if (dimension === "SEX") return { sex: key === "M" || key === "F" ? key : "U" };
  if (!key) return {};
  switch (dimension) {
    case "FACULTY": return { fac: key, dept: "", prog: "" };
    case "DEPARTMENT": return { dept: key, prog: "" };
    case "PROGRAMME": return { prog: key };
    case "LEVEL": return { level: key };
    case "CATEGORY": return { category: key };
    case "COURSE": return { offering: key };
    default: return {};
  }
}
