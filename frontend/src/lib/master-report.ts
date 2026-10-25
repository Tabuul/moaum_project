/**
 * V650: the Master University Report — the shapes, filters and words the dashboard and the printed report share. Every figure,
 * table and definition is the server's (reporting.master_summary, reporting.master_payments, MasterSections): the dashboard's
 * tables, the PDF's tables and the Excel's sheets are the same sections, so the three can never disagree. These only read them.
 */

export type Money = "ALL" | "GST" | "NONE";

export interface MasterOptions {
  period: { session: string; semester: number };
  sessions: string[];
  bounds: { session: string; starts_on: string | null; first_from: string | null; second_from: string | null }[];
  types: { code: string; label: string }[];
  purposes: { code: string; label: string }[];
  channels: string[];
  modes: string[];
  centres: string[];
  scope: { words: string; faculty: string; department: string; programme: string };
  money: Money;
}

export interface SummaryRow {
  dim: string; faculty_code: string | null; faculty: string | null; dept_code: string | null; department: string | null;
  programme_code: string | null; programme: string | null; level: number | null; sex: string | null; programme_type: string | null; study_mode: string | null;
  departments: number; programmes: number; total: number; male: number; female: number; sex_unknown: number;
  fees_paid: number; fees_part: number; fees_not_paid: number; no_fee: number; any_payment: number; paid_not_registered: number;
  registered: number; not_registered: number; carryover_registered: number; reg_approved: number; reg_pending: number;
  payable: number | null; paid_amount: number | null; outstanding: number | null;
  gst_applicable: number; gst_registered: number; gst_paid: number; gst_not_paid: number; gst_paid_amount: number | null; gst_outstanding: number | null;
  eps_applicable: number; eps_registered: number; eps_paid: number; eps_not_paid: number;
  card_eligible: number; card_issued: number; card_not_issued: number; card_not_eligible: number;
  permit_eligible: number; permit_generated: number; permit_printed: number; permit_not_printed: number;
  registered_not_paid: number; gst_registered_not_paid: number; card_issued_not_eligible: number; permit_generated_not_eligible: number;
}

export interface TxFigures {
  byStatus: { status: string; transactions: number; students: number; amount: number; net: number }[];
  byPurpose: { code: string; label: string; transactions: number; students: number; successful: number; pending: number; failed: number; reversed: number; refunded: number; revenue: number }[];
  byDay: { day: string; transactions: number; amount: number }[];
  bySemester: { semester: number | null; transactions: number; amount: number }[];
  byFaculty: { faculty_code: string | null; faculty: string | null; school_fees: number; revenue: number }[];
  total: { transactions: number; students: number; revenue: number; refunded: number };
}

export interface Reconciliation { check: string; holds: boolean; left?: number; right?: number }

export type Kind = "TEXT" | "INT" | "MONEY" | "DATE" | "DATETIME";
export type Cell = string | number | boolean | null;

/** a section as the server defines it: the same for the dashboard, the PDF and the Excel */
export interface Section { key: string; title: string; headers: string[]; kinds: Kind[]; rows: Cell[][]; note: string | null; total?: number }

export interface MasterSummary {
  filters: Record<string, string | number>;
  scope: string;
  money: Money;
  at: string;
  summary: SummaryRow[];
  transactions: TxFigures | null;
  reconciliation: Reconciliation[];
  sections: Section[];
}

export interface StudentRow {
  student_id: string; matric_no: string | null; jamb_no: string | null; surname: string; other_names: string; sex: string | null; status: string;
  faculty: string | null; department: string | null; programme: string | null; level: number | null; fee_status: string;
  payable: number | null; paid_amount: number | null; outstanding: number | null; registered: boolean; paid_not_registered: boolean;
  gst_status: string; eps_status: string; card_eligible: boolean; card_issued: boolean; permit_eligible: boolean; permit_printed: boolean;
}

export interface Page<T> { total: number; page: number; size: number; rows: T[] }

export interface HistoryRow {
  reference: string; title: string; filters: string; scope: string | null; row_count: number | null; status: string; formats: string | null;
  generated_at: string; completed_at: string | null; actor_office: string; generated_by: string | null;
}

/* ── the filters ─────────────────────────────────────────────────────────────────────────────────────────────────────── */

/** the report's own filters (the scope bar carries session, semester, faculty, department, programme and level) */
export const FILTER_KEYS = ["type", "sex", "astatus", "route", "mode", "centre", "fee", "reg", "gst", "eps", "card", "permit", "from", "to", "purpose", "pstatus", "channel"] as const;
export type FilterKey = (typeof FILTER_KEYS)[number];
export type Filters = Record<FilterKey, string>;

export const EMPTY_FILTERS: Filters = Object.fromEntries(FILTER_KEYS.map((k) => [k, ""])) as Filters;

