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
