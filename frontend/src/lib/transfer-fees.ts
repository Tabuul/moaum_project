/**
 * The inter-departmental transfer fee (V727): the monitor's filters as the address carries them, the words the desk, the monitor
 * and the old-portal reconciliation use, the columns of the monitor and its download, and the old portal's export read into the
 * rows the API takes — one place, so the screens and the workbook read the same. Every figure is the server's
 * (people.transfer_entitlement, people.transfer_fee_monitor, people.legacy_transfer_payment): the fee due is the fee the Bursary
 * states now, never a figure written here, and nothing here decides what a student owes. Node-tested.
 */

export interface TransferFeeFilters {
  session: string;
  /** a band of people.transfer_entitlement, or AWAITING_APPLICATION; empty for every band */
  band: string;
  /** what the application waits for (PAYMENT, a desk, DONE, APPLICATION); empty for all */
  awaiting: string;
  faculty: string;
  dept: string;
  search: string;
}

export const EMPTY_TRANSFER_FEES: TransferFeeFilters = { session: "", band: "", awaiting: "", faculty: "", dept: "", search: "" };

const KEYS: (keyof TransferFeeFilters)[] = ["session", "band", "awaiting", "faculty", "dept", "search"];
/** the bands the server puts an application in, in the order the monitor shows them; AWAITING_APPLICATION is an old-portal
 *  payment with no application yet; CLOSED a declined or not recommended application, which owes nothing more */
export const BANDS = ["NOT_PAID", "PENDING", "PART_PAID", "SETTLED_IN_PARTS", "PAID_IN_FULL", "OVERPAID", "AWAITING_APPLICATION", "FEE_NOT_STATED", "NO_FEE", "CLOSED"] as const;
/** what an application waits for, in the order it moves; DECLINED stands for nothing (declined or not recommended) */
export const AWAITINGS = ["PAYMENT", "CURRENT_HOD", "NEW_HOD", "REGISTRY", "ACADEMIC_OFFICE", "SENATE", "REGISTRY_EFFECT", "DONE", "APPLICATION", "DECLINED"] as const;
/** the session the monitor reads every session under */
export const ALL_SESSIONS = "ALL";

const SESSION = /^\d{4}\/\d{4}$/;
const UNIT = /^[A-Za-z0-9_-]{1,20}$/;

/** the filters read back from the address, each only where it has its shape */
export function readTransferFeeFilters(p: Record<string, string | string[] | undefined>): TransferFeeFilters {
  const out: TransferFeeFilters = { ...EMPTY_TRANSFER_FEES };
  for (const k of KEYS) {
    const raw = typeof p[k] === "string" ? (p[k] as string).trim() : "";
    if (!raw) continue;
    let ok: boolean;
    switch (k) {
      case "session": ok = SESSION.test(raw) || raw === ALL_SESSIONS; break;
      case "band": ok = (BANDS as readonly string[]).includes(raw); break;
      case "awaiting": ok = (AWAITINGS as readonly string[]).includes(raw); break;
      case "faculty": case "dept": ok = UNIT.test(raw); break;
      default: ok = true;
    }
    if (ok) out[k] = k === "search" ? raw.slice(0, 80) : raw;
  }
  return out;
}

/** the filters as a query string — the same keys for the address and the API */
export function transferFeeQuery(f: Partial<TransferFeeFilters>, extra: Record<string, string | number | undefined | null> = {}): string {
  const q = new URLSearchParams();
  for (const k of KEYS) {
    const v = f[k];
    if (v) q.set(k, v);
  }
  for (const [k, v] of Object.entries(extra)) if (v !== undefined && v !== null && v !== "") q.set(k, String(v));
  return q.toString();
}

export const TRANSFER_FEES_API = "/api/v1/transfers/fees";

/** one filter changed, with the one below it cleared: faculty → department */
export function withTransferFeeChange(f: TransferFeeFilters, key: keyof TransferFeeFilters, value: string): TransferFeeFilters {
  const n: TransferFeeFilters = { ...f, [key]: value };
  if (key === "faculty") n.dept = "";
  return n;
}

