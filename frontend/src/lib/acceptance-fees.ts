/**
 * The acceptance fee monitor (V724): the filters as the address carries them, the words the monitor uses, and the columns
 * of the list and its download — one place, so the screen and the workbook read the same. Every row and figure is the
 * server's (admissions.acceptance_fee_monitor, read by GET /admissions/sessions/{session}/acceptance-fees); nothing
 * here decides what an applicant owes. The 2026/2027 acceptance fee was stated at ₦25,000 and revised to ₦35,000: an
 * applicant who paid the earlier figure owes the difference, never the fee again, and the monitor says who.
 */

export interface AcceptanceFilters {
  session: string;
  /** NOT_PAID, PENDING, PART_PAID, SETTLED_IN_PARTS, PAID_IN_FULL, OVERPAID or CONFIRMED_WITHOUT_REFERENCE; empty for every band */
  band: string;
  faculty: string;
  programme: string;
  entryMode: string;
  q: string;
}

export const EMPTY_ACCEPTANCE: AcceptanceFilters = { session: "", band: "", faculty: "", programme: "", entryMode: "", q: "" };

const KEYS: (keyof AcceptanceFilters)[] = ["session", "band", "faculty", "programme", "entryMode", "q"];
/** the bands the server puts a released offer in, in the order the monitor shows them — V724: more confirmed than the fee as
 *  stated now (for the refund desk), and an acceptance confirmed with no reference behind it (by hand, or carried over: owes nothing) */
export const BANDS = ["NOT_PAID", "PENDING", "PART_PAID", "SETTLED_IN_PARTS", "PAID_IN_FULL", "OVERPAID", "CONFIRMED_WITHOUT_REFERENCE"] as const;
export const ENTRY_MODES = ["UTME", "DIRECT_ENTRY"] as const;

const SESSION = /^\d{4}\/\d{4}$/;
const UNIT = /^[A-Za-z0-9_-]{1,20}$/;

/** the filters read back from the address, each only where it has its shape */
export function readAcceptanceFilters(p: Record<string, string | string[] | undefined>): AcceptanceFilters {
  const out: AcceptanceFilters = { ...EMPTY_ACCEPTANCE };
  for (const k of KEYS) {
    const raw = typeof p[k] === "string" ? (p[k] as string).trim() : "";
    if (!raw) continue;
    let ok: boolean;
    switch (k) {
      case "session": ok = SESSION.test(raw); break;
      case "band": ok = (BANDS as readonly string[]).includes(raw); break;
      case "faculty": case "programme": ok = UNIT.test(raw); break;
      case "entryMode": ok = (ENTRY_MODES as readonly string[]).includes(raw); break;
      default: ok = true;
    }
    if (ok) out[k] = k === "q" ? raw.slice(0, 80) : raw;
  }
  return out;
}

/** the filters as a query string (the session too, unless left out for the API, whose path carries it) */
export function acceptanceQuery(f: Partial<AcceptanceFilters>, extra: Record<string, string | number | undefined | null> = {}, withSession = true): string {
  const q = new URLSearchParams();
  for (const k of KEYS) {
    if (k === "session" && !withSession) continue;
    const v = f[k];
    if (v) q.set(k, v);
  }
  for (const [k, v] of Object.entries(extra)) if (v !== undefined && v !== null && v !== "") q.set(k, String(v));
  return q.toString();
}

/** the API path of the monitor for a session ("2026/2027" is two path segments, as the admissions desks have it) */
export function acceptancePath(session: string): string {
  return `/api/v1/admissions/sessions/${session}/acceptance-fees`;
}

/** one filter changed, with the ones below it cleared: faculty → programme; a new session starts the filters afresh */
export function withAcceptanceChange(f: AcceptanceFilters, key: keyof AcceptanceFilters, value: string): AcceptanceFilters {
  const n: AcceptanceFilters = { ...f, [key]: value };
  if (key === "faculty") n.programme = "";
  if (key === "session") { n.faculty = ""; n.programme = ""; n.band = ""; }
  return n;
}

export function bandWord(b: string | null | undefined): string {
  switch (b) {
    case "NOT_PAID": return "Not paid";
    case "PENDING": return "Awaiting the bank";
    case "PART_PAID": return "Paid the earlier fee — balance owing";
    case "SETTLED_IN_PARTS": return "Paid the balance";
    case "PAID_IN_FULL": return "Paid in full";
    case "OVERPAID": return "Paid above the fee — for the refund desk";
    case "CONFIRMED_WITHOUT_REFERENCE": return "Confirmed without a reference";
    default: return b ?? "";
  }
}

export function entryWord(e: string | null | undefined): string {
  return e === "DIRECT_ENTRY" ? "Direct Entry" : e === "UTME" ? "UTME" : (e ?? "");
}

/** ₦ with thousands, from a number or the numeric the API renders as a string */
export function naira(n: number | string | null | undefined): string {
  if (n === null || n === undefined || n === "") return "—";
  return `₦${Number(n).toLocaleString("en-NG")}`;
}

