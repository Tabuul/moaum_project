/** V545: a bank statement read from the bank's CSV or Excel file — the header row found, the columns named (date, description,
 *  reference, debit, credit, or one amount column with a sign), each line's date and amounts read as banks write them — for the
 *  database to match each debit to what was paid out. Node-tested. */

/** one line as it is sent */
export interface StatementLine { date: string; description: string; reference: string; debit: string; credit: string }

export interface StatementRead { lines: StatementLine[]; header: string[]; columns: Record<string, number>; skipped: number; problem: string | null }

const norm = (s: string) => s.toLowerCase().replace(/[^a-z]/g, "");
const HEADS: Record<string, string[]> = {
  date: ["valuedate", "transdate", "transactiondate", "date", "postingdate", "tradate", "txndate"],
  description: ["description", "narration", "details", "remarks", "particulars", "transactiondetails", "narrative"],
  reference: ["reference", "ref", "referenceno", "chequeno", "chqno", "transactionref", "transref", "refno", "sessionid"],
  debit: ["debit", "debits", "withdrawal", "withdrawals", "dr", "debitamount", "moneyout", "paidout"],
  credit: ["credit", "credits", "deposit", "deposits", "cr", "creditamount", "moneyin", "paidin"],
  amount: ["amount", "transactionamount"],
};

/** the column of each kind in a header row, or -1 */
function columnsOf(row: string[]): Record<string, number> {
  const cells = row.map((c) => norm(c ?? ""));
  const out: Record<string, number> = {};
  for (const [k, names] of Object.entries(HEADS)) {
    out[k] = cells.findIndex((c) => names.includes(c));
  }
  if (out.date < 0) out.date = cells.findIndex((c) => c.includes("date"));
  return out;
}

const MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
const pad = (n: number) => String(n).padStart(2, "0");

/** a date as banks write it — 17/10/2026, 17-10-2026, 17-Oct-2026, 17 Oct 2026, 2026-10-17, or an Excel day number — as YYYY-MM-DD */
export function readDate(v: string): string {
  const s = (v ?? "").trim();
  if (!s) return "";
  let m = s.match(/^(\d{4})-(\d{1,2})-(\d{1,2})/);
  if (m) return `${m[1]}-${pad(+m[2])}-${pad(+m[3])}`;
  m = s.match(/^(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})/);
  if (m) { const y = m[3].length === 2 ? 2000 + +m[3] : +m[3]; return `${y}-${pad(+m[2])}-${pad(+m[1])}`; }
  m = s.match(/^(\d{1,2})[\s/-]([A-Za-z]{3})[A-Za-z]*[\s/-](\d{2,4})/);
  if (m) { const mi = MONTHS.indexOf(m[2].toLowerCase()); const y = m[3].length === 2 ? 2000 + +m[3] : +m[3]; if (mi >= 0) return `${y}-${pad(mi + 1)}-${pad(+m[1])}`; }
  if (/^\d{5}(\.\d+)?$/.test(s)) {
    const d = new Date(Date.UTC(1899, 11, 30) + Math.floor(Number(s)) * 86400000);
    return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
  }
  return "";
}

/** an amount as banks write it — 1,250.00, (1,250.00), -1250, NGN 1,250 — as a plain number string, its sign kept */
export function readAmount(v: string): string {
  const s = (v ?? "").trim();
  if (!s) return "";
  const negative = /^\(.*\)$/.test(s) || /^-/.test(s.replace(/[^0-9.\-()]/g, "")) || /\bdr\b/i.test(s);
  const digits = s.replace(/[^0-9.]/g, "");
  if (!digits || isNaN(Number(digits))) return "";
  return (negative ? "-" : "") + String(Math.round(Number(digits) * 100) / 100);
}

/** the statement's lines from its rows: the header is the first row naming a date and a debit (or an amount) column */
export function readStatement(rows: string[][]): StatementRead {
  const hi = rows.slice(0, 40).findIndex((r) => { const c = columnsOf(r); return c.date >= 0 && (c.debit >= 0 || c.amount >= 0); });
  if (hi < 0) return { lines: [], header: [], columns: {}, skipped: 0, problem: "No header row naming a date and a debit (or amount) column was found in the first 40 rows." };
  const columns = columnsOf(rows[hi]);
  const lines: StatementLine[] = [];
  let skipped = 0;
  for (const r of rows.slice(hi + 1)) {
    const cell = (k: string) => (columns[k] >= 0 ? String(r[columns[k]] ?? "").trim() : "");
    const date = readDate(cell("date"));
    let debit = readAmount(cell("debit"));
    let credit = readAmount(cell("credit"));
    if (columns.debit < 0 && columns.amount >= 0) {
      // one signed amount: money out is negative
      const a = readAmount(cell("amount"));
      if (a.startsWith("-")) debit = a.slice(1); else credit = a;
    }
    debit = debit.replace(/^-/, ""); credit = credit.replace(/^-/, "");
    if (!date || (!(Number(debit) > 0) && !(Number(credit) > 0))) { if (r.some((c) => String(c ?? "").trim())) skipped++; continue; }
    lines.push({ date, description: cell("description").slice(0, 500), reference: cell("reference").slice(0, 200), debit: Number(debit) > 0 ? debit : "", credit: Number(credit) > 0 ? credit : "" });
  }
  return { lines, header: rows[hi], columns, skipped, problem: lines.length ? null : "The file has a header but no dated line with a debit or a credit." };
}