export function bandWord(b: string | null | undefined): string {
  switch (b) {
    case "NOT_PAID": return "Not paid";
    case "PENDING": return "Awaiting the bank";
    case "PART_PAID": return "Part paid — balance owed";
    case "SETTLED_IN_PARTS": return "Paid in full, in parts";
    case "PAID_IN_FULL": return "Paid in full";
    case "OVERPAID": return "Paid above the fee";
    case "AWAITING_APPLICATION": return "Paid on the old portal — no application yet";
    case "FEE_NOT_STATED": return "Fee not stated by the Bursary";
    case "NO_FEE": return "Completed with no fee";
    case "CLOSED": return "Closed — nothing owed";
    default: return b ?? "";
  }
}

export function bandKind(b: string | null | undefined): "grey" | "info" | "ok" | "bad" | "warn" {
  switch (b) {
    case "NOT_PAID": case "FEE_NOT_STATED": return "bad";
    case "PENDING": case "PART_PAID": case "OVERPAID": return "warn";
    case "SETTLED_IN_PARTS": case "PAID_IN_FULL": return "ok";
    case "AWAITING_APPLICATION": return "info";
    default: return "grey";
  }
}

/** what an application waits for, in words; null is a declined one */
export function awaitingWord(a: string | null | undefined): string {
  switch (a) {
    case "PAYMENT": return "The student's payment";
    case "CURRENT_HOD": return "Current HOD";
    case "NEW_HOD": return "New HOD";
    case "REGISTRY": return "Registry";
    case "ACADEMIC_OFFICE": return "Academic Office — final approval";
    case "SENATE": return "Senate";
    case "REGISTRY_EFFECT": return "Registry — to effect";
    case "DONE": return "Completed";
    case "APPLICATION": return "The student's application";
    case "DECLINED": case null: case undefined: case "": return "Declined";
    default: return a;
  }
}

/** ₦ with thousands, from a number or the numeric the API renders as a string */
export function naira(n: number | string | null | undefined): string {
  if (n === null || n === undefined || n === "") return "—";
  return `₦${Number(n).toLocaleString("en-NG")}`;
}

const num = (v: number | string | null | undefined) => (v === null || v === undefined || v === "" ? 0 : Number(v));

/** a row of people.transfer_fee_monitor as the API sends it (the SQL's names) */
export interface TransferFeeRow {
  /** null for a student whose old-portal payments wait for an application */
  application_id: string | null;
  student_id: string;
  matric_no: string | null;
  name: string;
  session: string | null;
  from_programme: string | null;
  to_programme: string | null;
  faculty_code: string | null;
  from_dept: string | null;
  to_dept: string | null;
  state: string | null;
  awaiting: string | null;
  legacy_ref: string | null;
  fee_due: number | string | null;
  portal_paid: number | string | null;
  old_portal_paid: number | string | null;
  paid_total: number | string | null;
  balance: number | string | null;
  excess: number | string | null;
  payments: number | null;
  pending: boolean | null;
  band: string;
  applied_at: string | null;
}

export interface TransferFeePage { rows: TransferFeeRow[]; total: number; page: number; size: number; session?: string | null }

/** what the filter bar offers (GET /transfers/fees/options): the faculties and departments within the office's scope */
export interface TransferFeeOptions {
  current?: string | null;
  sessions?: string[];
  faculties: { code: string; name: string }[];
  departments: { code: string; name: string; faculty_code: string | null }[];
}

/** a session in words: ALL is every session */
export function sessionWord(s: string): string {
  return s === ALL_SESSIONS ? "All sessions" : s;
}

/** a row's keys in the SQL's names, whether the API sent them so or in camelCase (feeDue → fee_due) */
export function snakeKeys<T = Record<string, unknown>>(o: Record<string, unknown>): T {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(o ?? {})) out[k.replace(/[A-Z]/g, (m) => `_${m.toLowerCase()}`)] = v;
  return out as T;
}

export interface TransferFeeSummary {
  fee: number | string | null;
  /** the fee before its last revision, when, by which office and why */
  previousFee?: number | string | null; revisedAt?: string | null; revisedOffice?: string | null; revisedReason?: string | null;
  /** the rows counted, and the applications among them (the rest are old-portal credits awaiting an application) */
  total?: number; applications?: number;
  bands: Record<string, number>;
  awaiting: Record<string, number>;
  outstanding: number | string;
  collectedPortal: number | string;
  collectedOldPortal: number | string;
  excess: number | string;
  readyForFinalApproval: number;
  awaitingApplication: number;
  unmatchedPayments: number;
  /** the live applications that still owe, and those with nothing paid (the server counts live applications only) */
  stillOwing?: number;
  notPaid?: number;
}

