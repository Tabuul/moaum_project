/**
 * Writing a workbook the way the reader in xlsx.ts reads one: a zip of a
 * few XML parts, every entry STORED (no compression), so no library is
 * needed in the browser. Enough for JAMB's admission template — sheets of
 * strings and numbers with a heading row, now with column widths, borders,
 * a branded letterhead (school name and title) and the crest as a floating
 * image over the top-left corner. The letterhead sits in the rows the
 * template already reserves above the data, so the data grid — the part
 * JAMB reads — stays exactly where it was.
 */

export type Cell = string | number | null | undefined;

export interface XlsxLogo { png: Uint8Array; w: number; h: number }
export interface XlsxOpts { logo?: XlsxLogo }
/** a drop-down on a range of cells: a list of words, or the cells of another sheet holding the choices ('Lecturers'!$C$2:$C$40) */
export interface ListValidation { sqref: string; list?: string[]; range?: string; prompt?: string }
/** what a sheet may add to its rows: further header rows (0-based indices, styled as the header) and merged ranges ("A8:A9") */
export interface SheetOpts {
  headerRows?: number[]; merges?: string[]; /** 0-based columns whose data cells are centred */ centre?: number[];
  /** drop-downs (V478) */
  validations?: ListValidation[];
  /** 0-based columns hidden from view (an identifier the upload reads, not the person) */
  hiddenCols?: number[];
  /** protect the sheet: every cell locked but those of these 0-based columns, between these 0-based rows (inclusive) */
  protect?: { unlocked: { cols: number[]; fromRow?: number; toRow?: number }[] };
  /** keep the rows above this 0-based row in view as the sheet scrolls (the header) */
  freezeBelow?: number;
  /** the whole sheet hidden (a template's own context, read on upload) */
  hidden?: boolean;
  /** V745: 0-based columns formatted as Text (@) by default, so what is typed into an empty cell of them stays as typed: a date
   *  DD/MM/YYYY is not turned into a month-first Excel date, a number keeps its leading zeros */
  textCols?: number[];
  /** V773: data cells drawn in a colour of their own (not header or section rows); the cell's style replaces the stripe and the
   *  column's centring for that cell */
  fills?: CellFill[];
  /** V773: every header row's cells in these columns: this fill, white bold, centred, wrapped (a block of columns under one colour) */
  headerFills?: HeaderFill[];
  /** V773: a width (in characters) for these 0-based columns, in place of the width read off the data */
  widths?: Record<number, number>;
  /** V773: false draws every data row alike (no zebra: style 2, centred 8). Default true */
  stripe?: boolean;
  /** V773: the columns kept in view as the sheet scrolls sideways */
  freezeCols?: number;
  /** V773: the rows above this 0-based row are the letterhead, in place of the "S/N" search (a sheet whose header row does not
   *  start with S/N: without it the writer would draw no letterhead and paint the title as a section band) */
  letterheadRows?: number;
}
/** V773: one data cell's own look — 0-based row and column of the rows array; fill "RRGGBB"; fmt "0.00" shows a number with two
 *  decimals (Excel's built-in format 2), the value staying a number */
export interface CellFill { r: number; c: number; fill?: string; bold?: boolean; centre?: boolean; fmt?: "0.00" }
/** V773: a block of header columns under one colour — 0-based, inclusive */
export interface HeaderFill { from: number; to: number; fill: string }
export type SheetSpec = [string, Cell[][]] | [string, Cell[][], SheetOpts];

