/**
 * V609: Old Fees History's upload history — every upload (the Bursary's own loads, the Students Account Officer's uploads for the
 * Bursar's approval, the start overs) as the screen, its query and its Excel lists read them, and what a file states, read in the
 * browser before it is loaded. Node-tested.
 */
import { STATE_WORD as APPROVAL_WORD, type UploadState } from "./old-fees-uploads.ts";

export type HistoryKind = "DIRECT" | "FOR_APPROVAL" | "RESET";
export type HistoryState = "LOADING" | "STOPPED" | "LOADED" | "DONE" | Exclude<UploadState, "DRAFT">;
type Tone = "grey" | "info" | "ok" | "bad" | "warn";

export const KIND_WORD: Record<HistoryKind, string> = {
  DIRECT: "Loaded by the Bursary",
  FOR_APPROVAL: "For the Bursar's approval",
  RESET: "Start over",
};

export const HISTORY_STATE: Record<HistoryState, [string, Tone]> = {
  LOADING: ["Loading", "info"],
  STOPPED: ["Stopped part-way", "warn"],
  LOADED: ["Loaded", "ok"],
  DONE: ["Payments deleted", "grey"],
  PENDING: APPROVAL_WORD.PENDING,
  APPROVING: APPROVAL_WORD.APPROVING,
  APPROVED: APPROVAL_WORD.APPROVED,
  REJECTED: APPROVAL_WORD.REJECTED,
  WITHDRAWN: APPROVAL_WORD.WITHDRAWN,
};

/** the states a kind of upload can be in, for the State filter */
export const KIND_STATES: Record<HistoryKind, HistoryState[]> = {
  DIRECT: ["LOADING", "STOPPED", "LOADED"],
  FOR_APPROVAL: ["PENDING", "APPROVING", "APPROVED", "REJECTED", "WITHDRAWN"],
  RESET: ["DONE"],
};

type Num = number | string | null;

/** one upload as finance.legacy_upload_history lists it, with the names of the people */
export interface HistoryRow {
  id: string; ref: string; kind: HistoryKind; rebuilt: boolean; state: HistoryState; file_name: string | null;
  by_person: string | null; by_name: string | null; office: string | null; at: string; finished_at: string | null;
  parts: number; file_rows: number | null; rows_read: number | null; recorded: number; already: number | null;
  no_student: number | null; no_due: number | null; separate: number | null; taken_over: number | null; corrected: number | null;
  undated: number | null; deleted: number; students: number; sessions: string | null; file_amount: Num; amount: Num;
  decided_by: string | null; decided_by_name: string | null; decided_at: string | null; note: string | null;
}

/** the totals of what the filters find (rows and what was skipped null when no upload of them kept it: those rebuilt) */
export interface HistoryTotals {
  uploads: number; file_rows: number | null; rows_read: number | null; recorded: number; already: number | null; no_student: number | null;
  amount: Num; pending: number; resets: number; deleted: number; deleted_amount: Num;
}

export interface History {
  total: number; page: number; size: number; totals: HistoryTotals; by_kind: Partial<Record<HistoryKind, number>>; rows: HistoryRow[];
  people: { id: string; name: string }[]; offices: string[]; sessions: string[]; since: string | null;
}

export interface HistoryFilters {
  from?: string; to?: string; kind?: HistoryKind | ""; state?: HistoryState | ""; person?: string; office?: string; session?: string; q?: string;
}

/** the history's address for the filters, a page of a size */
export function historyUrl(f: HistoryFilters, size: number, page: number): string {
  const p = new URLSearchParams({ size: String(size), page: String(page) });
  for (const k of ["from", "to", "kind", "state", "person", "office", "session", "q"] as const) {
    const v = (f[k] ?? "").trim();
    if (v) p.set(k, v);
  }
  return `/api/bff/api/v1/finance/legacy-fees/history?${p.toString()}`;
}

/** the filters in words, for the Excel's line under the title */
export function filtersInWords(f: HistoryFilters, people: History["people"] = []): string {
  const parts: string[] = [];
  if (f.from && f.to) parts.push(`${f.from} to ${f.to}`);
  else if (f.from) parts.push(`from ${f.from}`);
  else if (f.to) parts.push(`up to ${f.to}`);
  if (f.kind) parts.push(KIND_WORD[f.kind]);
  if (f.state) parts.push(HISTORY_STATE[f.state][0]);
  if (f.person) parts.push(`by ${people.find((p) => p.id === f.person)?.name ?? "one person"}`);
  if (f.office) parts.push(`office ${f.office}`);
  if (f.session) parts.push(`session ${f.session}`);
  if (f.q?.trim()) parts.push(`"${f.q.trim()}"`);
  return parts.length ? parts.join(" · ") : "Every upload";
}

const num = (v: Num | undefined): number => {
  const x = Number(v ?? 0);
  return Number.isFinite(x) ? Math.round(x * 100) / 100 : 0;
};