/** the applications (and old-portal credits) the summary counts */
export function summaryTotal(s: Pick<TransferFeeSummary, "bands">): number {
  return Object.values(s.bands ?? {}).reduce((a, b) => a + (Number(b) || 0), 0);
}

/** the live applications whose fee is not met in full — the server's count when it gives one (live applications only); else not
 *  paid, awaiting the bank, or part paid — never a CLOSED one (declined or not recommended), which owes nothing more */
export function stillOwing(s: Pick<TransferFeeSummary, "bands"> & Partial<Pick<TransferFeeSummary, "stillOwing">>): number {
  if (typeof s.stillOwing === "number") return s.stillOwing;
  const b = s.bands ?? {};
  return (b.NOT_PAID ?? 0) + (b.PENDING ?? 0) + (b.PART_PAID ?? 0);
}

/** the download's columns after S/N */
export const TRANSFER_FEE_HEAD = ["Matric number", "Name", "Session", "From", "To", "Old-portal reference", "Fee due", "Paid here", "Paid on the old portal",
  "Paid in all", "Balance", "Excess", "Payments", "Standing", "Awaiting", "Applied"];

export function transferFeeLine(r: TransferFeeRow): (string | number)[] {
  return [
    r.matric_no ?? "—",
    r.name,
    r.session ?? "—",
    r.from_programme ?? "—",
    r.to_programme ?? "—",
    r.legacy_ref ?? "—",
    r.fee_due === null || r.fee_due === undefined ? "—" : Number(r.fee_due),
    num(r.portal_paid),
    num(r.old_portal_paid),
    num(r.paid_total),
    r.balance === null || r.balance === undefined ? "—" : Number(r.balance),
    num(r.excess),
    r.payments ?? 0,
    bandWord(r.band),
    awaitingWord(r.awaiting),
    r.applied_at ? r.applied_at.slice(0, 10) : "—",
  ];
}

/** the facts a reader needs once the workbook is apart from the portal */
export function transferFeeMeta(f: TransferFeeFilters, labels: { faculty?: string; dept?: string }, fee: number | string | null, total: number, generatedAt: string): [string, string][] {
  const parts: string[] = [];
  if (f.band) parts.push(`Standing: ${bandWord(f.band)}`);
  if (f.awaiting) parts.push(`Awaiting: ${awaitingWord(f.awaiting)}`);
  if (f.faculty) parts.push(`Faculty: ${labels.faculty ?? f.faculty}`);
  if (f.dept) parts.push(`Department: ${labels.dept ?? f.dept}`);
  if (f.search) parts.push(`Search: "${f.search}"`);
  return [
    ["Session", f.session ? sessionWord(f.session) : "—"],
    ["Transfer fee as stated now", fee === null || fee === undefined ? "Not stated" : naira(fee)],
    ["Filters", parts.length ? parts.join(" · ") : "None — every application of the session"],
    ["Generated", generatedAt],
    ["Total rows", total.toLocaleString("en-GB")],
  ];
}

/** the download's file name: the monitor, the session and the narrowest filter chosen */
export function transferFeeFileName(f: TransferFeeFilters, ext: "xlsx"): string {
  const unit = f.dept || f.faculty;
  const band = f.band ? `-${f.band.toLowerCase().replace(/_/g, "-")}` : "";
  const session = f.session === ALL_SESSIONS ? "-all-sessions" : f.session ? `-${f.session.replace("/", "-")}` : "";
  return `transfer-fees${session}${unit ? `-${unit.toLowerCase()}` : ""}${band}.${ext}`;
}

/* ── the desk (people.transfer_list's V727 columns) ── */

export interface DeskFee {
  state: string;
  fee_due?: number | string | null;
  paid_total?: number | string | null;
  balance?: number | string | null;
  pending?: boolean | null;
  band?: string | null;
}

export const LIVE_STATES = ["APPLIED", "FROM_OK", "TO_OK", "REG_OK", "RECOMMENDED", "APPROVED"];

/** where a live application stands on the fee: nothing paid, at whatever desk it sits (an old-portal application loaded at a later
 *  stage included); part paid, a balance owed; ready for the Academic Office's final approval (paid in full, nothing awaiting the
 *  bank); with the desks (paid in full at a desk before the final approval, or paid while the fee is not stated). A closed
 *  application (declined, not recommended, withdrawn: band CLOSED) owes nothing and stands nowhere. */
