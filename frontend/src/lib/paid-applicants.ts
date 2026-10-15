/**
 * The Post-UTME paid applicants report (V479): the filters as the address carries them, the words the report uses, and the
 * eight columns of the list and its downloads — one place, so the screen, the workbook and the PDF read the same. Every
 * row and figure is the server's (admissions.post_utme_paid_applicants); nothing here decides who has paid.
 */

export interface PaidFilters {
  session: string;
  /** VERIFIED (the default when empty), PENDING, REVERSED, NOT_STARTED or ALL */
  status: string;
  fac: string;
  dept: string;
  prog: string;
  sex: string;
  entry: string;
  /** payment dates, YYYY-MM-DD, Lagos days */
  from: string;
  to: string;
  jamb: string;
  q: string;
}

export const EMPTY_PAID: PaidFilters = { session: "", status: "", fac: "", dept: "", prog: "", sex: "", entry: "", from: "", to: "", jamb: "", q: "" };

const KEYS: (keyof PaidFilters)[] = ["session", "status", "fac", "dept", "prog", "sex", "entry", "from", "to", "jamb", "q"];
export const PAID_STATUSES = ["VERIFIED", "PENDING", "REVERSED", "NOT_STARTED", "ALL"] as const;
export const ENTRY_MODES = ["UTME", "DIRECT_ENTRY", "TRANSFER"] as const;

const SESSION = /^\d{4}\/\d{4}$/;
const UNIT = /^[A-Za-z0-9_-]{1,20}$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const JAMB = /^[A-Za-z0-9/-]{4,40}$/;

/** the filters read back from the address, each only where it has its shape */
export function readPaidFilters(p: Record<string, string | string[] | undefined>): PaidFilters {
  const out: PaidFilters = { ...EMPTY_PAID };
  for (const k of KEYS) {
    const raw = typeof p[k] === "string" ? (p[k] as string).trim() : "";
    if (!raw) continue;
    let ok: boolean;
    switch (k) {
      case "session": ok = SESSION.test(raw); break;
      case "status": ok = (PAID_STATUSES as readonly string[]).includes(raw); break;
      case "fac": case "dept": case "prog": ok = UNIT.test(raw); break;
      case "sex": ok = raw === "M" || raw === "F"; break;
      case "entry": ok = (ENTRY_MODES as readonly string[]).includes(raw); break;
      case "from": case "to": ok = DATE.test(raw) && !Number.isNaN(new Date(`${raw}T00:00:00Z`).getTime()); break;
      case "jamb": ok = JAMB.test(raw); break;
      default: ok = true;
    }
    if (ok) out[k] = k === "q" ? raw.slice(0, 80) : raw;
  }
  return out;
}

/** the filters as a query string (the session too, unless left out for the API, whose path carries it) */
export function paidQuery(f: Partial<PaidFilters>, extra: Record<string, string | number | undefined | null> = {}, withSession = true): string {
  const q = new URLSearchParams();
  for (const k of KEYS) {
    if (k === "session" && !withSession) continue;
    const v = f[k];
    if (v) q.set(k, v);
  }
  for (const [k, v] of Object.entries(extra)) if (v !== undefined && v !== null && v !== "") q.set(k, String(v));
  return q.toString();
}

/** the API path of the report for a session ("2026/2027" is two path segments, as the admissions desks have it) */
export function paidPath(session: string): string {
  return `/api/v1/admissions/sessions/${session}/paid-applicants`;
}

/** one filter changed, with the ones below it cleared: faculty → department → programme */
export function withPaidChange(f: PaidFilters, key: keyof PaidFilters, value: string): PaidFilters {
  const n: PaidFilters = { ...f, [key]: value };
  if (key === "fac") { n.dept = ""; n.prog = ""; }
  if (key === "dept") n.prog = "";
  if (key === "session") { n.fac = ""; n.dept = ""; n.prog = ""; }
  return n;
}

export const NOT_AVAILABLE = "NOT AVAILABLE";

export function statusWord(s: string | null | undefined): string {
  switch (s || "VERIFIED") {
    case "VERIFIED": return "Paid (verified)";
    case "PENDING": return "Pending — not confirmed";
    case "REVERSED": return "Reversed by the Bursary";
    case "NOT_STARTED": return "No payment started";
    case "ALL": return "Every payment status";
    default: return s ?? "";
  }
}

export function entryWord(e: string | null | undefined): string {
  return e === "DIRECT_ENTRY" ? "Direct Entry" : e === "TRANSFER" ? "Transfer" : e === "UTME" ? "UTME" : (e ?? "");
}

export function genderWord(s: string | null | undefined): string {
  return s === "M" ? "Male" : s === "F" ? "Female" : NOT_AVAILABLE;
}

/** what a row lacks, in words (the server names it; a row is never left out for it) */
export const MISSING_WORD: Record<string, string> = {
  JAMB_NUMBER: "JAMB registration number",
  PROGRAMME_NOT_MATCHED: "Programme not found on the programme register (no faculty or department)",
  GENDER: "Gender",
  PHONE: "Phone number",
  EMAIL: "E-mail address",
  UTME_AGGREGATE: "UTME aggregate score",
};

export function missingWord(code: string): string {
  return MISSING_WORD[code] ?? code;
}

