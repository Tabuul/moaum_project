/**
 * The school-fee readiness monitor and the student portal's fee gate (V724): the filters as the address carries them, the
 * words the screens use, and the columns of the freshers' list and its download — one place, so the screen and the
 * workbook read the same. Every row and figure is the server's (finance.programme_fee_coverage, finance.intake_fee_monitor,
 * finance.portal_fee_gate — read by GET /finance/sessions/{session}/intake-fees and GET /finance/portal-gate); nothing
 * here decides whether a fee is stated or a portal opens.
 */

export type IntakeTab = "coverage" | "applicants";

export interface IntakeFilters {
  session: string;
  tab: IntakeTab;
  /** NOT_CONFIGURED, NOT_OPEN, AVAILABLE, PAYMENT_PENDING, PART_PAID or PAID; empty for every state */
  feeState: string;
  /** OPEN, EXCEPTION, HELD_ACCEPTANCE_BALANCE, CLEARED, HELD_FEES_NOT_AVAILABLE or HELD_FEES_UNPAID; empty for every state */
  portalState: string;
  faculty: string;
  programme: string;
  entryMode: string;
  q: string;
}

export const EMPTY_INTAKE: IntakeFilters = { session: "", tab: "coverage", feeState: "", portalState: "", faculty: "", programme: "", entryMode: "", q: "" };

const KEYS: (keyof IntakeFilters)[] = ["session", "tab", "feeState", "portalState", "faculty", "programme", "entryMode", "q"];
/** finance.school_fee_state's states, in the order the monitor shows them */
export const FEE_STATES = ["NOT_CONFIGURED", "NOT_OPEN", "AVAILABLE", "PAYMENT_PENDING", "PART_PAID", "PAID"] as const;
/** finance.portal_access_state's answers, held first — V724: the acceptance fee balance comes before the school fees */
export const PORTAL_STATES = ["HELD_ACCEPTANCE_BALANCE", "HELD_FEES_NOT_AVAILABLE", "HELD_FEES_UNPAID", "CLEARED", "EXCEPTION", "OPEN"] as const;
export const ENTRY_MODES = ["UTME", "DIRECT_ENTRY"] as const;

const SESSION = /^\d{4}\/\d{4}$/;
const UNIT = /^[A-Za-z0-9_-]{1,20}$/;

/** the filters read back from the address, each only where it has its shape */
export function readIntakeFilters(p: Record<string, string | string[] | undefined>): IntakeFilters {
  const out: IntakeFilters = { ...EMPTY_INTAKE };
  for (const k of KEYS) {
    const raw = typeof p[k] === "string" ? (p[k] as string).trim() : "";
    if (!raw) continue;
    let ok: boolean;
    switch (k) {
      case "session": ok = SESSION.test(raw); break;
      case "tab": ok = raw === "coverage" || raw === "applicants"; break;
      case "feeState": ok = (FEE_STATES as readonly string[]).includes(raw); break;
      case "portalState": ok = (PORTAL_STATES as readonly string[]).includes(raw); break;
      case "faculty": case "programme": ok = UNIT.test(raw); break;
      case "entryMode": ok = (ENTRY_MODES as readonly string[]).includes(raw); break;
      default: ok = true;
    }
    if (!ok) continue;
    if (k === "tab") out.tab = raw as IntakeTab;
    else out[k] = k === "q" ? raw.slice(0, 80) : raw;
  }
  return out;
}

/** the filters as a query string: the address keeps the session and the tab; the API's path carries the session and
 *  its list knows no tab */
export function intakeQuery(f: Partial<IntakeFilters>, extra: Record<string, string | number | undefined | null> = {}, forApi = false): string {
  const q = new URLSearchParams();
  for (const k of KEYS) {
    if (forApi && (k === "session" || k === "tab")) continue;
    const v = f[k];
    if (v) q.set(k, v);
  }
  for (const [k, v] of Object.entries(extra)) if (v !== undefined && v !== null && v !== "") q.set(k, String(v));
  return q.toString();
}

/** the API path of the monitor for a session ("2026/2027" is two path segments, as the finance desks have it) */
export function intakePath(session: string): string {
  return `/api/v1/finance/sessions/${session}/intake-fees`;
}