export function deskStanding(r: DeskFee): "AWAITING_PAYMENT" | "BALANCE_OWED" | "READY" | "WITH_DESKS" | null {
  if (!LIVE_STATES.includes(r.state) || r.band === "CLOSED") return null;
  const paid = num(r.paid_total);
  const owed = r.balance === null || r.balance === undefined ? null : Number(r.balance);
  if (paid <= 0) return "AWAITING_PAYMENT";
  if (owed !== null && owed > 0) return "BALANCE_OWED";
  if (r.state === "REG_OK" && owed === 0 && !r.pending) return "READY";
  return "WITH_DESKS";
}

/* ── the old portal's transfer payments (the reconciliation list) ── */

/** USED: paid for a transfer the old portal approved and this portal restored — never a credit for another */
export const LEGACY_STATUSES = ["LINKED", "AWAITING_APPLICATION", "USED", "UNMATCHED", "NOT_COUNTED", "OUT_OF_SCOPE", "REJECTED"] as const;

export const LEGACY_STATUS_WORDS: Record<string, [string, "grey" | "info" | "ok" | "bad" | "warn"]> = {
  LINKED: ["Counted toward an application", "ok"],
  AWAITING_APPLICATION: ["Awaiting an application", "info"],
  USED: ["Used by a restored transfer", "info"],
  UNMATCHED: ["Unmatched", "bad"],
  NOT_COUNTED: ["Not counted", "grey"],
  OUT_OF_SCOPE: ["Before the current exercise", "grey"],
  REJECTED: ["Rejected", "bad"],
};

export const ITEM_KIND_WORDS: Record<string, string> = {
  FORM: "Transfer form", LETTER: "Provisional letter", TRANSFER: "Transfer", CHANGE_OF_COURSE: "Change of course",
};

export const DECISIONS = ["LINK", "NOT_COUNTED", "REJECT", "RELEASE"] as const;
export type Decision = (typeof DECISIONS)[number];
export const DECISION_WORDS: Record<Decision, [string, string]> = {
  LINK: ["Count it toward an application", "The payment counts toward the application chosen — one of this student's."],
  NOT_COUNTED: ["Not counted", "The payment does not count toward the transfer fee; the Bursary decides what it was for."],
  REJECT: ["Reject", "The payment never counts toward a transfer fee."],
  RELEASE: ["Release the decision", "The officer's decision is set aside and the payment follows the rule again."],
};

/** a row of people.legacy_transfer_payment with the student, the programme and the application */
export interface LegacyRow {
  payment_id: string; student_id: string | null; session_label: string | null; item: string; item_kind: string; amount: number | string; payref: string | null;
  paid_on: string | null; channel: string | null; status: string; match_method: string | null; application_id: string | null; reason: string | null;
  moved_hint: boolean | null; decided_at: string | null; decided_office: string | null; decided_note: string | null; decided_by_name?: string | null;
  name?: string | null; matric_no?: string | null; programme?: string | null; application_state?: string | null; state?: string | null;
  reference?: string | null; to_programme?: string | null; legacy_ref?: string | null;
  /** the payment archived for review: it counts nowhere until the Bursary restores it */
  archived?: boolean | null;
  /** the student's live application, the one a LINK names by default */
  live_application_id?: string | null; live_application_state?: string | null;
}
/** a row of the list in the names the screen reads, whichever of the likely names the API gives the joined columns */
export function legacyRow(x: Record<string, unknown>): LegacyRow {
  const r = snakeKeys<LegacyRow & Record<string, unknown>>(x);
  const pick = (...v: unknown[]) => (v.find((y) => y !== undefined && y !== null && y !== "") ?? null) as string | null;
  return {
    ...r,
    name: pick(r.name, r.student_name, r.student),
    programme: pick(r.programme, r.programme_name),
    application_state: pick(r.application_state, r.state, r.app_state),
    to_programme: pick(r.application_to_programme, r.to_programme, r.to_programme_name),
    reference: pick(r.reference, r.payment_reference),
    decided_by_name: pick(r.decided_by_name, r.decided_name),
  };
}

