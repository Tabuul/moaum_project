/** A course structure read from a CCMAS document's tables: the columns found by their headings — Course Code, Title, Units,
 *  Status, LH, PH — in whatever order the document puts them, a leading S/N column passed over, and a table that continues one
 *  on the next page (no heading of its own) read with the columns of the table before it. Level and semester come from the
 *  document's own headings ("100 Level", "First Semester"). A table with no heading anywhere is read in the order the
 *  template uses, a leading serial number passed over. */
import type { DocxBlock } from "./docx.ts";

export interface StructureDocRow { code: string; title: string; units: string; status: string; level: number | null; semester: number | null; lh: string; ph: string }
interface Columns { code: number; title: number; units: number; status: number; lh: number; ph: number }

const norm = (s: string) => s.replace(/\s+/g, " ").trim().toLowerCase();
const at = (cells: string[], test: (h: string) => boolean) => cells.findIndex((c) => test(norm(c)));

/** a course code as departments write them: CSC 201, GST111, BSU-SOC-101, MOAU-CHM 101 */
export function looksLikeCode(s: string): boolean {
  return /^[a-z]{2,5}(?:[- ][a-z]{2,5})?[- ]?\d{3}[a-z]?$/i.test(s.trim().replace(/\s+/g, " "));
}

/** the columns of a heading row, or null when the row is not one */
export function columnsOf(row: string[]): Columns | null {
  const code = at(row, (h) => /course\s*code|^code$|^course\s*no/.test(h));
  const title = at(row, (h) => /title/.test(h) || h === "course");
  if (code < 0 || title < 0) return null;
  return {
    code, title,
    units: at(row, (h) => /unit|credit|^cu$|^cr$/.test(h)),
    status: at(row, (h) => /status|^type$|classification/.test(h)),
    lh: at(row, (h) => /^lh$|lecture/.test(h)),
    ph: at(row, (h) => /^ph$|practical/.test(h)),
  };
}

/** the template's order, after a leading serial number when the row carries one */
function positional(row: string[]): Columns {
  const sn = /^\d{1,3}\.?$/.test((row[0] ?? "").trim()) && looksLikeCode(row[1] ?? "") ? 1 : 0;
  return { code: sn, title: sn + 1, units: sn + 2, status: sn + 3, lh: sn + 4, ph: sn + 5 };
}

export function structureRowsFromDocx(blocks: DocxBlock[]): StructureDocRow[] {
  const rows: StructureDocRow[] = [];
  let level: number | null = null;
  let semester: number | null = null;
  let cols: Columns | null = null;   // the last heading seen: a table that runs on to the next page has none of its own
  for (const b of blocks) {
    if (b.kind === "p") {
      const lm = b.text.match(/(\d{3})\s*level/i);
      if (lm) level = Number(lm[1]);
      if (/first|1st/i.test(b.text) && /semester/i.test(b.text)) semester = 1;
      else if (/second|2nd/i.test(b.text) && /semester/i.test(b.text)) semester = 2;
      else if (/third|3rd/i.test(b.text) && /semester/i.test(b.text)) semester = 3;
      continue;
    }
    for (const r of b.rows) {
      const head = columnsOf(r);
      if (head) { cols = head; continue; }
      const c = cols ?? positional(r);
      const cell = (i: number) => (i >= 0 ? (r[i] ?? "").trim() : "");
      const code = cell(c.code);
      if (!code || /^course\s*code$/i.test(code) || /^total/i.test(code) || /^total/i.test(cell(c.title))) continue;
      rows.push({ code, title: cell(c.title), units: cell(c.units), status: cell(c.status), level, semester, lh: cell(c.lh), ph: cell(c.ph) });
    }
  }
  return rows;
}
