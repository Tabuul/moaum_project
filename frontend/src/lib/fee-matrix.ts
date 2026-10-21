/**
 * Reading an approved fees workbook into the rows the structure upload takes (V535).
 *
 * Three layouts are read:
 *  - one row per fee: Faculty (or Programme), Level, Entry mode, Semester, Indigene, Amount;
 *  - the faculty cross-tab: a FACULTY/SEMESTER header with a column pair per level, then a block per faculty with
 *    1st and 2nd Semester rows;
 *  - the block layout the College of Health Sciences sends: a block per programme (or faculty) whose title row names
 *    it ("MBBS", "NURSING", "RADIOGRAPHY SCIENCES") beside its level bands ("100L/200DE", "200L", "600L/SP"), an
 *    Indigenes / Non-Indigene row, then 1ST, 2ND and TOTAL rows. The block's title is matched to a programme or a
 *    faculty on the register (suggestTarget), and the Bursary confirms or changes the match before anything is read.
 *
 * Entry modes are stated on every line, as the 2025/2026 structure states them, so no line reaches a student twice: a
 * "100L/200DE" band is level 100 for UTME and Transfer and level 200 for Direct Entry; a 200L band is UTME and Transfer
 * when the block has a Direct Entry band (else all three); a band from 300 up is all three; "/SP" also gives the
 * spillover line (no level, no entry mode). A CCE structure is entry mode CCE throughout. V613: a band naming a spillover year —
 * "400L/SP1", "400 Level (SP1)" — is that year's spillover line alone, at the programme's final level the band names; the
 * Spillover column of the row layout likewise reads "SP1", "SP2", "SP3".
 */
export type Cell = string | number | null | undefined;
export type Grid = Cell[][];

const norm = (v: Cell) => String(v ?? "").replace(/\s+/g, " ").trim();
const num = (v: Cell): number | null => {
  if (typeof v === "number") return Number.isFinite(v) ? v : null;
  const s = norm(v).replace(/[^0-9.]/g, "");
  return s && Number.isFinite(Number(s)) ? Number(s) : null;
};
/** to the kobo, half up */
export const kobo = (n: number) => Math.round((n + Number.EPSILON) * 100) / 100;

export type Indigene = "INDIGENE" | "NON_INDIGENE";
/** a row as the structure upload takes it */
export interface StructureRow {
  faculty?: string; programmeCode?: string; level?: string; entryMode?: string; semester?: string; indigene?: string;
  spillover?: string; amount: string; item?: string; kind?: string; feeGroup?: string; ord?: string;
  /** V613: the spillover year a spillover row is for (1–3) */
  spillYear?: string;
}

/** a level band of a block or a cross-tab header: "100L/200DE" → level 100 and Direct Entry at 200; "600L/SP" → spillover too */
export interface Band { col: number; head: string; level: number | null; de: number | null; spill: boolean; spillYear: number | null }

