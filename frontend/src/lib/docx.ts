/**
 * Read a .docx (a zip of XML) in document order: heading paragraphs and tables,
 * so a caller can track the "100 Level" / "First Semester" heading that precedes
 * each course table. Dependency-free — the platform inflates deflate-raw natively.
 */

export type DocxBlock = { kind: "p"; text: string } | { kind: "table"; rows: string[][] };

function u16(b: Uint8Array, o: number) { return b[o] | (b[o + 1] << 8); }
function u32(b: Uint8Array, o: number) { return (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)) >>> 0; }

/** the raw (possibly deflated) bytes of one entry, from the zip central directory */
function entryBytes(buf: ArrayBuffer, want: string): { bytes: Uint8Array; stored: boolean } | null {
  const b = new Uint8Array(buf);
  let eocd = -1;
  for (let i = b.length - 22; i >= 0; i--) { if (u32(b, i) === 0x06054b50) { eocd = i; break; } }
  if (eocd < 0) return null;
  const count = u16(b, eocd + 10);
  let off = u32(b, eocd + 16);
  const dec = new TextDecoder();
  for (let n = 0; n < count; n++) {
    if (u32(b, off) !== 0x02014b50) break;
    const method = u16(b, off + 10);
    const csize = u32(b, off + 20);
    const nameLen = u16(b, off + 28);
    const extraLen = u16(b, off + 30);
    const commLen = u16(b, off + 32);
    const lho = u32(b, off + 42);
    const name = dec.decode(b.subarray(off + 46, off + 46 + nameLen));
    if (name === want) {
      const lnLen = u16(b, lho + 26);
      const leLen = u16(b, lho + 28);
      const start = lho + 30 + lnLen + leLen;
      return { bytes: b.subarray(start, start + csize), stored: method === 0 };
    }
    off += 46 + nameLen + extraLen + commLen;
  }
  return null;
}

async function inflate(e: { bytes: Uint8Array; stored: boolean }): Promise<string> {
  if (e.stored) return new TextDecoder().decode(e.bytes);
  const stream = new Blob([e.bytes as BlobPart]).stream().pipeThrough(new DecompressionStream("deflate-raw"));
  return new Response(stream).text();
}

function decodeXml(s: string): string {
  return s.replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&apos;/g, "'");
}

function paraText(p: string): string {
  return decodeXml([...p.matchAll(/<w:t[^>]*>([\s\S]*?)<\/w:t>/g)].map((m) => m[1]).join("")).trim();
}

function tableRows(tbl: string): string[][] {
  return [...tbl.matchAll(/<w:tr\b[\s\S]*?<\/w:tr>/g)].map((tr) =>
    [...tr[0].matchAll(/<w:tc\b[\s\S]*?<\/w:tc>/g)].map((tc) =>
      [...tc[0].matchAll(/<w:p\b[\s\S]*?<\/w:p>/g)].map((p) => paraText(p[0])).filter(Boolean).join(" ").trim()));
}

/** the document body as an ordered list of heading paragraphs and tables */
export async function docxBlocks(buf: ArrayBuffer): Promise<DocxBlock[]> {
  const e = entryBytes(buf, "word/document.xml");
  if (!e) return [];
  const xml = await inflate(e);
  const bodyM = xml.match(/<w:body\b[\s\S]*?<\/w:body>/);
  const body = bodyM ? bodyM[0] : xml;
  const blocks: DocxBlock[] = [];
  const headingsIn = (seg: string) => {
    for (const p of seg.matchAll(/<w:p\b[\s\S]*?<\/w:p>/g)) {
      const t = paraText(p[0]);
      if (t) blocks.push({ kind: "p", text: t });
    }
  };
  let idx = 0;
  for (const m of body.matchAll(/<w:tbl\b[\s\S]*?<\/w:tbl>/g)) {
    headingsIn(body.slice(idx, m.index));
    blocks.push({ kind: "table", rows: tableRows(m[0]) });
    idx = (m.index ?? 0) + m[0].length;
  }
  headingsIn(body.slice(idx));
  return blocks;
}
