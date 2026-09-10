/**
 * Reads the first worksheet of an .xlsx as rows of strings — in the browser,
 * with nothing loaded from anywhere.
 *
 * An .xlsx is a ZIP of XML. The ZIP directory is a few fixed-layout records;
 * deflate is something the platform inflates natively (DecompressionStream);
 * the XML these files carry is regular enough to read with a handful of
 * patterns. Ported from the prototype, which read real CAPS downloads this
 * way, and kept dependency-free for the same reason: the admission list
 * never leaves the office's browser until it has been read and shown back.
 *
 * Handles stored and deflated entries, shared strings, inline strings and
 * numbers. Not ZIP64, which an admission list will never reach, and not
 * dates, which these files do not carry. A file it cannot read throws,
 * because an empty list looks like a successful import of nothing.
 */

interface ZipEntry {
  method: number;
  bytes: Uint8Array;
}

function zipEntries(buf: ArrayBuffer): Record<string, ZipEntry> {
  const dv = new DataView(buf);
  const out: Record<string, ZipEntry> = {};
  let i = buf.byteLength - 22;
  for (; i >= 0; i--) {
    if (dv.getUint32(i, true) === 0x06054b50) break;
  }
  if (i < 0) throw new Error("not a .xlsx file — no ZIP directory in it");
  let n = dv.getUint16(i + 10, true);
  let off = dv.getUint32(i + 16, true);
  const decoder = new TextDecoder();
  while (n-- > 0) {
    if (dv.getUint32(off, true) !== 0x02014b50) break;
    const method = dv.getUint16(off + 10, true);
    const csize = dv.getUint32(off + 20, true);
    const nameLen = dv.getUint16(off + 28, true);
    const extraLen = dv.getUint16(off + 30, true);
    const cmtLen = dv.getUint16(off + 32, true);
    const lho = dv.getUint32(off + 42, true);
    const name = decoder.decode(new Uint8Array(buf, off + 46, nameLen));
    const lnLen = dv.getUint16(lho + 26, true);
    const leLen = dv.getUint16(lho + 28, true);
    out[name] = { method, bytes: new Uint8Array(buf, lho + 30 + lnLen + leLen, csize) };
    off += 46 + nameLen + extraLen + cmtLen;
  }
  return out;
}

async function inflate(e: ZipEntry): Promise<string> {
  if (e.method === 0) return new TextDecoder().decode(e.bytes);
  if (e.method !== 8) throw new Error(`the file uses ZIP compression method ${e.method}, which cannot be read here`);
  const stream = new Blob([e.bytes as BlobPart]).stream().pipeThrough(new DecompressionStream("deflate-raw"));
  return new Response(stream).text();
}

/** "AB12" → 27 */
export function colOf(ref: string): number {
  let c = 0;
  for (let i = 0; i < ref.length; i++) {
    const ch = ref.charCodeAt(i);
    if (ch < 65 || ch > 90) break;
    c = c * 26 + (ch - 64);
  }
  return c - 1;
}

const ENTITIES: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'" };

export function unescapeXml(s: string): string {
  return s.replace(/&(#x[0-9a-fA-F]+|#\d+|[a-z]+);/g, (m, e: string) => {
    if (e[0] === "#") return String.fromCodePoint(e[1] === "x" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10));
    return e in ENTITIES ? ENTITIES[e] : m;
  });
}

/** Every <t> inside an element, concatenated — a shared string may be split into runs. */
function textRuns(xml: string): string {
  let t = "";
  for (const m of xml.matchAll(/<t\b[^>]*>([\s\S]*?)<\/t>/g)) t += unescapeXml(m[1]);
  return t;
}

export function sharedStrings(xml: string): string[] {
  const out: string[] = [];
  for (const m of xml.matchAll(/<si\b[^>]*>([\s\S]*?)<\/si>/g)) out.push(textRuns(m[1]));
  return out;
}

