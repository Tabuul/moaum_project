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

/** the column-header row is the first row that starts with "SN"; everything
 *  above it is the letterhead, everything below it is data */
function headerRow(rows: Cell[][]): number {
  const i = rows.findIndex((r) => String(r[0] ?? "").trim().toUpperCase() === "SN");
  return i < 0 ? 0 : i;
}

export function sheetXml(rows: Cell[][], hasLogo = false): string {
  const hdr = headerRow(rows);
  const nCols = rows.reduce((m, r) => Math.max(m, r.length), 0);
  // widths from the data grid only, so a long school name does not blow out a column
  const widths: number[] = [];
  for (let c = 0; c < nCols; c++) {
    let max = 8;
    for (let r = hdr; r < rows.length; r++) { const v = rows[r][c]; const len = v == null ? 0 : String(v).length; if (len > max) max = len; }
    widths[c] = Math.min(max + 2, 70);
  }
  const cols = nCols ? "<cols>" + widths.map((w, i) => `<col min="${i + 1}" max="${i + 1}" width="${w}" customWidth="1"/>`).join("") + "</cols>" : "";
  const out: string[] = [];
  let titleSeen = false;
  rows.forEach((row, r) => {
    if (r < hdr) {
      // letterhead: only the non-empty cells, no borders; the first is the school name
      const cells: string[] = [];
      row.forEach((v, c) => {
        if (v === null || v === undefined || v === "") return;
        const style = titleSeen ? 4 : 3;
        titleSeen = true;
        cells.push(`<c r="${colName(c)}${r + 1}" s="${style}" t="inlineStr"><is><t xml:space="preserve">${esc(String(v))}</t></is></c>`);
      });
      if (cells.length) out.push(`<row r="${r + 1}">${cells.join("")}</row>`);
      return;
    }
    const s = r === hdr ? 1 : 2; // the column-header row bold on a shaded fill; the data bordered
    const cells: string[] = [];
    row.forEach((v, c) => {
      const ref = `${colName(c)}${r + 1}`;
      if (v === null || v === undefined || v === "") { cells.push(`<c r="${ref}" s="${s}"/>`); return; }
      if (typeof v === "number" && Number.isFinite(v)) cells.push(`<c r="${ref}" s="${s}"><v>${v}</v></c>`);
      else cells.push(`<c r="${ref}" s="${s}" t="inlineStr"><is><t xml:space="preserve">${esc(String(v))}</t></is></c>`);
    });
    if (cells.length) out.push(`<row r="${r + 1}">${cells.join("")}</row>`);
  });
  const drawing = hasLogo ? `<drawing r:id="rId1"/>` : "";
  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">${cols}<sheetData>${out.join("")}</sheetData>${drawing}</worksheet>`;
}

const STYLES_XML = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="4"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font><font><b/><sz val="13"/><color rgb="FF0E3F55"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FF122019"/><name val="Calibri"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF0E3F55"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left style="thin"><color rgb="FFB4C2CC"/></left><right style="thin"><color rgb="FFB4C2CC"/></right><top style="thin"><color rgb="FFB4C2CC"/></top><bottom style="thin"><color rgb="FFB4C2CC"/></bottom><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="5"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="center"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"/><xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="left" vertical="center"/></xf><xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="left" vertical="center"/></xf></cellXfs></styleSheet>`;

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
export function xlsx(sheets: [string, Cell[][]][], opts: XlsxOpts = {}): Uint8Array {
  const logo = opts.logo;
  const hasLogo = !!logo;
  const drawRels = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image1.png"/></Relationships>`;
  const sheetRels = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing__N__.xml"/></Relationships>`;

  const ctExtra = hasLogo
    ? `<Default Extension="png" ContentType="image/png"/>` + sheets.map((_, i) => `<Override PartName="/xl/drawings/drawing${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>`).join("")
    : "";

  const entries: [string, string | Uint8Array][] = [
    ["[Content_Types].xml", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>${ctExtra}<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>${sheets.map((_, i) => `<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>`).join("")}</Types>`],
    ["_rels/.rels", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>`],
    ["xl/workbook.xml", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>${sheets.map(([name], i) => `<sheet name="${esc(name.slice(0, 31))}" sheetId="${i + 1}" r:id="rId${i + 1}"/>`).join("")}</sheets></workbook>`],
    ["xl/_rels/workbook.xml.rels", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${sheets.map((_, i) => `<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>`).join("")}<Relationship Id="rId${sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>`],
    ["xl/styles.xml", STYLES_XML],
    ...sheets.map(([, rows], i): [string, string] => [`xl/worksheets/sheet${i + 1}.xml`, sheetXml(rows, hasLogo)]),
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