export function readBand(head: string, col: number): Band | null {
  const h = norm(head).toUpperCase();
  if (!h || (/^[\d.,\s₦]+$/.test(h) && !/^\d{3}$/.test(h))) return null; // an amount, not a level
  const nums = h.match(/(?<!\d)\d{3}(?!\d)/g) ?? [];
  /* V613: "SP1", "SP 2", "(SP3)" — the spillover year; "SP" or "SPILLOVER" alone is any year */
  const year = h.match(/(?:^|[/\s(])SP\s*([1-3])\b/);
  const spill = year !== null || /SPILL|(^|[/\s(])SP\b/.test(h);
  if (!nums.length && !spill) return null;
  const level = nums.length ? Number(nums[0]) : null;
  if (level !== null && (level < 100 || level > 900 || level % 100 !== 0)) return null;
  const de = /DE\b|DIRECT/.test(h) && nums[1] ? Number(nums[1]) : null;
  return { col, head: norm(head), level, de, spill, spillYear: year ? Number(year[1]) : null };
}

/** the (level, entry mode) pairs a band's amount is stated for */
export type BandLine = { level: number | null; entryMode: string | null; spillover: boolean; spillYear: number | null };

export function bandLines(b: Band, blockHasDe: boolean, cce = false): BandLine[] {
  const out: BandLine[] = [];
  /* V613: a band naming a spillover year is that year's spillover line alone, at the programme's final level the band names */
  if (b.spillYear) return [{ level: b.level, entryMode: cce ? "CCE" : null, spillover: true, spillYear: b.spillYear }];
  if (b.level !== null) {
    if (cce) out.push({ level: b.level, entryMode: "CCE", spillover: false, spillYear: null });
    else if (b.de !== null) out.push({ level: b.level, entryMode: "UTME", spillover: false, spillYear: null }, { level: b.level, entryMode: "TRANSFER", spillover: false, spillYear: null },
      { level: b.de, entryMode: "DIRECT_ENTRY", spillover: false, spillYear: null });
    else if (b.level === 100 || (b.level === 200 && blockHasDe)) out.push({ level: b.level, entryMode: "UTME", spillover: false, spillYear: null }, { level: b.level, entryMode: "TRANSFER", spillover: false, spillYear: null });
    else for (const m of ["UTME", "TRANSFER", "DIRECT_ENTRY"]) out.push({ level: b.level, entryMode: m, spillover: false, spillYear: null });
  }
  if (b.spill) out.push({ level: null, entryMode: cce ? "CCE" : null, spillover: true, spillYear: null });
  return out;
}

const semOf = (s: string): number | null => (/^(1st|first)\b|1st sem|first sem/i.test(s) ? 1 : /^(2nd|second)\b|2nd sem|second sem/i.test(s) ? 2 : /^(3rd|third)\b|3rd sem|third sem/i.test(s) ? 3 : null);
const isTotal = (s: string) => /^total\b|^session total|^annual/i.test(s);

/** a semester cell read against its TOTAL, where the sheet gives one: the two semesters made to add up to the TOTAL to the kobo
 *  (the first semester by the sheet's own share, the second the rest). A sheet whose 1ST and 2ND do not make its TOTAL is told. */
export interface Mismatch { label: string; band: string; indigene: Indigene; first: number; second: number; total: number; used: [number, number] }

function settle(first: number | null, second: number | null, total: number | null): { amounts: Map<number, number>; mismatch: [number, number] | null } {
  const amounts = new Map<number, number>();
  if (total !== null && total > 0) {
    const t = kobo(total);
    if (first !== null && second !== null && first + second > 0) {
      const off = Math.abs(first + second - total) > 1;
      const f = off ? kobo(t * (first / (first + second))) : kobo(first);
      amounts.set(1, f).set(2, kobo(t - f));
      return { amounts, mismatch: off ? [f, kobo(t - f)] : null };
    }
    if (first === null && second === null) { amounts.set(0, t); return { amounts, mismatch: null }; } // the session as one line
  }
  if (first !== null && first > 0) amounts.set(1, kobo(first));
  if (second !== null && second > 0) amounts.set(2, kobo(second));
  return { amounts, mismatch: null };
}

/** one block of the block layout, its lines read but not yet charged to a programme or faculty */
export interface BlockLine { level: number | null; entryMode: string | null; semester: number | null; indigene: Indigene; amount: number; spillover: boolean; spillYear: number | null }
export interface FeeBlock { label: string; row: number; bands: Band[]; lines: BlockLine[] }

const NOT_A_BLOCK = /^(semester|faculty|programme|level|indigene|non|₦|n$|total|prepared|authori[sz]ed|approved|signed)/i;

/** the block layout: each row whose first cell names something and whose other cells are level bands starts a block */
export function readFeeBlocks(grid: Grid, cce = false): { blocks: FeeBlock[]; mismatches: Mismatch[] } {
  const blocks: FeeBlock[] = [];
  const mismatches: Mismatch[] = [];
  const titleAt = (r: Cell[] | undefined): { label: string; bands: Band[] } | null => {
    if (!r) return null;
    const label = norm(r[0]);
    if (!label || NOT_A_BLOCK.test(label) || semOf(label) !== null) return null;
    const bands = r.slice(1).map((c, i) => (typeof c === "number" ? null : readBand(norm(c), i + 1))).filter((b): b is Band => b !== null);
    return bands.length ? { label, bands } : null;
  };
  for (let i = 0; i < grid.length; i++) {
    const t = titleAt(grid[i]);
    if (!t) continue;
    // the Indigene / Non-indigene row under the title says which column of each band is which
    const ind = new Map<number, Indigene>();
    for (let k = i + 1; k <= i + 3 && k < grid.length; k++) {
      const r = grid[k] ?? [];
      if (r.some((c) => /indigen/i.test(norm(c)))) {
        r.forEach((c, j) => { const s = norm(c); if (/non/i.test(s)) ind.set(j, "NON_INDIGENE"); else if (/indigen/i.test(s)) ind.set(j, "INDIGENE"); });
        break;
      }
    }
    // the semester rows, up to the next block
    const rows: { sem: number | null; total: boolean; r: Cell[] }[] = [];
    let j = i + 1;
    for (; j < grid.length && j <= i + 12; j++) {
      if (titleAt(grid[j])) break;
      const a = norm(grid[j]?.[0]);
      const sem = semOf(a);
      if (sem !== null) rows.push({ sem, total: false, r: grid[j] ?? [] });
      else if (isTotal(a)) { rows.push({ sem: null, total: true, r: grid[j] ?? [] }); break; }
    }
    if (!rows.length) continue;
    const hasDe = t.bands.some((b) => b.de !== null);
    const lines: BlockLine[] = [];
    t.bands.forEach((b, n) => {
      const end = n + 1 < t.bands.length ? t.bands[n + 1].col : b.col + 2;
      const cols: [number, Indigene][] = [];
      for (let c = b.col; c < end; c++) { const k = ind.get(c); if (k) cols.push([c, k]); }
      if (!cols.length) cols.push([b.col, "INDIGENE"], [b.col + 1, "NON_INDIGENE"]);
      for (const [c, indigene] of cols) {
        const at = (sem: number) => { const row = rows.find((x) => x.sem === sem); return row ? num(row.r[c]) : null; };
        const totalRow = rows.find((x) => x.total);
        const total = totalRow ? num(totalRow.r[c]) : null;
        const { amounts, mismatch } = settle(at(1), at(2), total);
        const third = at(3);
        if (third !== null && third > 0) amounts.set(3, kobo(third));
        if (mismatch) mismatches.push({ label: t.label, band: b.head, indigene, first: at(1) ?? 0, second: at(2) ?? 0, total: total ?? 0, used: mismatch });
        for (const [sem, amount] of [...amounts.entries()].sort((x, y) => x[0] - y[0])) {
          if (!(amount > 0)) continue;
          for (const l of bandLines(b, hasDe, cce)) lines.push({ ...l, semester: sem || null, indigene, amount });
        }
      }
    });
    if (lines.length) blocks.push({ label: t.label, row: i, bands: t.bands, lines });
    i = j - 1;
  }
  return { blocks, mismatches };
}

/** a block's lines as the upload's rows, charged to the programme or faculty it was matched to */
export function blockRows(block: FeeBlock, target: { programmeCode?: string; faculty?: string }): StructureRow[] {
  return block.lines.map((l) => {
    const row: StructureRow = { amount: l.amount.toFixed(2), indigene: l.indigene };
    if (target.programmeCode) row.programmeCode = target.programmeCode;
    else if (target.faculty) row.faculty = target.faculty;
    if (l.level !== null) row.level = String(l.level);
    if (l.entryMode) row.entryMode = l.entryMode;
    if (l.semester !== null) row.semester = String(l.semester);
    if (l.spillover) { row.spillover = "true"; if (l.spillYear) row.spillYear = String(l.spillYear); }
    return row;
  });
}

/* ── matching a block's title to the register ─────────────────────────────────────────────────────── */

export interface Target { kind: "PROGRAMME" | "FACULTY"; code: string; name: string; faculty_code?: string | null }
const STOP = new Set(["OF", "AND", "THE", "IN", "FOR", "B", "BSC", "BACHELOR", "FACULTY", "DEPARTMENT", "DEPT", "HONS", "COLLEGE"]);
const words = (s: string) => s.toUpperCase().replace(/[^A-Z]+/g, " ").split(" ").filter((w) => w && !STOP.has(w));
const meets = (a: string, b: string) => a.length >= 2 && b.length >= 2 && (a.startsWith(b) || b.startsWith(a)); // "SC" for SCIENCE, "LAB" for LABORATORY

/** how well a title names a target: the share of its words the target's name holds (a word may be the start of the other —
 *  "BIOCHEM" for BIOCHEMISTRY, "LAB" for LABORATORY), with a little for the target's own words matched */
export function matchScore(label: string, name: string): number {
  const lw = words(label), nw = words(name);
  if (!lw.length || !nw.length) return 0;
  if (lw.join(" ") === nw.join(" ")) return 2;
  const hit = lw.filter((w) => nw.some((n) => meets(w, n))).length;
  const back = nw.filter((n) => lw.some((w) => meets(w, n))).length;
  if (!hit || !lw.some((w) => w.length >= 3 && nw.some((n) => meets(w, n)))) return 0;
  return hit / lw.length + 0.1 * (back / nw.length);
}

/** the programme or faculty a block's title most likely names, or null when nothing names it well enough; where two are as
 *  likely, the one in the faculty most of the sheet's other blocks fall in (the College's Biochemistry, not Science's) */
export function suggestTargets(labels: string[], targets: Target[]): (Target | null)[] {
  const ranked = labels.map((label) => targets.map((t) => ({ t, s: matchScore(label, t.name) + (t.kind === "PROGRAMME" && words(label).join(" ") === words(t.code).join(" ") ? 2 : 0) }))
    .filter((x) => x.s >= 0.6).sort((a, b) => b.s - a.s));
  const sure = ranked.map((r) => (r.length && (r.length === 1 || r[0].s - r[1].s > 0.05) ? r[0].t : null));
  const facs = new Map<string, number>();
  for (const t of sure) { const f = t?.kind === "PROGRAMME" ? t.faculty_code : t?.code; if (f) facs.set(f, (facs.get(f) ?? 0) + 1); }
  const home = [...facs.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? null;
  return ranked.map((r, i) => {
    if (sure[i]) return sure[i];
    if (!r.length) return null;
    const top = r.filter((x) => r[0].s - x.s <= 0.05);
    return (home && top.find((x) => (x.t.kind === "PROGRAMME" ? x.t.faculty_code : x.t.code) === home)?.t) || top[0].t;
  });
}

/* ── the two layouts read before the block layout ─────────────────────────────────────────────────── */

/** True when the sheet is a plain one-row-per-fee table (a Faculty column and an Amount column), not a cross-tab. */
export function looksFlat(grid: Grid): boolean {
  return grid.some((r) => {
    const cs = r.map((c) => norm(c).toLowerCase());
    return cs.some((c) => /facult|programme/.test(c) && !c.includes("/")) && cs.some((c) => /(^|\s)amount\b|^fees?$/.test(c));
  });
}

/** Parse a one-row-per-fee sheet. Each row is a single fee line: Faculty, Level, Entry mode, Semester, Indigene, Amount (Item /
 *  Spillover / Programme / Kind / Fee group / Order optional). Raw values pass straight to the importer, which normalises them;
 *  only the entry mode is canonicalised here so "Direct Entry"/"DE" reach it as DIRECT_ENTRY. */
export function parseFeeFlat(grid: Grid, cce = false): StructureRow[] {
  const hIdx = grid.findIndex((r) => {
    const cs = r.map((c) => norm(c).toLowerCase());
    return cs.some((c) => /facult|programme/.test(c) && !c.includes("/semester")) && cs.some((c) => /(^|\s)amount\b|^fees?$/.test(c));
  });
  if (hIdx < 0) return [];
  const H = grid[hIdx].map((c) => norm(c).toLowerCase());
  const find = (re: RegExp) => H.findIndex((c) => re.test(c));
  const col = {
    facultyCode: find(/faculty code/), faculty: find(/^facult(y|ies)?$|^faculty name$/), facultyAny: find(/facult/), level: find(/level/), mode: find(/entry|mode/),
    semester: find(/semester|(^|\b)sem(\b|$)/), indigene: find(/indigen|origin|state/),
    amount: find(/(^|\s)amount\b|^fees?$/), item: find(/item|descrip|charge|purpose/),
    spill: find(/spill/), programme: find(/programme code|^programme$|^program|course/),
    kind: find(/^kind|fee kind|^type/), group: find(/group/), ord: find(/^ord(er)?$|^order/),
  };
  // the faculty's code where the sheet gives it (the "fees to state" sheet does), else its name
  const facCol = col.facultyCode >= 0 ? col.facultyCode : col.faculty >= 0 ? col.faculty : col.facultyAny;
  const rows: StructureRow[] = [];
  for (let i = hIdx + 1; i < grid.length; i++) {
    const r = grid[i].map(norm);
    const cell = (c: number) => (c >= 0 ? (r[c] ?? "") : "");
    const amt = cell(col.amount).replace(/[^0-9.]/g, "");
    if (!amt || Number(amt) <= 0) continue;
    const fac = cell(facCol);
    const prog = cell(col.programme);
    if (!fac && !prog) continue;
    const row: StructureRow = { amount: amt };
    if (fac) row.faculty = fac;
    if (prog) row.programmeCode = prog;
    if (cell(col.level)) row.level = cell(col.level);
    const m = cce ? "CCE" : col.mode >= 0 ? modeOf(cell(col.mode)) : null;
    if (m) row.entryMode = m;
    if (cell(col.semester)) row.semester = cell(col.semester);
    if (cell(col.indigene)) row.indigene = cell(col.indigene);
    if (cell(col.item)) row.item = cell(col.item);
    /* V613: "SP1", "SP2", "SP3" name the spillover year; Yes, true, spillover: any year */
    const spillCell = cell(col.spill), spillYear = spillCell.match(/\bSP\s*([1-3])\b/i);
    if (spillYear) { row.spillover = "true"; row.spillYear = spillYear[1]; }
    else if (/^(y|t|1|true|yes|spill)/i.test(spillCell)) row.spillover = "true";
    if (cell(col.kind)) row.kind = cell(col.kind);
    if (cell(col.group)) row.feeGroup = cell(col.group);
    if (cell(col.ord)) row.ord = cell(col.ord);
    rows.push(row);
  }
  return rows;
}

export function modeOf(v: string): string | null {
  const s = v.toUpperCase().replace(/[^A-Z]/g, "");
  if (!s) return null;
  if (s === "DE" || s.includes("DIRECT")) return "DIRECT_ENTRY";
  if (s.includes("TRANSFER")) return "TRANSFER";
  if (s === "CCE" || s.includes("CONTINUING") || s.includes("PARTTIME")) return "CCE";
  if (s.includes("UTME")) return "UTME";
  if (s.includes("JUPEB")) return "JUPEB";
  if (s.includes("SANDWICH")) return "SANDWICH";
  if (s.includes("POST") || s === "PG") return "POSTGRADUATE";
  return v.toUpperCase().trim();
}

/** Parse the faculty cross-tab (a FACULTY/SEMESTER header, faculty blocks × 1st/2nd/Total rows × level bands × Indigene /
 *  Non-indigene) into one row per cell, the entry modes stated as the block layout states them. Empty when the sheet has
 *  no FACULTY header. */
export function parseFeeMatrix(grid: Grid, cce = false): StructureRow[] {
  const hIdx = grid.findIndex((r) => r.some((c) => /faculty\s*\/\s*semester|^faculty$/i.test(norm(c))));
  if (hIdx < 0) return [];
  const header = grid[hIdx].map(norm);
  const facCol = header.findIndex((c) => /faculty/i.test(c));
  const bands: Band[] = [];
  for (let c = facCol + 1; c < header.length; c++) { const b = readBand(header[c], c); if (b) bands.push(b); }
  const hasDe = bands.some((b) => b.de !== null);
  const rows: StructureRow[] = [];
  let fac = "";
  for (let i = hIdx + 1; i < grid.length; i++) {
    const r = grid[i].map(norm);
    const c1 = r[facCol];
    if (!c1) continue;
    if (!/semester|total/i.test(c1) && semOf(c1) === null) { fac = c1; continue; } // a faculty name starts a block
    const sem = semOf(c1);
    if (!sem || !fac) continue; // the Total row
    for (const b of bands) {
      for (const [col, indigene] of [[b.col, "INDIGENE"], [b.col + 1, "NON_INDIGENE"]] as const) {
        const n = num(r[col]);
        if (n === null || n <= 0) continue;
        for (const l of bandLines(b, hasDe, cce)) {
          const row: StructureRow = { faculty: fac, semester: String(sem), indigene, amount: kobo(n).toFixed(2) };
          if (l.level !== null) row.level = String(l.level);
          if (l.entryMode) row.entryMode = l.entryMode;
          if (l.spillover) { row.spillover = "true"; if (l.spillYear) row.spillYear = String(l.spillYear); }
          rows.push(row);
        }
      }
    }
  }
  return rows;
}

/** what was read from a workbook: ready rows, or blocks still to be matched to the register */
export type ReadWorkbook =
  | { layout: "FLAT" | "MATRIX"; rows: StructureRow[] }
  | { layout: "BLOCKS"; blocks: FeeBlock[]; mismatches: Mismatch[] }
  | { layout: "NONE" };

export function readFeeWorkbook(sheets: Grid[], cce = false): ReadWorkbook {
  for (const g of sheets) if (looksFlat(g)) { const rows = parseFeeFlat(g, cce); if (rows.length) return { layout: "FLAT", rows }; }
  for (const g of sheets) { const rows = parseFeeMatrix(g, cce); if (rows.length) return { layout: "MATRIX", rows }; }
  const blocks: FeeBlock[] = [];
  const mismatches: Mismatch[] = [];
  for (const g of sheets) { const r = readFeeBlocks(g, cce); blocks.push(...r.blocks); mismatches.push(...r.mismatches); }
  return blocks.length ? { layout: "BLOCKS", blocks, mismatches } : { layout: "NONE" };
}