/** the filters a page was asked for, each well formed or empty */
export function readFilters(p: Record<string, string | string[] | undefined>): Filters {
  const one = (k: string) => (typeof p[k] === "string" ? (p[k] as string).trim() : "");
  const word = (k: string) => (/^[A-Za-z0-9_ ]{1,40}$/.test(one(k)) ? one(k).toUpperCase() : "");
  const date = (k: string) => (/^\d{4}-\d{2}-\d{2}$/.test(one(k)) ? one(k) : "");
  const out = { ...EMPTY_FILTERS };
  for (const k of FILTER_KEYS) out[k] = k === "from" || k === "to" ? date(k) : k === "channel" ? one(k).replace(/[%_]/g, "").slice(0, 40) : word(k);
  if (!["M", "F", "U"].includes(out.sex)) out.sex = "";
  return out;
}

/** the query the API is asked with: the scope's keys and the filters set */
export function masterQuery(scope: { session?: string; sem?: string; fac?: string; dept?: string; prog?: string; level?: string }, f: Filters,
  extra: Record<string, string | number | boolean | undefined> = {}): string {
  const p = new URLSearchParams();
  if (scope.session) p.set("session", scope.session);
  if (scope.sem && scope.sem !== "0") p.set("semester", scope.sem);
  if (scope.fac) p.set("fac", scope.fac);
  if (scope.dept) p.set("dept", scope.dept);
  if (scope.prog) p.set("prog", scope.prog);
  if (scope.level) p.set("level", scope.level);
  for (const k of FILTER_KEYS) if (f[k]) p.set(k, f[k]);
  for (const [k, v] of Object.entries(extra)) if (v !== undefined && v !== "" && v !== false) p.set(k, String(v));
  return p.toString();
}

/** the period a preset names, as days (YYYY-MM-DD); "this semester" and "this session" are the chosen ones' own start dates */
export function presetPeriod(preset: string, today: Date, bounds?: { sessionFrom?: string | null; semesterFrom?: string | null }): { from: string; to: string } | null {
  const iso = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  const t = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  const minus = (n: number) => new Date(t.getFullYear(), t.getMonth(), t.getDate() - n);
  switch (preset) {
    case "TODAY": return { from: iso(t), to: iso(t) };
    case "YESTERDAY": return { from: iso(minus(1)), to: iso(minus(1)) };
    case "WEEK": return { from: iso(minus((t.getDay() + 6) % 7)), to: iso(t) };
    case "MONTH": return { from: iso(new Date(t.getFullYear(), t.getMonth(), 1)), to: iso(t) };
    case "YEAR": return { from: iso(new Date(t.getFullYear(), 0, 1)), to: iso(t) };
    case "SEMESTER": return bounds?.semesterFrom ? { from: bounds.semesterFrom.slice(0, 10), to: iso(t) } : null;
    case "SESSION": return bounds?.sessionFrom ? { from: bounds.sessionFrom.slice(0, 10), to: iso(t) } : null;
    default: return null;
  }
}

export const PRESETS: [string, string][] = [["", "Any date"], ["TODAY", "Today"], ["YESTERDAY", "Yesterday"], ["WEEK", "This week"], ["MONTH", "This month"],
  ["SEMESTER", "This semester"], ["SESSION", "This session"], ["YEAR", "This year"], ["CUSTOM", "Custom date range"]];

export const FEE_WORDS: Record<string, string> = { PAID: "Paid in full", PART_PAID: "Partially paid", NOT_PAID: "Not paid", NO_FEE_STATED: "No fee stated", ANY_PAYMENT: "Any school-fees payment" };
export const REG_WORDS: Record<string, string> = { REGISTERED: "Registered", NOT_REGISTERED: "Not registered", PAID_NOT_REGISTERED: "Paid but not registered", CARRYOVER: "Carry-over registration" };
export const GST_WORDS: Record<string, string> = { PAID: "Paid", NOT_PAID: "Not paid", REGISTERED: "Registered", NOT_REGISTERED: "Not registered", APPLICABLE: "Owed or registered" };
export const CARD_WORDS: Record<string, string> = { ELIGIBLE: "Eligible", NOT_ELIGIBLE: "Not eligible", ISSUED: "Issued (drawn)", NOT_ISSUED: "Eligible, not drawn" };
export const PERMIT_WORDS: Record<string, string> = { ELIGIBLE: "Eligible", GENERATED: "Generated", PRINTED: "Printed", NOT_PRINTED: "Eligible, not printed" };
export const PSTATUS_WORDS: Record<string, string> = { SUCCESSFUL: "Successful", PENDING: "Pending", FAILED: "Failed (expired unpaid)", REVERSED: "Reversed", REFUNDED: "Refunded" };
export const FEE_STATUS_WORDS: Record<string, string> = { FULLY_PAID: "Paid in full", PART_PAYMENT: "Partially paid", NOT_PAID: "Not paid", NO_CHARGE: "No fee stated" };
export const STATUS_WORDS: Record<string, string> = { PAID: "Paid", PART_PAID: "Part paid", NOT_PAID: "Not paid", NOT_APPLICABLE: "Not owed" };
export const SEX_WORDS: Record<string, string> = { M: "Male", F: "Female", U: "Not stated" };