/** the monitor's row: admissions.acceptance_fee_monitor in camelCase */
export interface AcceptanceRow {
  applicationId: string;
  applicationNo: string | null;
  jambRegNo: string | null;
  surname: string;
  otherNames: string | null;
  programme: string | null;
  programmeCode: string | null;
  facultyCode: string | null;
  entryMode: string;
  feeDue: number | string;
  paidTotal: number | string;
  balance: number | string;
  /** V724: confirmed above the fee as stated now (OVERPAID) — for the refund desk */
  excess?: number | string | null;
  payments: number;
  firstAmount: number | string | null;
  firstPaidAt: string | null;
  lastPaidAt: string | null;
  openReference: string | null;
  openAmount: number | string | null;
  band: string;
  acceptedAt: string | null;
  /** V724: the record on the register, once the offer is on it — the row's door to /students/{studentId} */
  studentId?: string | null;
  admissionNo: string | null;
  lettersIssued: number;
}

export interface AcceptancePage { rows: AcceptanceRow[]; total: number; page: number; size: number }
export interface AcceptanceSummary {
  offers: number; notPaid: number; pending: number; partPaid: number; settledInParts: number; paidInFull: number;
  /** V724: more confirmed than the fee as stated now; an acceptance confirmed with no reference behind it */
  overpaid?: number; confirmedWithoutReference?: number;
  /** offers whose first confirmed payment was below the fee as stated now: paid the earlier figure */
  paidOldAmount: number;
  /** what every offer has yet to pay — the whole fee where nothing is paid, and the balances */
  outstanding: number | string;
  /** V724: the balance the part payers owe (PART_PAID alone) */
  outstandingBalance?: number | string;
  /** V724: what the OVERPAID offers paid above the fee */
  excess?: number | string;
  collected: number | string; feeDue: number | string | null;
}

/** the record a row opens: the student's own page once the offer is on the register (the Bursary reads it), else the applicant
 *  on the admissions desk by JAMB number or name */
export function acceptanceRecordHref(r: Pick<AcceptanceRow, "studentId" | "jambRegNo" | "surname">, session: string): string | null {
  if (r.studentId) return `/students/${r.studentId}`;
  const q = r.jambRegNo || r.surname;
  return q ? `/admissions/applicants?session=${encodeURIComponent(session)}&q=${encodeURIComponent(q)}` : null;
}
export interface AcceptanceOptions {
  faculties: { code: string; name: string }[];
  programmes: { code: string; name: string; faculty: string }[];
  bands?: string[];
}

/** the offers whose acceptance is not yet met in full: not paid, awaiting the bank, or the earlier fee paid */
export function stillOwing(s: Pick<AcceptanceSummary, "notPaid" | "pending" | "partPaid">): number {
  return (s.notPaid ?? 0) + (s.pending ?? 0) + (s.partPaid ?? 0);
}

/** the download's columns after S/N; the engines number the rows from 1 */
export const ACCEPTANCE_HEAD = ["JAMB number", "Application number", "Name", "Programme", "Entry mode", "Fee due", "Paid", "Balance", "Excess", "Payments", "First amount paid", "Standing", "Admission number", "Letters issued"];

export function acceptanceLine(r: AcceptanceRow): (string | number)[] {
  return [
    r.jambRegNo ?? "—",
    r.applicationNo ?? "—",
    [r.surname, r.otherNames].filter(Boolean).join(", "),
    r.programme ?? "—",
    entryWord(r.entryMode),
    Number(r.feeDue),
    Number(r.paidTotal),
    Number(r.balance),
    Number(r.excess ?? 0),
    r.payments ?? 0,
    r.firstAmount === null || r.firstAmount === undefined ? "—" : Number(r.firstAmount),
    bandWord(r.band),
    r.admissionNo ?? "—",
    r.lettersIssued ?? 0,
  ];
}

/** the facts a reader needs once the workbook is apart from the portal */
export function acceptanceMeta(f: AcceptanceFilters, labels: { faculty?: string; programme?: string }, total: number, generatedAt: string): [string, string][] {
  const parts: string[] = [];
  if (f.band) parts.push(`Standing: ${bandWord(f.band)}`);
  if (f.faculty) parts.push(`Faculty: ${labels.faculty ?? f.faculty}`);
  if (f.programme) parts.push(`Programme: ${labels.programme ?? f.programme}`);
  if (f.entryMode) parts.push(`Entry mode: ${entryWord(f.entryMode)}`);
  if (f.q) parts.push(`Search: "${f.q}"`);
  return [
    ["Admission session", f.session],
    ["Filters", parts.length ? parts.join(" · ") : "None — every released offer of the session"],
    ["Generated", generatedAt],
    ["Total offers", total.toLocaleString("en-GB")],
  ];
}

/** the download's file name: the monitor, the session and the narrowest filter chosen */
export function acceptanceFileName(f: AcceptanceFilters, ext: "xlsx"): string {
  const unit = f.programme || f.faculty;
  const band = f.band ? `-${f.band.toLowerCase().replace(/_/g, "-")}` : "";
  return `acceptance-fees-${f.session.replace("/", "-")}${unit ? `-${unit.toLowerCase()}` : ""}${band}.${ext}`;
}
