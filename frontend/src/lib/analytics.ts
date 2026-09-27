/** Financial analytics (V279): the one engine's shapes, the filter bar's state, the date presets, and the query it sends. */

export interface FinFigures { transactions: number; payers: number; amount: number }
export interface FinCategoryRow extends FinFigures { code: string; label: string }
export interface FinFacultyRow extends FinFigures { faculty_code: string | null; faculty: string | null }
export interface FinDepartmentRow extends FinFacultyRow { dept_code: string | null; department: string | null }
export interface FinProgrammeRow extends FinDepartmentRow { programme_code: string | null; programme: string | null }
export interface FinLevelRow extends FinFigures { level: number | null }
export interface FinGenderRow extends FinFigures { sex: string | null }
export interface FinEntryRow extends FinFigures { entry_mode: string | null }
export interface FinSessionRow extends FinFigures { session: string | null }
export interface FinChannelRow extends FinFigures { channel: string | null }
export interface FinTrendRow extends FinFigures { bucket: string }
export interface FinTotals extends FinFigures {
  revenue: number; pending_count: number; pending_amount: number; failed_count: number; refunded_count: number; refunded_amount: number; net_revenue: number;
}
export interface FinCategory { code: string; label: string; ord: number; revenue: boolean; active: boolean; kinds?: string[]; pattern?: string | null; updated_at?: string }
export interface FinScope { kind: "UNIVERSITY" | "PG_SCHOOL" | "COLLEGE" | "FACULTY" | "DEPARTMENT"; label: string; faculty: string; department: string; money: boolean; transactions: boolean; office: string }
export interface FinProgrammeOption { faculty_code: string; faculty: string; dept_code: string; department: string; programme_code: string; programme: string }
export interface FinOptions {
  categories: FinCategory[]; sessions: string[]; currentSession: string | null; entryModes: string[]; channels: string[]; programmes: FinProgrammeOption[];
  levels: number[]; genders: string[]; granularities: string[];
}
export interface FinCompare extends FinFigures { label: string; from: string; to: string; session: string }
export interface FinSummary {
  scope: FinScope; filters: FinFilters & { types: string[] }; options: FinOptions; totals: FinTotals;
  byCategory: FinCategoryRow[]; byFaculty: FinFacultyRow[]; byDepartment: FinDepartmentRow[]; byProgramme: FinProgrammeRow[]; byLevel: FinLevelRow[];
  byGender: FinGenderRow[]; byEntry: FinEntryRow[]; bySession: FinSessionRow[]; byChannel: FinChannelRow[]; trend: FinTrendRow[]; compare: FinCompare | null;
}
export interface FinTransaction {
  source: string; reference: string; receipt_no: string | null; number: string | null; student_id: string | null; application_id: string | null; pg_application_id: string | null;
  surname: string; other_names: string | null; sex: string | null; faculty_code: string | null; faculty: string | null; dept_code: string | null; department: string | null;
  programme_code: string | null; programme: string | null; level: number | null; entry_mode: string | null; entry_session: string | null; session: string;
  category_code: string; category: string; purpose: string | null; kind: string | null; amount: number; confirmed_at: string; generated_at: string; channel: string | null; status: string;
}
export interface FinPage { scope: FinScope; filters: FinFilters; total: number; page: number; size: number; rows: FinTransaction[] }

/** the filter bar's state: every value a string so it round-trips through the query string */
export interface FinFilters {
  preset: string; from: string; to: string; granularity: string; types: string; sex: string; fac: string; dept: string; prog: string; level: string;
  session: string; entry: string; channel: string; q: string;
}
export const EMPTY_FIN: FinFilters = { preset: "", from: "", to: "", granularity: "day", types: "", sex: "", fac: "", dept: "", prog: "", level: "", session: "", entry: "", channel: "", q: "" };

export const PRESETS: { key: string; label: string }[] = [
  { key: "", label: "Any date" }, { key: "today", label: "Today" }, { key: "yesterday", label: "Yesterday" }, { key: "this_week", label: "This week" },
  { key: "last_week", label: "Last week" }, { key: "this_month", label: "This month" }, { key: "last_month", label: "Last month" },
  { key: "this_quarter", label: "This quarter" }, { key: "this_year", label: "This year" }, { key: "last_year", label: "Last year" }, { key: "custom", label: "Custom range" },
];

const iso = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
const startOfWeek = (d: Date) => { const x = new Date(d); const day = (x.getDay() + 6) % 7; x.setDate(x.getDate() - day); return x; };