/** the filters as words, for a report's heading */
export function filterLines(f: Filters, options: MasterOptions | null): [string, string][] {
  const out: [string, string][] = [];
  const label = (list: { code: string; label: string }[] | undefined, code: string) => list?.find((x) => x.code === code)?.label ?? code;
  if (f.type) out.push(["Programme type", label(options?.types, f.type)]);
  if (f.sex) out.push(["Gender", SEX_WORDS[f.sex] ?? f.sex]);
  if (f.astatus) out.push(["Student status", f.astatus]);
  if (f.route) out.push(["Admission route", f.route]);
  if (f.mode) out.push(["Study mode", f.mode]);
  if (f.centre) out.push(["Centre", f.centre]);
  if (f.fee) out.push(["School fees", FEE_WORDS[f.fee] ?? f.fee]);
  if (f.reg) out.push(["Registration", REG_WORDS[f.reg] ?? f.reg]);
  if (f.gst) out.push(["GST", GST_WORDS[f.gst] ?? f.gst]);
  if (f.eps) out.push(["EPS", GST_WORDS[f.eps] ?? f.eps]);
  if (f.card) out.push(["Examination card", CARD_WORDS[f.card] ?? f.card]);
  if (f.permit) out.push(["GST permit", PERMIT_WORDS[f.permit] ?? f.permit]);
  if (f.from || f.to) out.push(["Transactions from", `${f.from || "the start"} to ${f.to || "today"}`]);
  if (f.purpose) out.push(["Payment purpose", label(options?.purposes, f.purpose)]);
  if (f.pstatus) out.push(["Payment status", PSTATUS_WORDS[f.pstatus] ?? f.pstatus]);
  if (f.channel) out.push(["Payment channel", f.channel]);
  return out;
}

export function semWord(n: number | string | null | undefined): string {
  const v = Number(n);
  return v === 1 ? "First semester" : v === 2 ? "Second semester" : v === 3 ? "Third semester" : "—";
}

/** a moment as Lagos wall-clock time (UTC+1, no summer time): "YYYY-MM-DD HH:MM" */
export function lagos(iso: string | null | undefined): string {
  if (!iso) return "";
  const d = new Date(iso);
  if (!Number.isFinite(d.getTime())) return String(iso);
  const l = new Date(d.getTime() + 3600000).toISOString();
  return `${l.slice(0, 10)} ${l.slice(11, 16)}`;
}

/** a cell as the section's kind says: numbers grouped, naira with two places, dates and moments in Lagos time */
export function cellText(v: Cell, kind: Kind): string {
  if (v === null || v === undefined || v === "") return "";
  if (kind === "INT" && typeof v === "number") return v.toLocaleString("en-GB");
  if (kind === "MONEY" && typeof v === "number") return v.toLocaleString("en-GB", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  if (kind === "DATETIME") return lagos(String(v));
  if (kind === "DATE") return String(v).slice(0, 10);
  return String(v);
}

export function universityRow(s: { summary: SummaryRow[] }): SummaryRow | undefined {
  return s.summary.find((r) => r.dim === "ALL");
}

export function byDim(s: { summary: SummaryRow[] }, dim: string): SummaryRow[] {
  return s.summary.filter((r) => r.dim === dim);
}

/** the KPI tiles: each figure the server's, and the filter its list opens with */
export function kpis(s: MasterSummary): { label: string; value: number; money?: boolean; open?: Partial<Filters> }[] {
  const a = universityRow(s);
  if (!a) return [];
  const out: { label: string; value: number; money?: boolean; open?: Partial<Filters> }[] = [
    { label: "Total students", value: a.total, open: {} },
    { label: "Male", value: a.male, open: { sex: "M" } },
    { label: "Female", value: a.female, open: { sex: "F" } },
    { label: "School fees paid", value: a.fees_paid, open: { fee: "PAID" } },
    { label: "School fees not paid", value: a.fees_not_paid, open: { fee: "NOT_PAID" } },
    { label: "Partially paid", value: a.fees_part, open: { fee: "PART_PAID" } },
    { label: "Paid but not registered", value: a.paid_not_registered, open: { reg: "PAID_NOT_REGISTERED" } },
    { label: "Registered", value: a.registered, open: { reg: "REGISTERED" } },
    { label: "GST paid", value: a.gst_paid, open: { gst: "PAID" } },
    { label: "GST not paid", value: a.gst_not_paid, open: { gst: "NOT_PAID" } },
    { label: "EPS paid", value: a.eps_paid, open: { eps: "PAID" } },
    { label: "EPS not paid", value: a.eps_not_paid, open: { eps: "NOT_PAID" } },
    { label: "Exam cards issued", value: a.card_issued, open: { card: "ISSUED" } },
    { label: "GST permits printed", value: a.permit_printed, open: { permit: "PRINTED" } },
  ];
  if (s.transactions) {
    out.push({ label: "Total revenue (₦)", value: s.transactions.total.revenue, money: true }, { label: "Total transactions", value: s.transactions.total.transactions });
  }
  return out;
}

/** a KPI's value as a tile shows it */
export function kpiText(k: { value: number; money?: boolean }): string {
  return k.money ? `₦${Number(k.value).toLocaleString("en-GB", { maximumFractionDigits: 0 })}` : Number(k.value).toLocaleString("en-GB");
}