function esc(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

export function colName(i: number): string {
  let n = i + 1;
  let s = "";
  while (n > 0) {
    const r = (n - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    n = Math.floor((n - 1) / 26);
  }
  return s;
}

/** the column-header row is the first row that starts with "SN" or "S/N"; everything
 *  above it is the letterhead, everything below it is data */
const isSn = (v: Cell) => { const t = String(v ?? "").trim().toUpperCase(); return t === "SN" || t === "S/N"; };
function headerRow(rows: Cell[][]): number {
  const i = rows.findIndex((r) => isSn(r[0]));
  return i < 0 ? 0 : i;
}

/** is the cell at this 0-based row and column left editable on a protected sheet? */
function unlockedAt(opts: SheetOpts, r: number, c: number): boolean {
  return !!opts.protect?.unlocked.some((u) => u.cols.includes(c) && r >= (u.fromRow ?? 0) && r <= (u.toRow ?? Number.MAX_SAFE_INTEGER));
}

/** V773: a header cell's own style key (a block's colour) */
const headerKey = (fill: string) => `H|${fill.toUpperCase()}`;
/** V773: a data cell's own style key: its fill (or none), bold, centred, number format */
const dataKey = (f: CellFill) => `D|${f.fill ? f.fill.toUpperCase() : "-"}|${f.bold ? 1 : 0}|${f.centre ? 1 : 0}|${f.fmt === "0.00" ? 2 : 0}`;

/** V773: the styles a workbook's sheets ask for beyond the fixed table, in order of first appearance (each sheet's header fills,
 *  then its cell fills); the i-th is cell style 15 + i */
export function styleExtras(opts: SheetOpts[]): string[] {
  const out: string[] = [];
  const add = (k: string) => { if (!out.includes(k)) out.push(k); };
  for (const o of opts) {
    for (const h of o.headerFills ?? []) add(headerKey(h.fill));
    for (const f of o.fills ?? []) add(dataKey(f));
  }
  return out;
}

export function sheetXml(rows: Cell[][], hasLogo = false, opts: SheetOpts = {}, extras: string[] = styleExtras([opts])): string {
  const extraHeaders = new Set(opts.headerRows ?? []);
  const hiddenCols = new Set(opts.hiddenCols ?? []);
  const textCols = new Set(opts.textCols ?? []);
  const centred = new Set(opts.centre ?? []);
  const stripe = opts.stripe !== false;
  const hdr = opts.letterheadRows ?? Math.min(headerRow(rows), ...(opts.headerRows?.length ? [Math.min(...opts.headerRows)] : []));
  const nCols = rows.reduce((m, r) => Math.max(m, r.length), 0);
  // V773: a cell's own style, and a header block's, by their place in the workbook's extra styles
  const xf = new Map(extras.map((k, i) => [k, 15 + i]));
  const cellStyle = new Map<string, number>();
  for (const f of opts.fills ?? []) { const s = xf.get(dataKey(f)); if (s !== undefined) cellStyle.set(`${f.r},${f.c}`, s); }
  const headerStyle = (c: number): number | undefined => {
    const h = opts.headerFills?.find((x) => c >= x.from && c <= x.to);
    return h ? xf.get(headerKey(h.fill)) : undefined;
  };
  // widths from the data grid only, so a long school name does not blow out a column
  const widths: number[] = [];
  for (let c = 0; c < nCols; c++) {
    let max = 8;
    for (let r = hdr; r < rows.length; r++) { const v = rows[r][c]; const len = v == null ? 0 : Math.max(...String(v).split("\n").map((l) => l.length)); if (len > max) max = len; }
    widths[c] = opts.widths?.[c] ?? Math.min(max + 2, 70);
  }
  // a Text column's own style (14) is the default of every cell of it the sheet does not write: the cells typed into later
  const cols = nCols ? "<cols>" + widths.map((w, i) => `<col min="${i + 1}" max="${i + 1}" width="${w}"${textCols.has(i) ? ' style="14"' : ""} customWidth="1"${hiddenCols.has(i) ? ' hidden="1"' : ""}/>`).join("") + "</cols>" : "";
  const fb = opts.freezeBelow != null && opts.freezeBelow > 0 ? opts.freezeBelow : 0;
  const fc = opts.freezeCols != null && opts.freezeCols > 0 ? opts.freezeCols : 0;
  const pane = fb && fc ? `<pane xSplit="${fc}" ySplit="${fb}" topLeftCell="${colName(fc)}${fb + 1}" activePane="bottomRight" state="frozen"/>`
    : fc ? `<pane xSplit="${fc}" topLeftCell="${colName(fc)}1" activePane="topRight" state="frozen"/>`
    : fb ? `<pane ySplit="${fb}" topLeftCell="A${fb + 1}" activePane="bottomLeft" state="frozen"/>`
    : "";
  const views = pane ? `<sheetViews><sheetView workbookViewId="0">${pane}</sheetView></sheetViews>` : "";
  const out: string[] = [];
  let lh = 0;        // letterhead lines seen: 0 = school name, 1 = title, 2+ = the date/muted line
  let dataIdx = 0;   // data rows seen, for the zebra stripe
  rows.forEach((row, r) => {
    const nonEmpty = row.filter((v) => v !== null && v !== undefined && v !== "").length;
    if (r < hdr) {
      // letterhead: only the non-empty cells, no borders — the school name, the title, then the date
      const cells: string[] = [];
      row.forEach((v, c) => {
        if (v === null || v === undefined || v === "") return;
        const style = lh === 0 ? 3 : lh === 1 ? 4 : 5;
        lh++;
        cells.push(`<c r="${colName(c)}${r + 1}" s="${style}" t="inlineStr"><is><t xml:space="preserve">${esc(String(v))}</t></is></c>`);
      });
      if (cells.length) out.push(`<row r="${r + 1}">${cells.join("")}</row>`);
      return;
    }
    if (nonEmpty === 0) { return; } // a blank spacer row: nothing to draw, and it must not shift the stripe
    // a "SN" row is a column-header (there are several: the summary table, the quota table, the LGA table);
    // a lone non-empty cell below a header is a section title, given a coloured band the width of the grid;
    // every other row is data, striped for the eye and bordered for the grid
    const isHeader = isSn(row[0]) || extraHeaders.has(r);
    const only = nonEmpty === 1 ? row.find((v) => v !== null && v !== undefined && v !== "") : null;
    const isSection = !isHeader && nonEmpty === 1 && typeof only === "string" && !Number.isFinite(Number(only));
    let s: number;
    if (isHeader) { s = 1; }
    else if (isSection) { s = 6; }
    else { s = stripe && dataIdx % 2 !== 0 ? 7 : 2; dataIdx++; }
    const width = isHeader || isSection ? nCols : row.length;
    const cells: string[] = [];
    for (let c = 0; c < width; c++) {
      const v = row[c];
      const ref = `${colName(c)}${r + 1}`;
      const sc0 = !isHeader && !isSection && centred.has(c) ? (s === 7 ? 9 : 8) : s;
      // V478: an editable cell of a protected sheet: the same look, unlocked (styles 10–13 mirror 2, 7, 8, 9)
      const sc1 = opts.protect && !isHeader && !isSection && unlockedAt(opts, r, c) ? ({ 2: 10, 7: 11, 8: 12, 9: 13 } as Record<number, number>)[sc0] ?? sc0 : sc0;
      // V773: a header block's colour, or a data cell's own look
      const sc = (isHeader ? headerStyle(c) : !isSection ? cellStyle.get(`${r},${c}`) : undefined) ?? sc1;
      if (v === null || v === undefined || v === "") { cells.push(`<c r="${ref}" s="${sc}"/>`); continue; }
      if (typeof v === "number" && Number.isFinite(v)) cells.push(`<c r="${ref}" s="${sc}"><v>${v}</v></c>`);
      else cells.push(`<c r="${ref}" s="${sc}" t="inlineStr"><is><t xml:space="preserve">${esc(String(v))}</t></is></c>`);
    }
    if (cells.length) out.push(`<row r="${r + 1}">${cells.join("")}</row>`);
  });
  const drawing = hasLogo ? `<drawing r:id="rId1"/>` : "";
  const merges = opts.merges?.length ? `<mergeCells count="${opts.merges.length}">${opts.merges.map((m) => `<mergeCell ref="${m}"/>`).join("")}</mergeCells>` : "";
  // V478: no password — the protection keeps a slip of the hand off the register's values; the server checks every row whatever
  const protection = opts.protect ? `<sheetProtection sheet="1" objects="1" scenarios="1" formatColumns="0" formatRows="0" autoFilter="0"/>` : "";
  const validations = opts.validations?.length
    ? `<dataValidations count="${opts.validations.length}">${opts.validations.map((v) => {
      const formula = v.range ? esc(v.range) : esc(`"${(v.list ?? []).join(",")}"`);
      const prompt = v.prompt ? ` showInputMessage="1" prompt="${esc(v.prompt.slice(0, 250))}"` : "";
      return `<dataValidation type="list" allowBlank="1" showErrorMessage="1" errorTitle="Not on the list" error="Choose from the list."${prompt} sqref="${v.sqref}"><formula1>${formula}</formula1></dataValidation>`;
    }).join("")}</dataValidations>`
    : "";
  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">${views}${cols}<sheetData>${out.join("")}</sheetData>${protection}${merges}${validations}${drawing}</worksheet>`;
}

// fonts: 0 normal · 1 white-bold (header) · 2 navy-bold-15 (school name) · 3 navy-bold-12 (title)
//        4 grey-10 (date) · 5 white-bold-12 (section band)
// fills:  0 none · 1 gray125 · 2 navy (header) · 3 mid-navy (section band) · 4 pale (zebra)
// borders: 0 none · 1 thin
// cellXfs: 0 normal · 1 header · 2 data · 3 school name · 4 title · 5 date · 6 section band · 7 data zebra · 8 data centred · 9 data zebra centred
//          10–13: 2, 7, 8, 9 unlocked (the cells a protected sheet leaves editable, V478)
//          14: Text (@, built-in numFmtId 49), a Text column's default (V745)
//          15…: V773, the styles a workbook asks for beyond these (stylesXml), appended so no index above moves
export const STYLES_XML =`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="6"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font><font><b/><sz val="15"/><color rgb="FF0E3F55"/><name val="Calibri"/></font><font><b/><sz val="12"/><color rgb="FF0E3F55"/><name val="Calibri"/></font><font><sz val="10"/><color rgb="FF6B7B85"/><name val="Calibri"/></font><font><b/><sz val="12"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts><fills count="5"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF0E3F55"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FF2A6F97"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFEEF3F6"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left style="thin"><color rgb="FFB4C2CC"/></left><right style="thin"><color rgb="FFB4C2CC"/></right><top style="thin"><color rgb="FFB4C2CC"/></top><bottom style="thin"><color rgb="FFB4C2CC"/></bottom><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="15"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf><xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="left" vertical="center"/></xf><xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="left" vertical="center"/></xf><xf numFmtId="0" fontId="4" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="left" vertical="center"/></xf><xf numFmtId="0" fontId="5" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="center"/></xf><xf numFmtId="0" fontId="0" fillId="4" borderId="1" xfId="0" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf><xf numFmtId="0" fontId="0" fillId="4" borderId="1" xfId="0" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1" applyProtection="1"><alignment vertical="center" wrapText="1"/><protection locked="0"/></xf><xf numFmtId="0" fontId="0" fillId="4" borderId="1" xfId="0" applyFill="1" applyBorder="1" applyAlignment="1" applyProtection="1"><alignment vertical="center" wrapText="1"/><protection locked="0"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1" applyProtection="1"><alignment horizontal="center" vertical="center" wrapText="1"/><protection locked="0"/></xf><xf numFmtId="0" fontId="0" fillId="4" borderId="1" xfId="0" applyFill="1" applyBorder="1" applyAlignment="1" applyProtection="1"><alignment horizontal="center" vertical="center" wrapText="1"/><protection locked="0"/></xf><xf numFmtId="49" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs></styleSheet>`;

/** V773: the style table with the workbook's extra styles appended (styleExtras): each colour a fill of its own (5, 6, …, in the
 *  order first asked for), a bold data cell's font (6), and one cell style per key from 15 on. With none, STYLES_XML itself —
 *  every workbook made before is byte for byte the same */
export function stylesXml(extras: string[]): string {
  if (!extras.length) return STYLES_XML;
  const keys = extras.map((k) => k.split("|"));
  const fills: string[] = [];
  for (const k of keys) { const f = k[0] === "H" ? k[1] : k[1] === "-" ? null : k[1]; if (f && !fills.includes(f)) fills.push(f); }
  const bold = keys.some((k) => k[0] === "D" && k[2] === "1");
  const fillId = (f: string) => 5 + fills.indexOf(f);
  const xfs = keys.map((k) => {
    if (k[0] === "H") {
      return `<xf numFmtId="0" fontId="1" fillId="${fillId(k[1])}" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>`;
    }
    const [, fill, b, centre, fmt] = k;
    return `<xf numFmtId="${fmt}" fontId="${b === "1" ? 6 : 0}" fillId="${fill === "-" ? 0 : fillId(fill)}" borderId="1" xfId="0"${fmt === "2" ? ' applyNumberFormat="1"' : ""} applyFont="1"${fill === "-" ? "" : ' applyFill="1"'} applyBorder="1" applyAlignment="1"><alignment ${centre === "1" ? 'horizontal="center" ' : ""}vertical="center" wrapText="1"/></xf>`;
  });
  return STYLES_XML
    .replace('<fonts count="6">', `<fonts count="${bold ? 7 : 6}">`)
    .replace("</fonts>", `${bold ? '<font><b/><sz val="11"/><name val="Calibri"/></font>' : ""}</fonts>`)
    .replace('<fills count="5">', `<fills count="${5 + fills.length}">`)
    .replace("</fills>", `${fills.map((f) => `<fill><patternFill patternType="solid"><fgColor rgb="FF${f}"/><bgColor indexed="64"/></patternFill></fill>`).join("")}</fills>`)
    .replace('<cellXfs count="15">', `<cellXfs count="${15 + xfs.length}">`)
    .replace("</cellXfs>", `${xfs.join("")}</cellXfs>`);
}

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

export function crc32(bytes: Uint8Array): number {
  let c = 0xffffffff;
  for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

/** a zip with every entry stored, as the OOXML container allows; text or bytes */
export function zipStored(entries: [string, string | Uint8Array][]): Uint8Array {
  const enc = new TextEncoder();
  const parts: Uint8Array[] = [];
  const central: Uint8Array[] = [];
  let offset = 0;
  const le16 = (n: number) => [n & 0xff, (n >>> 8) & 0xff];
  const le32 = (n: number) => [n & 0xff, (n >>> 8) & 0xff, (n >>> 16) & 0xff, (n >>> 24) & 0xff];
  for (const [name, body] of entries) {
    const nameB = enc.encode(name);
    const data = typeof body === "string" ? enc.encode(body) : body;
    const crc = crc32(data);
    const local = new Uint8Array([
      0x50, 0x4b, 0x03, 0x04, ...le16(20), ...le16(0x0800), ...le16(0), ...le16(0), ...le16(0x21),
      ...le32(crc), ...le32(data.length), ...le32(data.length), ...le16(nameB.length), ...le16(0),
    ]);
    parts.push(local, nameB, data);
    central.push(new Uint8Array([
      0x50, 0x4b, 0x01, 0x02, ...le16(20), ...le16(20), ...le16(0x0800), ...le16(0), ...le16(0), ...le16(0x21),
      ...le32(crc), ...le32(data.length), ...le32(data.length), ...le16(nameB.length), ...le16(0), ...le16(0),
      ...le16(0), ...le16(0), ...le32(0), ...le32(offset),
    ]), nameB);
    offset += local.length + nameB.length + data.length;
  }
  const centralSize = central.reduce((n, p) => n + p.length, 0);
  const end = new Uint8Array([0x50, 0x4b, 0x05, 0x06, ...le16(0), ...le16(0), ...le16(entries.length), ...le16(entries.length), ...le32(centralSize), ...le32(offset), ...le16(0)]);
  const total = offset + centralSize + end.length;
  const out = new Uint8Array(total);
  let p = 0;
  for (const part of [...parts, ...central, end]) { out.set(part, p); p += part.length; }
  return out;
}

/** the crest as a floating image over the top-left corner of a sheet */
function drawingXml(logo: XlsxLogo): string {
  const PX = 9525;
  const targetH = 58;
  const scale = targetH / logo.h;
  const cx = Math.round(logo.w * scale * PX);
  const cy = Math.round(targetH * PX);
  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>` +
    `<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">` +
    `<xdr:oneCellAnchor><xdr:from><xdr:col>0</xdr:col><xdr:colOff>19050</xdr:colOff><xdr:row>0</xdr:row><xdr:rowOff>9525</xdr:rowOff></xdr:from>` +
    `<xdr:ext cx="${cx}" cy="${cy}"/>` +
    `<xdr:pic><xdr:nvPicPr><xdr:cNvPr id="1" name="Crest"/><xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr></xdr:nvPicPr>` +
    `<xdr:blipFill><a:blip xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:embed="rId1"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill>` +
    `<xdr:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="${cx}" cy="${cy}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr>` +
    `</xdr:pic><xdr:clientData/></xdr:oneCellAnchor></xdr:wsDr>`;
}

/** a workbook: named sheets of rows, optionally with the crest on every sheet */
export function xlsx(sheets: SheetSpec[], opts: XlsxOpts = {}): Uint8Array {
  const logo = opts.logo;
  const hasLogo = !!logo;
  // V773: the styles the sheets ask for beyond the fixed table, numbered once for the whole workbook
  const extras = styleExtras(sheets.map((s) => s[2] ?? {}));
  const drawRels = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image1.png"/></Relationships>`;
  const sheetRels = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing__N__.xml"/></Relationships>`;

  const ctExtra = hasLogo
    ? `<Default Extension="png" ContentType="image/png"/>` + sheets.map((_, i) => `<Override PartName="/xl/drawings/drawing${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>`).join("")
    : "";

  const entries: [string, string | Uint8Array][] = [
    ["[Content_Types].xml", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>${ctExtra}<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>${sheets.map((_, i) => `<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>`).join("")}</Types>`],
    ["_rels/.rels", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>`],
    ["xl/workbook.xml", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>${sheets.map(([name, , o], i) => `<sheet name="${esc(name.slice(0, 31))}" sheetId="${i + 1}"${o?.hidden ? ' state="hidden"' : ""} r:id="rId${i + 1}"/>`).join("")}</sheets></workbook>`],
    ["xl/_rels/workbook.xml.rels", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${sheets.map((_, i) => `<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>`).join("")}<Relationship Id="rId${sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>`],
    ["xl/styles.xml", stylesXml(extras)],
    ...sheets.map((sh, i): [string, string] => [`xl/worksheets/sheet${i + 1}.xml`, sheetXml(sh[1], hasLogo, sh[2] ?? {}, extras)]),
  ];

  if (hasLogo && logo) {
    for (let i = 0; i < sheets.length; i++) {
      entries.push([`xl/worksheets/_rels/sheet${i + 1}.xml.rels`, sheetRels.replace("__N__", String(i + 1))]);
      entries.push([`xl/drawings/drawing${i + 1}.xml`, drawingXml(logo)]);
      entries.push([`xl/drawings/_rels/drawing${i + 1}.xml.rels`, drawRels]);
    }
    entries.push(["xl/media/image1.png", logo.png]);
  }

  return zipStored(entries);
}