/** The rows of one worksheet's XML, every cell as a trimmed string. */
export function sheetRows(xml: string, shared: string[]): string[][] {
  const rows: string[][] = [];
  for (const rm of xml.matchAll(/<row\b[^>]*>([\s\S]*?)<\/row>/g)) {
    const row: string[] = [];
    for (const cm of rm[1].matchAll(/<c\b([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g)) {
      const attrs = cm[1];
      const inner = cm[2] ?? "";
      const ref = /\br="([A-Z]+)\d+"/.exec(attrs)?.[1] ?? "A";
      const type = /\bt="([^"]*)"/.exec(attrs)?.[1];
      let v = "";
      if (type === "s") {
        const idx = /<v>([\s\S]*?)<\/v>/.exec(inner)?.[1];
        v = idx === undefined ? "" : (shared[Number(idx)] ?? "");
      } else if (type === "inlineStr") {
        v = textRuns(inner);
      } else {
        const raw = /<v>([\s\S]*?)<\/v>/.exec(inner)?.[1];
        v = raw === undefined ? "" : unescapeXml(raw);
      }
      row[colOf(ref)] = v.trim();
    }
    for (let i = 0; i < row.length; i++) if (row[i] === undefined) row[i] = "";
    rows.push(row);
  }
  return rows;
}

/** The first worksheet of an .xlsx, as rows of strings. */
export async function xlsxRows(buf: ArrayBuffer): Promise<string[][]> {
  const z = zipEntries(buf);
  const sheet = Object.keys(z)
    .filter((k) => /^xl\/worksheets\/sheet\d+\.xml$/.test(k))
    .sort()[0];
  if (!sheet) throw new Error("the workbook has no worksheet in it");
  const [sheetXml, sharedXml] = await Promise.all([
    inflate(z[sheet]),
    z["xl/sharedStrings.xml"] ? inflate(z["xl/sharedStrings.xml"]) : Promise.resolve(""),
  ]);
  if (!/<(?:\w+:)?sheetData\b/.test(sheetXml)) throw new Error("the worksheet inside the file is not readable");
  return sheetRows(sheetXml, sharedXml ? sharedStrings(sharedXml) : []);
}

// ── writer: build a formatted .xlsx (auto widths + bordered cells) ──
/** A tiny, dependency-free .xlsx writer: a stored (uncompressed) ZIP of minimal
 *  OOXML parts. Columns are auto-sized to the longest value in each, and every
 *  cell carries a thin border; the header row is bold on a shaded fill. Real
 *  numbers become numeric cells; everything else is written as text, so JAMB
 *  numbers, matriculation numbers and phone numbers keep their leading zeros.
 */