/** what an upload row would become (people.legacy_transfer_upload_check) */
export const CHECK_WORDS: Record<string, [string, "grey" | "info" | "ok" | "bad" | "warn"]> = {
  NEW: ["Loaded as an application", "ok"],
  ATTACH: ["Joins the student's application here, at the old portal's stage", "ok"],
  EXISTS: ["Already loaded", "grey"],
  ALREADY_MOVED: ["Already moved — restore instead", "warn"],
  FROM_MISMATCH: ["Programme left does not match", "bad"],
  CONFLICT: ["Conflicts with an application here", "bad"],
  NOT_ELIGIBLE: ["Not eligible", "bad"],
  NO_STUDENT: ["No student", "bad"],
  OUT_OF_SCOPE: ["Before the current exercise", "grey"],
  DUPLICATE_ROW: ["Twice among the rows that would load", "bad"],
  INVALID: ["Invalid", "bad"],
};
/** the statuses a commit takes without the partial switch (EXISTS is left as it is) */
export const LOADABLE = ["NEW", "ATTACH", "EXISTS"];

/** a row the commit leaves out */
export function leftOut(status: string): boolean {
  return !LOADABLE.includes(status);
}

/** the keys the API reads an upload row by (the first of each list is the one this screen writes) */
const ALIASES: [string, string[]][] = [
  ["legacy_ref", ["legacy_ref", "application_ref", "application_no", "application_number", "application_reference", "reference", "ref", "transfer_ref", "transfer_reference", "transfer_no"]],
  ["matric_no", ["matric_no", "matric", "matric_number", "matriculation_number", "matriculation_no", "mat_no", "matno"]],
  ["to_programme", ["to_programme", "to_programme_code", "new_programme", "new_programme_code", "destination", "to_department", "new_department", "programme_to", "proposed_programme", "proposed_course", "new_course", "to_course"]],
  ["from_programme", ["from_programme", "from_programme_code", "old_programme", "old_programme_code", "current_programme", "programme_from", "present_programme", "old_course", "from_course", "current_course"]],
  ["stage", ["stage", "status", "stage_reached", "approval_status", "current_stage"]],
  ["session", ["session", "academic_session"]],
  ["applied_on", ["applied_on", "date_applied", "application_date", "date", "applied_date", "date_of_application"]],
  ["approvals", ["approvals", "approval_history", "history", "approval"]],
  ["documents", ["documents", "document", "attachments", "attachment"]],
  ["payrefs", ["payrefs", "payment_refs", "payment_reference", "payref", "payment_ref", "payment_references", "payment_reference_s", "payment_numbers", "payment_no", "payment_number"]],
  ["reason", ["reason", "reason_for_transfer", "reasons"]],
];
const CANON = new Map(ALIASES.flatMap(([k, names]) => names.map((n) => [n, k] as [string, string])));

/** a spreadsheet heading as a snake_case key: "Matric No." → matric_no, "Date Applied" → applied_on; a heading the API does not
 *  read keeps its snake_case form (the old record is kept as received) */
export function headerKey(h: string): string {
  const k = String(h ?? "").trim().toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "");
  return CANON.get(k) ?? k;
}

export interface SheetRead {
  rows: Record<string, string>[];
  /** the line of the file each row was read from (1 for the first line) */
  lines: number[];
  problem: string | null;
}

/** the old portal's export read back: the header row found (a title may sit above it) by a matriculation number and the
 *  programme moved to or the old reference, each row by its column names, empty rows left out */
export function readLegacyTransferSheet(grid: string[][]): SheetRead {
  const hi = grid.slice(0, 30).findIndex((r) => {
    const keys = r.map((c) => headerKey(String(c ?? "")));
    return keys.includes("matric_no") && (keys.includes("legacy_ref") || keys.includes("to_programme"));
  });
  if (hi < 0) {
    return { rows: [], lines: [], problem: "No header naming the matriculation number and the old-portal reference or the programme moved to was found in the first 30 rows." };
  }
  const head = grid[hi].map((c) => headerKey(String(c ?? "")) || null);
  const rows: Record<string, string>[] = [];
  const lines: number[] = [];
  grid.slice(hi + 1).forEach((r, i) => {
    const row: Record<string, string> = {};
    head.forEach((k, j) => {
      if (!k) return;
      const v = String(r[j] ?? "").trim();
      // the first non-empty column of a name wins, as the API reads it
      if (v && !row[k]) row[k] = v;
    });
    if (Object.keys(row).length) { rows.push(row); lines.push(hi + i + 2); }
  });
  return { rows, lines, problem: rows.length ? null : "The file has no row under its header." };
}

/** the counts of a list of statuses, for the tiles */
export function countBy<T extends { status: string }>(rows: T[]): Record<string, number> {
  const out: Record<string, number> = {};
  for (const r of rows) out[r.status] = (out[r.status] ?? 0) + 1;
  return out;
}