/** the UTME aggregate as JAMB gave it; never computed. A Direct Entry candidate sat no UTME. */
export function aggregateCell(r: Pick<PaidRow, "utme_aggregate" | "entry_mode">): string | number {
  if (r.utme_aggregate !== null && r.utme_aggregate !== undefined) return Number(r.utme_aggregate);
  return r.entry_mode === "DIRECT_ENTRY" ? `${NOT_AVAILABLE} (DIRECT ENTRY)` : NOT_AVAILABLE;
}

export interface PaidRow {
  application_id?: string;
  application_no?: string | null;
  jamb_reg_no: string | null;
  full_name: string;
  programme: string | null;
  programme_code?: string | null;
  faculty_code?: string | null;
  faculty?: string | null;
  dept_code?: string | null;
  department?: string | null;
  sex: string | null;
  entry_mode: string;
  utme_aggregate: number | null;
  phone: string | null;
  email: string | null;
  payment_status: string;
  paid_at?: string | null;
  payment_reference?: string | null;
  receipt_no?: string | null;
  channel?: string | null;
  amount?: number | null;
  verified_payments?: number;
  missing: string[] | null;
}

export interface Counted { n: number }
export interface PaidPage {
  session: string; filters: Record<string, string>; scope: PaidScope; total: number; page: number; size: number;
  rows: PaidRow[]; missing: { field: string; n: number }[];
}
export interface PaidScope { faculty: string | null; department: string | null; programme: string | null }
export interface PaidSummary {
  session: string; filters: Record<string, string>; scope: PaidScope; total: number;
  bySex: (Counted & { sex: string | null })[];
  byEntryMode: (Counted & { entry_mode: string })[];
  byFaculty: (Counted & { faculty_code: string | null; faculty: string | null })[];
  byProgramme: (Counted & { faculty_code: string | null; faculty: string | null; programme_code: string | null; programme: string | null })[];
  byStatus: { status: string; n: number }[];
}
export interface PaidProgramme { faculty_code: string; faculty: string; dept_code: string; department: string; programme_code: string; programme: string; applicants: number }
export interface PaidOptions { sessions: string[]; programmes: PaidProgramme[]; scope: PaidScope }
export interface PaidExport {
  session: string; format: "XLSX" | "PDF"; filters: Record<string, string>; labels: { faculty?: string; department?: string; programme?: string };
  scope: PaidScope; generatedBy: string | null; total: number; rows: PaidRow[];
}

/** the report's columns after S/N, in the order the Academic Office asked for; the engines number the rows from 1 */
export const PAID_HEAD = ["JAMB Registration Number", "Candidate's Full Name", "Course/Programme Applied For", "Gender", "UTME Aggregate Score", "Phone Number", "Email Address"];

export function paidLine(r: PaidRow): (string | number)[] {
  return [
    r.jamb_reg_no || NOT_AVAILABLE,
    r.full_name,
    r.programme || NOT_AVAILABLE,
    genderWord(r.sex),
    aggregateCell(r),
    r.phone || NOT_AVAILABLE,
    r.email || NOT_AVAILABLE,
  ];
}

/** the title, the line under it and the facts a reader needs once the paper is apart from the portal */
export function paidHeading(f: PaidFilters, labels: PaidExport["labels"], total: number, generatedBy: string | null, generatedAt: string): {
  title: string; sub: string; meta: [string, string][];
} {
  const status = f.status || "VERIFIED";
  const title = status === "VERIFIED" ? "PAID POST-UTME APPLICANTS" : `POST-UTME APPLICANTS — ${statusWord(status).toUpperCase()}`;
  const parts: string[] = [];
  if (f.fac) parts.push(`Faculty: ${labels.faculty ?? f.fac}`);
  if (f.dept) parts.push(`Department: ${labels.department ?? f.dept}`);
  if (f.prog) parts.push(`Programme: ${labels.programme ?? f.prog}`);
  if (f.sex) parts.push(`Gender: ${genderWord(f.sex)}`);
  if (f.entry) parts.push(`Entry mode: ${entryWord(f.entry)}`);
  if (f.from || f.to) parts.push(`Paid ${f.from ? `from ${f.from}` : ""}${f.from && f.to ? " " : ""}${f.to ? `to ${f.to}` : ""}`);
  if (f.jamb) parts.push(`JAMB number: ${f.jamb}`);
  if (f.q) parts.push(`Search: "${f.q}"`);
  const meta: [string, string][] = [
    ["Admission session", f.session],
    ["Payment status", statusWord(status)],
    ["Filters", parts.length ? parts.join(" · ") : "None — every applicant in your scope"],
    ["Generated", generatedAt],
    ["Generated by", generatedBy ?? "—"],
    ["Total applicants", total.toLocaleString("en-GB")],
  ];
  return { title, sub: `${f.session} admission session`, meta };
}

/** the download's file name: the report, the session and the narrowest unit chosen */
export function paidFileName(f: PaidFilters, ext: "xlsx" | "pdf"): string {
  const unit = f.prog || f.dept || f.fac;
  const status = f.status && f.status !== "VERIFIED" ? `-${f.status.toLowerCase().replace(/_/g, "-")}` : "";
  return `paid-post-utme-applicants-${f.session.replace("/", "-")}${unit ? `-${unit.toLowerCase()}` : ""}${status}.${ext}`;
}