/** one filter changed, with the ones below it cleared: faculty → programme; a new session starts the filters afresh */
export function withIntakeChange(f: IntakeFilters, key: keyof IntakeFilters, value: string): IntakeFilters {
  const n: IntakeFilters = { ...f, [key]: value } as IntakeFilters;
  if (key === "faculty") n.programme = "";
  if (key === "session") { n.faculty = ""; n.programme = ""; n.feeState = ""; n.portalState = ""; }
  return n;
}

export function feeStateWord(s: string | null | undefined): string {
  switch (s) {
    case "NOT_CONFIGURED": return "Fees not yet stated";
    case "NOT_OPEN": return "Payment window not open";
    case "AVAILABLE": return "Fees available — nothing paid";
    case "PAYMENT_PENDING": return "Awaiting the bank";
    case "PART_PAID": return "Part paid";
    case "PAID": return "Paid in full";
    default: return s ?? "";
  }
}

export function portalStateWord(s: string | null | undefined): string {
  switch (s) {
    case "OPEN": return "Open (gate does not apply)";
    case "EXCEPTION": return "Open by exception";
    case "HELD_ACCEPTANCE_BALANCE": return "Held — acceptance balance owed";
    case "CLEARED": return "Cleared";
    case "HELD_FEES_NOT_AVAILABLE": return "Held — fees not yet stated";
    case "HELD_FEES_UNPAID": return "Held — fees unpaid";
    default: return s ?? "";
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

/* ── fee configuration: finance.programme_fee_coverage ── */

/** one programme × entry (UTME at 100 Level, Direct Entry at 200 Level): whether a fee line reaches it */
export interface CoverageRow {
  facultyCode: string | null; faculty: string | null; programmeCode: string; programme: string;
  entryMode: string; level: number; covered: boolean; lines: number; admitted: number;
}
/** the figures count programmes, not programme × entry: a programme is covered when every entry of it is, uncovered otherwise,
 *  and uncovered with freshers when an uncovered entry of it has freshers on the register */
export interface Coverage {
  programmes: number; covered: number; uncovered: number;
  uncoveredWithFreshers?: number; freshers?: number;
  rows: CoverageRow[];
  byFaculty: { code: string | null; name: string | null; programmes: number; covered: number; uncovered: number; uncoveredWithFreshers?: number; freshers?: number }[];
}

/* ── the freshers: finance.intake_fee_monitor ── */

export interface IntakeRow {
  studentId: string;
  admissionNo: string | null;
  matricNo: string | null;
  surname: string;
  otherNames: string | null;
  programmeCode: string | null;
  programme: string | null;
  facultyCode: string | null;
  entryMode: string;
  currentLevel: number | null;
  status: string;
  feeStated: boolean;
  due: number | string;
  dueFirstSemester: number | string;
  paid: number | string;
  balance: number | string;
  paidInFull: boolean;
  firstSemesterCleared: boolean;
  openReference: string | null;
  feeState: string;
  /** V724: the acceptance fee balance still owed (a fee revised after part of it was paid); 0 when none */
  acceptanceBalance: number | string;
  /** V724: without an applicant account there is no dashboard to pay on, and the gate does not hold the record */
  hasApplicantAccount: boolean;
  portalState: string;
  accountOpened: boolean;
  lastSignedInAt: string | null;
}
export interface IntakePage { rows: IntakeRow[]; total: number; page: number; size: number }
/** the figures above the list, counted with the list's filters but for the two states (each state tile stays a door) */
export interface IntakeSummary {
  freshers: number;
  feeStates: Record<string, number>;
  portalStates: Record<string, number>;
  /** the student portal open to them: cleared, let through by exception, or not gated */
  cleared: number;
  /** held: the acceptance balance, the fees not stated, or the fees unpaid */
  notCleared: number;
  /** student accounts opened (iam.student_account) — not the same figure as signed in */
  accountsOpened: number;
  /** signed in to the student portal at least once */
  signedIn: number;
  feeStated?: number;
  due?: number | string; collected?: number | string; outstanding?: number | string;
}
export interface IntakeOptions {
  faculties: { code: string; name: string }[];
  programmes: { code: string; name: string; faculty: string }[];
  feeStates?: string[];
  portalStates?: string[];
}

/** the download's columns after S/N; the engines number the rows from 1 */
export const INTAKE_HEAD = ["Admission number", "Matriculation number", "Name", "Programme", "Entry mode", "Level", "Fees stated", "Due", "Due — first semester", "Paid", "Balance", "Fee state", "Acceptance balance", "Applicant account", "Portal", "Student account opened", "Last signed in"];

export function intakeLine(r: IntakeRow): (string | number)[] {
  return [
    r.admissionNo ?? "—",
    r.matricNo ?? "—",
    [r.surname, r.otherNames].filter(Boolean).join(", "),
    r.programme ?? r.programmeCode ?? "—",
    entryWord(r.entryMode),
    r.currentLevel ?? "—",
    r.feeStated ? "Yes" : "No",
    Number(r.due),
    Number(r.dueFirstSemester),
    Number(r.paid),
    Number(r.balance),
    feeStateWord(r.feeState),
    Number(r.acceptanceBalance ?? 0),
    r.hasApplicantAccount === false ? "None" : "Yes",
    portalStateWord(r.portalState),
    r.accountOpened ? "Yes" : "No",
    r.lastSignedInAt ?? "—",
  ];
}

/** the facts a reader needs once the workbook is apart from the portal */
export function intakeMeta(f: IntakeFilters, labels: { faculty?: string; programme?: string }, total: number, generatedAt: string): [string, string][] {
  const parts: string[] = [];
  if (f.feeState) parts.push(`Fee state: ${feeStateWord(f.feeState)}`);
  if (f.portalState) parts.push(`Portal: ${portalStateWord(f.portalState)}`);
  if (f.faculty) parts.push(`Faculty: ${labels.faculty ?? f.faculty}`);
  if (f.programme) parts.push(`Programme: ${labels.programme ?? f.programme}`);
  if (f.entryMode) parts.push(`Entry mode: ${entryWord(f.entryMode)}`);
  if (f.q) parts.push(`Search: "${f.q}"`);
  return [
    ["Entry session", f.session],
    ["Filters", parts.length ? parts.join(" · ") : "None — every UTME and Direct Entry fresher of the session on the register"],
    ["Generated", generatedAt],
    ["Total freshers", total.toLocaleString("en-GB")],
  ];
}

/** the download's file name: the monitor, the session and the narrowest filter chosen */
export function intakeFileName(f: IntakeFilters, ext: "xlsx"): string {
  const unit = f.programme || f.faculty;
  const state = f.portalState ? `-${f.portalState.toLowerCase().replace(/_/g, "-")}` : f.feeState ? `-${f.feeState.toLowerCase().replace(/_/g, "-")}` : "";
  return `school-fees-readiness-${f.session.replace("/", "-")}${unit ? `-${unit.toLowerCase()}` : ""}${state}.${ext}`;
}

/* ── the student portal's fee gate: finance.portal_fee_gate and its exceptions ── */

/** GET /api/v1/finance/portal-gate */
export interface PortalGate {
  enabled: boolean;
  fromSession: string;
  clearsOn: "FIRST_SEMESTER" | "PAID_IN_FULL";
  changedAt: string | null;
  changedOffice: string | null;
  reason: string | null;
  /** the names of policy.academic_session, newest first */
  sessions: string[];
  /** the exceptions that stand now */
  exceptions: PortalGateException[];
}
export interface PortalGateException {
  id: string;
  studentId: string;
  admissionNo: string | null;
  matricNo: string | null;
  name: string;
  basis: string;
  reason: string;
  startsAt: string;
  expiresAt: string;
  grantedOffice: string;
  grantedAt: string;
}

/** what an exception rests on, as finance.grant_portal_fee_exception names it */
export const EXCEPTION_BASES: [string, string][] = [
  ["INSTALMENT_POLICY", "Approved instalment arrangement"],
  ["WAIVER", "Waiver"],
  ["BURSARY_DECISION", "Bursary decision"],
];
export function basisWord(b: string | null | undefined): string {
  return EXCEPTION_BASES.find(([code]) => code === b)?.[1] ?? (b ?? "");
}
export function clearsOnWord(c: string | null | undefined): string {
  return c === "PAID_IN_FULL" ? "Session's fees paid in full" : "First semester's fees paid";
}
/** an exception runs for a stated time of at most 200 days (finance.grant_portal_fee_exception) */
export const EXCEPTION_MAX_DAYS = 200;

/** the offices the API lets set the gate (finance.set_portal_fee_gate), grant or revoke an exception
 *  (finance.grant_portal_fee_exception) and read the panel at all */
export const GATE_SETTERS = ["bursar", "ict", "admin", "super"];
export const GATE_EXCEPTORS = ["bursar", "studentaccounts", "admin", "super"];
export const GATE_READERS = ["bursar", "studentaccounts", "ict", "admin", "super"];