type Cell = string | number | null | undefined;

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(bytes: Uint8Array): number {
  let c = 0xffffffff;
  for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

/** a stored (method 0) ZIP of the given files */
function zip(files: { name: string; data: Uint8Array }[]): Uint8Array {
  const enc = new TextEncoder();
  const parts: Uint8Array[] = [];
  const central: Uint8Array[] = [];
  let offset = 0;
  for (const f of files) {
    const name = enc.encode(f.name);
    const crc = crc32(f.data);
    const size = f.data.length;
    const lh = new DataView(new ArrayBuffer(30));
    lh.setUint32(0, 0x04034b50, true);
    lh.setUint16(4, 20, true);
    lh.setUint16(8, 0, true);
    lh.setUint32(14, crc, true);
    lh.setUint32(18, size, true);
    lh.setUint32(22, size, true);
    lh.setUint16(26, name.length, true);
    parts.push(new Uint8Array(lh.buffer), name, f.data);
    const ch = new DataView(new ArrayBuffer(46));
    ch.setUint32(0, 0x02014b50, true);
    ch.setUint16(4, 20, true);
    ch.setUint16(6, 20, true);
    ch.setUint32(16, crc, true);
    ch.setUint32(20, size, true);
    ch.setUint32(24, size, true);
    ch.setUint16(28, name.length, true);
    ch.setUint32(42, offset, true);
    central.push(new Uint8Array(ch.buffer), name);
    offset += 30 + name.length + size;
  }
  let centralSize = 0;
  for (const c of central) centralSize += c.length;
  const eocd = new DataView(new ArrayBuffer(22));
  eocd.setUint32(0, 0x06054b50, true);
  eocd.setUint16(8, files.length, true);
  eocd.setUint16(10, files.length, true);
  eocd.setUint32(12, centralSize, true);
  eocd.setUint32(16, offset, true);
  const all = [...parts, ...central, new Uint8Array(eocd.buffer)];
  let total = 0;
  for (const a of all) total += a.length;
  const out = new Uint8Array(total);
  let p = 0;
  for (const a of all) {
    out.set(a, p);
    p += a.length;
  }
  return out;
}

const xesc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

function colLetter(n: number): string {
  let s = "";
  let x = n;
  while (x >= 0) {
    s = String.fromCharCode((x % 26) + 65) + s;
    x = Math.floor(x / 26) - 1;
  }
  return s;
}

const isNum = (v: Cell): v is number => typeof v === "number" && Number.isFinite(v);

/** build a one-sheet .xlsx workbook from a header row and data rows */
export function buildXlsx(headers: string[], rows: Cell[][], sheetName = "Sheet1"): Blob {
  const all = [headers, ...rows];
  const nCols = headers.length;
  const widths: number[] = [];
  for (let c = 0; c < nCols; c++) {
    let max = 8;
    for (const r of all) {
      const v = r[c];
      const len = v == null ? 0 : String(v).length;
      if (len > max) max = len;
    }
    widths[c] = Math.min(max + 2, 70);
  }

  const cols = "<cols>" + widths.map((w, i) => `<col min="${i + 1}" max="${i + 1}" width="${w}" customWidth="1"/>`).join("") + "</cols>";
  const rowsXml = all
    .map((r, ri) => {
      const style = ri === 0 ? 1 : 2;
      const cells = r
        .map((v, ci) => {
          const ref = colLetter(ci) + (ri + 1);
          if (v == null || v === "") return `<c r="${ref}" s="${style}"/>`;
          if (ri > 0 && isNum(v)) return `<c r="${ref}" s="${style}"><v>${v}</v></c>`;
          return `<c r="${ref}" s="${style}" t="inlineStr"><is><t xml:space="preserve">${xesc(String(v))}</t></is></c>`;
        })
        .join("");
      return `<row r="${ri + 1}">${cells}</row>`;
    })
    .join("");

  const sheet = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">${cols}<sheetData>${rowsXml}</sheetData></worksheet>`;

  const styles = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts>
<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF0E3F55"/><bgColor indexed="64"/></patternFill></fill></fills>
<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left style="thin"><color rgb="FFB4C2CC"/></left><right style="thin"><color rgb="FFB4C2CC"/></right><top style="thin"><color rgb="FFB4C2CC"/></top><bottom style="thin"><color rgb="FFB4C2CC"/></bottom><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="3">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left" vertical="center"/></xf>
<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"/>
</cellXfs>
</styleSheet>`;

  const safeSheet = xesc(sheetName).slice(0, 31);
  const workbook = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="${safeSheet}" sheetId="1" r:id="rId1"/></sheets></workbook>`;

  const wbRels = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>`;

  const rootRels = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>`;

  const contentTypes = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>`;

  const enc = new TextEncoder();
  const bytes = zip([
    { name: "[Content_Types].xml", data: enc.encode(contentTypes) },
    { name: "_rels/.rels", data: enc.encode(rootRels) },
    { name: "xl/workbook.xml", data: enc.encode(workbook) },
    { name: "xl/_rels/workbook.xml.rels", data: enc.encode(wbRels) },
    { name: "xl/styles.xml", data: enc.encode(styles) },
    { name: "xl/worksheets/sheet1.xml", data: enc.encode(sheet) },
  ]);
  return new Blob([bytes as BlobPart], { type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" });
}