/** a moment as Lagos reads it: "16 Oct 2026, 16:21" */
export function when(iso: string | null | undefined): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleString("en-GB", { timeZone: "Africa/Lagos", day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", hourCycle: "h23" });
}

/** what was skipped: already on record, no such student, nothing to settle (null when the upload cannot say) */
export function skipped(r: Pick<HistoryRow, "already" | "no_student" | "no_due">): number | null {
  if (r.already == null && r.no_student == null && r.no_due == null) return null;
  return (r.already ?? 0) + (r.no_student ?? 0) + (r.no_due ?? 0);
}

/** the upload's progress in rows: "12,000 of 40,000 rows" while loading, else the rows of the file (or read) */
export function rowsWord(r: Pick<HistoryRow, "kind" | "state" | "file_rows" | "rows_read">): string {
  if (r.kind === "RESET") return "—";
  if ((r.state === "LOADING" || r.state === "STOPPED") && r.file_rows != null) return `${(r.rows_read ?? 0).toLocaleString()} of ${r.file_rows.toLocaleString()}`;
  const v = r.file_rows ?? r.rows_read;
  return v == null ? "—" : v.toLocaleString();
}

export const HISTORY_HEADERS = ["Upload", "Began (Lagos)", "Ended (Lagos)", "How", "State", "File", "By", "Office", "Parts", "Rows in the file",
  "Rows read", "Payments recorded", "Already on record", "No such student", "Nothing to settle", "Added beside another", "Taken over",
  "Corrected", "No usable date", "Payments deleted", "Students", "Sessions", "Amount stated in the file (₦)", "Amount recorded or deleted (₦)",
  "Decided by", "Decided", "Note"];

/** one upload as a row of the Excel list (S/N added by the list) */
export function historyRow(r: HistoryRow): (string | number)[] {
  const opt = (v: number | null) => (v == null ? "" : v);
  return [r.ref, when(r.at), when(r.finished_at), `${KIND_WORD[r.kind]}${r.rebuilt ? " (rebuilt from the records)" : ""}`, HISTORY_STATE[r.state]?.[0] ?? r.state,
    r.file_name ?? "", r.by_name ?? "", r.office ?? "", r.parts, opt(r.file_rows), opt(r.rows_read), r.kind === "RESET" ? "" : r.recorded,
    opt(r.already), opt(r.no_student), opt(r.no_due), opt(r.separate), opt(r.taken_over), opt(r.corrected), opt(r.undated),
    r.kind === "RESET" ? r.deleted : "", r.students, r.sessions ?? "", r.file_amount == null ? "" : num(r.file_amount),
    r.amount == null ? "" : num(r.amount), r.decided_by_name ?? "", when(r.decided_at) === "—" ? "" : when(r.decided_at), r.note ?? ""];
}

/** a part of an upload as it was loaded (or a batch of a start over) */
export interface HistoryPart {
  seq: number; from_row: number | null; at?: string; rows_read: number | null; recorded?: number; duplicates?: number | null;
  matched?: number | null; no_student?: number | null; no_due?: number | null; separate?: number | null; taken_over?: number | null;
  corrected?: number | null; undated?: number | null; deleted?: number; amount?: Num; resent?: number; duplicate_sample?: string | null;
}

/** the rows a part covered: "Rows 1–500" (a part of the old door, or a rebuilt one, covers rows it cannot name) */
export function partRows(p: Pick<HistoryPart, "from_row" | "rows_read">): string {
  if (p.from_row == null || p.rows_read == null) return "—";
  return `${(p.from_row + 1).toLocaleString()}–${(p.from_row + p.rows_read).toLocaleString()}`;
}

/** a payment an upload recorded or a start over deleted */
export interface HistoryPayment {
  part: number; at: string; number: string | null; name: string | null; session: string; purpose: string; amount: Num; paid_on: string | null;
  reference: string; receipt_no: string | null; payref: string | null;
}

export const PAYMENT_HEADERS = ["Part", "Matric/admission no.", "Name", "Session", "Purpose", "Amount (₦)", "Paid on", "Reference", "Receipt", "Old portal's payment number"];

export function paymentRow(p: HistoryPayment): (string | number)[] {
  return [p.part, p.number ?? "", p.name ?? "", p.session, p.purpose, num(p.amount), p.paid_on ? p.paid_on.slice(0, 10) : "", p.reference, p.receipt_no ?? "", p.payref ?? ""];
}

/** what a file states, read before it is loaded: its rows, the students (by the number given), the sessions and the amount (a blank
 *  amount is "cleared in full" and adds nothing) — as V607's tally reads an upload for approval */
export function fileTally(rows: { matric?: string; session?: string; amount?: string | number | null }[]): { rows: number; students: number; sessions: string; amount: number } {
  const students = new Set<string>();
  const sessions = new Set<string>();
  let amount = 0;
  for (const r of rows) {
    const m = String(r.matric ?? "").trim().toUpperCase();
    if (m) students.add(m);
    const s = String(r.session ?? "").trim();
    if (s) sessions.add(s);
    const a = String(r.amount ?? "").replace(/[^0-9.]/g, "");
    if (/^[0-9]+(\.[0-9]+)?$/.test(a)) amount += Number(a);
  }
  return { rows: rows.length, students: students.size, sessions: [...sessions].sort().join(", "), amount: Math.round(amount * 100) / 100 };
}