/** the dates a preset stands for, on the day it is asked; a custom preset keeps what was typed */
export function presetRange(key: string, now = new Date()): { from: string; to: string } | null {
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const y = today.getFullYear(), m = today.getMonth();
  switch (key) {
    case "today": return { from: iso(today), to: iso(today) };
    case "yesterday": { const d = new Date(today); d.setDate(d.getDate() - 1); return { from: iso(d), to: iso(d) }; }
    case "this_week": { const s = startOfWeek(today); return { from: iso(s), to: iso(today) }; }
    case "last_week": { const s = startOfWeek(today); s.setDate(s.getDate() - 7); const e = new Date(s); e.setDate(e.getDate() + 6); return { from: iso(s), to: iso(e) }; }
    case "this_month": return { from: iso(new Date(y, m, 1)), to: iso(today) };
    case "last_month": return { from: iso(new Date(y, m - 1, 1)), to: iso(new Date(y, m, 0)) };
    case "this_quarter": { const qm = m - (m % 3); return { from: iso(new Date(y, qm, 1)), to: iso(today) }; }
    case "this_year": return { from: iso(new Date(y, 0, 1)), to: iso(today) };
    case "last_year": return { from: iso(new Date(y - 1, 0, 1)), to: iso(new Date(y - 1, 11, 31)) };
    default: return null;
  }
}

/** the granularity a preset reads best at, unless the user chose one */
export function presetGranularity(key: string): string {
  return key === "this_year" || key === "last_year" ? "month" : key === "this_quarter" ? "week" : "day";
}

const KEYS: (keyof FinFilters)[] = ["preset", "from", "to", "granularity", "types", "sex", "fac", "dept", "prog", "level", "session", "entry", "channel", "q"];

export function readFinFilters(p: Record<string, string | string[] | undefined>): FinFilters {
  const one = (k: string) => { const v = p[k]; return typeof v === "string" ? v : Array.isArray(v) ? v[0] ?? "" : ""; };
  const f: FinFilters = { ...EMPTY_FIN };
  for (const k of KEYS) f[k] = one(k);
  if (!f.granularity) f.granularity = "day";
  if (f.preset && f.preset !== "custom") { const r = presetRange(f.preset); if (r) { f.from = r.from; f.to = r.to; } }
  return f;
}

/** the query string for the page (every filter) and the API (the same, without the preset) */
export function finQuery(f: Partial<FinFilters>, extra: Record<string, string | number | undefined> = {}, forApi = false): string {
  const p = new URLSearchParams();
  for (const k of KEYS) { const v = f[k]; if (v && !(forApi && k === "preset")) p.set(k, String(v)); }
  for (const [k, v] of Object.entries(extra)) if (v !== undefined && v !== "") p.set(k, String(v));
  return p.toString();
}

export const naira = (n: number | string | null | undefined) => (n == null ? "—" : "₦" + Number(n).toLocaleString("en-NG", { maximumFractionDigits: 0 }));
export const SEX_WORD: Record<string, string> = { M: "Male", F: "Female" };
export const sexWord = (s: string | null | undefined) => (s ? SEX_WORD[s] ?? s : "Not recorded");
export const entryWord = (e: string | null | undefined) => (e ? e.replace(/_/g, " ").toLowerCase().replace(/^./, (c) => c.toUpperCase()).replace(/^Utme$/, "UTME") : "Not recorded");
export const dayOf = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }) : "—");
export const whenAt = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");

/** the bucket of a trend row as a heading: a day, a week, a month, a quarter or a year */
export function bucketLabel(bucket: string, granularity: string): string {
  const d = new Date(bucket + "T00:00:00");
  if (isNaN(d.getTime())) return bucket;
  switch (granularity) {
    case "month": return d.toLocaleDateString("en-GB", { month: "long", year: "numeric" });
    case "quarter": return `Q${Math.floor(d.getMonth() / 3) + 1} ${d.getFullYear()}`;
    case "year": return String(d.getFullYear());
    case "week": return `Week of ${d.toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" })}`;
    default: return d.toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });
  }
}

/** the heading a role reads the analytics under */
export function analyticsHeading(scope: FinScope): string {
  switch (scope.kind) {
    case "FACULTY": return "Faculty Student & Financial Analytics";
    case "DEPARTMENT": return "Department Student & Financial Analytics";
    case "COLLEGE": return "College of Health Sciences Analytics";
    case "PG_SCHOOL": return "Postgraduate School Analytics";
    default:
      return scope.office === "academic" ? "Academic Statistics" : scope.office === "ict" ? "ICT Student & Portal Analytics" : "University Financial Analytics";
  }
}
