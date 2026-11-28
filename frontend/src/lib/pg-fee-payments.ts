/**
 * Application fee payments of PG applicants, uploaded in the Bursary's Old Fees History layout (V786): Matriculation Number
 * (here the applicant's PG application number, PG/YY/NNNNNN, or the number the old portal gave it), Session, Semester, Level,
 * Amount, Purpose/Payment Item (PG APPLICATION), Payment Date, Channel, Reference. The rows are read by the Old Fees History
 * reader (lib/legacy-fees.ts), each kept with its row of the sheet, checked on the server without writing anything, and then
 * uploaded; this file carries the rows and the words for what the check and the upload say of each one. The rules are the server's.
 */
import { legacyFeeColumns, legacyFeeRows, type LegacyFeeRow } from "./legacy-fees.ts";

/** a row as the server takes it: what the Old Fees History reader reads, and the row of the sheet it came from */
export type PgFeeApiRow = LegacyFeeRow & { row: number };

/** the sheet's payments, and the rows of the sheet the reader did not take (something written, but no number or no session) */
export interface PgFeeRead { rows: PgFeeApiRow[]; left: number[] }

/** what the server says of a row: recorded (CLEARED, HELD, ALREADY) or refused (the rest) */
export interface PgFeeLine {
  rowNo: number; number: string; applicationNo: string | null; name: string | null; reference: string; amount: number | null;
  result: string; reason: string | null; note: string | null;
}
export interface PgFeeReport {
  applied: boolean; batchId: string | null; batchReference: string | null; fileName: string;
  rows: number; cleared: number; held: number; already: number; refused: number; results: PgFeeLine[];
}

export type PgFeeKind = "ok" | "info" | "warn" | "bad" | "grey";

/** the most payments one file holds: what the route takes in one request (PgMigrationController.PaymentsIn) */
export const PG_FEE_MAX_ROWS = 2000;

/** the sheet that carries the payments: the first whose header has a matriculation-number column and a session column, as the Old
 *  Fees History upload finds it; none when no sheet has them */
export function pgFeeSheet<T extends { rows: string[][] }>(sheets: T[]): T | null {
  return sheets.find((sh) => { const c = legacyFeeColumns(sh.rows[0] ?? []); return c.matric >= 0 && c.session >= 0; }) ?? null;
}

/** the payments of a sheet read as a grid (the header in the first row), one at a time through the Old Fees History reader, each
 *  with its row of the sheet — the grid is read with each row at its own place (xlsxWorkbook's rowNumbers), so index + 1 is the row
 *  the officer sees. A row with no number is left out; one that has something written but is not read (no number, or a session
 *  not written YYYY/YYYY) is named in `left`; a blank row is neither. */
export function pgFeePaymentRows(grid: unknown[][]): PgFeeRead {
  const header = grid[0] ?? [];
  const rows: PgFeeApiRow[] = [];
  const left: number[] = [];
  for (let i = 1; i < grid.length; i++) {
    const cells = grid[i] ?? [];
    const read = legacyFeeRows([header, cells]).rows[0];
    if (read && read.matric.trim()) rows.push({ ...read, row: i + 1 });
    else if (cells.some((c) => String(c ?? "").trim() !== "")) left.push(i + 1);
  }
  return { rows, left };
}

/** the words for what a row will do (a check) and what it did (an upload), and the pill that carries them */
export const PG_FEE_RESULT: Record<string, { check: string; done: string; kind: PgFeeKind }> = {
  CLEARED: { check: "Clears", done: "Cleared", kind: "ok" },
  HELD: { check: "Held for an officer", done: "Held", kind: "warn" },
  ALREADY: { check: "Already recorded", done: "Already recorded", kind: "grey" },
  NOT_APPLICATION_FEE: { check: "Not an application fee", done: "Not an application fee", kind: "bad" },
  NO_REFERENCE: { check: "No reference", done: "No reference", kind: "bad" },
  NO_AMOUNT: { check: "No amount", done: "No amount", kind: "bad" },
  NOT_FOUND: { check: "Number not found", done: "Number not found", kind: "bad" },
  IS_STUDENT: { check: "A student's number", done: "A student's number", kind: "bad" },
  CONFLICT: { check: "Reference used for another applicant", done: "Reference used for another applicant", kind: "bad" },
  REJECTED: { check: "Rejected before", done: "Rejected before", kind: "bad" },
};

/** a row's result in words and the pill's kind: future for a check (applied false), past for an upload; a result not listed is shown as it came */
export function pgFeeWord(result: string, applied: boolean): [string, PgFeeKind] {
  const w = PG_FEE_RESULT[result];
  return w ? [applied ? w.done : w.check, w.kind] : [result, "grey"];
}

const count = (n: number) => n.toLocaleString("en-GB");

/** the report in one line: the rows, how many clear, are held, were recorded already, and are refused */
export function pgFeeSummary(r: Pick<PgFeeReport, "applied" | "rows" | "cleared" | "held" | "already" | "refused">): string {
  const a = r.applied;
  return `${count(r.rows)} ${r.rows === 1 ? "row" : "rows"}: ${count(r.cleared)} ${a ? "cleared" : "will clear"}, ${count(r.held)} ${a ? "held" : "will be held"}, `
    + `${count(r.already)} already recorded, ${count(r.refused)} refused`;
}

/** may this checked file be uploaded: it was checked, not uploaded, and at least one row clears or is held */
export function pgFeeMayUpload(r: Pick<PgFeeReport, "applied" | "cleared" | "held"> | null): boolean {
  return !!r && !r.applied && r.cleared + r.held > 0;
}

/** the rows of the sheet the reader did not take, in words (the first few named) */
export function pgFeeLeftWords(left: number[]): string {
  if (!left.length) return "";
  const shown = left.slice(0, 10).join(", ");
  return `${count(left.length)} ${left.length === 1 ? "row" : "rows"} of the sheet ${left.length === 1 ? "was" : "were"} left out for having no application number or no session written like 2026/2027: `
    + `sheet ${left.length === 1 ? "row" : "rows"} ${shown}${left.length > 10 ? ", and more" : ""}.`;
}
