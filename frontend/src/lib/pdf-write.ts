/**
 * A small PDF writer, enough for a slip and a letter: A4 pages, Helvetica
 * in two weights, lines of text, rules, boxes, and a JPEG photograph placed
 * as it is. No library: a PDF is a handful of objects and an offset table,
 * and writing it by hand keeps the portal free of a dependency for two
 * documents. Text is WinAnsi; characters outside it are replaced.
 */

export const A4 = { w: 595.28, h: 841.89 };

type Op = string;

export interface Image { data: Uint8Array; width: number; height: number }

export class Page {
  ops: Op[] = [];
  images: { name: string; img: Image }[] = [];

  /** text at (x, y) from the bottom-left, in points; bold uses Helvetica-Bold */
  text(x: number, y: number, s: string, size = 10, bold = false, colour: [number, number, number] = [0, 0, 0]): this {
    this.ops.push(`BT /${bold ? "F2" : "F1"} ${size} Tf ${colour.map((c) => c.toFixed(3)).join(" ")} rg ${x.toFixed(2)} ${y.toFixed(2)} Td (${escapePdf(s)}) Tj ET`);
    return this;
  }

  /** wrapped text, returns the y after the last line */
  paragraph(x: number, y: number, s: string, width: number, size = 10, lead = 1.35, bold = false): number {
    const maxChars = Math.max(10, Math.floor(width / (size * 0.5)));
    const words = s.split(/\s+/);
    let line = "";
    let yy = y;
    for (const w of words) {
      if ((line + " " + w).trim().length > maxChars) {
        this.text(x, yy, line.trim(), size, bold);
        yy -= size * lead;
        line = w;
      } else {
        line = (line + " " + w).trim();
      }
    }
    if (line) {
      this.text(x, yy, line, size, bold);
      yy -= size * lead;
    }
    return yy;
  }

  rule(x1: number, y1: number, x2: number, y2: number, width = 0.6, grey = 0.75): this {
    this.ops.push(`${grey} G ${width} w ${x1.toFixed(2)} ${y1.toFixed(2)} m ${x2.toFixed(2)} ${y2.toFixed(2)} l S`);
    return this;
  }

  box(x: number, y: number, w: number, h: number, grey = 0.75): this {
    this.ops.push(`${grey} G 0.6 w ${x.toFixed(2)} ${y.toFixed(2)} ${w.toFixed(2)} ${h.toFixed(2)} re S`);
    return this;
  }

  fill(x: number, y: number, w: number, h: number, grey = 0.94): this {
    this.ops.push(`${grey} g ${x.toFixed(2)} ${y.toFixed(2)} ${w.toFixed(2)} ${h.toFixed(2)} re f 0 g`);
    return this;
  }

  /** a JPEG, placed with its bottom-left at (x, y) and the given box, keeping its own proportions inside it */
  jpeg(x: number, y: number, w: number, h: number, img: Image): this {
    const name = `Im${this.images.length + 1}`;
    this.images.push({ name, img });
    const scale = Math.min(w / img.width, h / img.height);
    const dw = img.width * scale;
    const dh = img.height * scale;
    const dx = x + (w - dw) / 2;
    const dy = y + (h - dh) / 2;
    this.ops.push(`q ${dw.toFixed(2)} 0 0 ${dh.toFixed(2)} ${dx.toFixed(2)} ${dy.toFixed(2)} cm /${name} Do Q`);
    return this;
  }
}

export function escapePdf(s: string): string {
  let out = "";
  for (const ch of s) {
    const c = ch.codePointAt(0) ?? 32;
    if (ch === "(" || ch === ")" || ch === "\\") out += "\\" + ch;
    else if (c === 0x2019 || c === 0x2018) out += "'";
    else if (c === 0x201c || c === 0x201d) out += '"';
    else if (c === 0x2013 || c === 0x2014) out += "-";
    else if (c === 0x20a6) out += "NGN ";
    else if (c === 0xb7 || c === 0x2022) out += "\\267";
    else if (c >= 0x20 && c <= 0x7e) out += ch;
    else if (c >= 0xa0 && c <= 0xff) out += "\\" + c.toString(8).padStart(3, "0");
    else out += "?";
  }
  return out;
}

/** JPEG dimensions from the SOF marker; null if the bytes are not a baseline or progressive JPEG */
export function jpegSize(data: Uint8Array): { width: number; height: number } | null {
  if (data.length < 4 || data[0] !== 0xff || data[1] !== 0xd8) return null;
  let i = 2;
  while (i + 9 < data.length) {
    if (data[i] !== 0xff) { i++; continue; }
    const marker = data[i + 1];
    if (marker === 0xd8 || marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) { i += 2; continue; }
    const len = (data[i + 2] << 8) | data[i + 3];
    if ((marker >= 0xc0 && marker <= 0xc3) || (marker >= 0xc5 && marker <= 0xc7) || (marker >= 0xc9 && marker <= 0xcb) || (marker >= 0xcd && marker <= 0xcf)) {
      return { height: (data[i + 5] << 8) | data[i + 6], width: (data[i + 7] << 8) | data[i + 8] };
    }
    i += 2 + len;
  }
  return null;
}

/** the document: pages in order, as bytes */
export function pdf(pages: Page[], title = "MOAUM Portal"): Uint8Array {
  const enc = new TextEncoder();
  const parts: Uint8Array[] = [];
  const offsets: number[] = [];
  let length = 0;
  const push = (s: string | Uint8Array) => {
    const b = typeof s === "string" ? enc.encode(s) : s;
    parts.push(b);
    length += b.length;
  };
  const obj = (n: number, body: string | Uint8Array[]) => {
    offsets[n] = length;
    push(`${n} 0 obj\n`);
    if (typeof body === "string") push(body);
    else for (const b of body) push(b);
    push("\nendobj\n");
  };
  push("%PDF-1.4\n%\xe2\xe3\xcf\xd3\n");
  /* 1 catalog · 2 pages · 3 F1 · 4 F2 · then per page: page, content, images */
  let next = 5;
  const pageIds: number[] = [];
  const built: { id: number; content: number; images: { id: number; name: string; img: Image }[]; page: Page }[] = [];
  for (const p of pages) {
    const id = next++;
    const content = next++;
    const images = p.images.map((im) => ({ id: next++, name: im.name, img: im.img }));
    pageIds.push(id);
    built.push({ id, content, images, page: p });
  }
  obj(1, "<< /Type /Catalog /Pages 2 0 R >>");
  obj(2, `<< /Type /Pages /Kids [${pageIds.map((i) => `${i} 0 R`).join(" ")}] /Count ${pageIds.length} >>`);
  obj(3, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>");
  obj(4, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>");
  for (const b of built) {
    const xobjects = b.images.map((im) => `/${im.name} ${im.id} 0 R`).join(" ");
    obj(b.id, `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${A4.w} ${A4.h}] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> /XObject << ${xobjects} >> >> /Contents ${b.content} 0 R >>`);
    const stream = enc.encode(b.page.ops.join("\n"));
    obj(b.content, [enc.encode(`<< /Length ${stream.length} >>\nstream\n`), stream, enc.encode("\nendstream")]);
    for (const im of b.images) {
      obj(im.id, [enc.encode(`<< /Type /XObject /Subtype /Image /Width ${im.img.width} /Height ${im.img.height} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${im.img.data.length} >>\nstream\n`), im.img.data, enc.encode("\nendstream")]);
    }
  }
  const infoId = next++;
  obj(infoId, `<< /Title (${escapePdf(title)}) /Producer (MOAUM Portal) >>`);
  const xref = length;
  const count = next;
  push(`xref\n0 ${count}\n0000000000 65535 f \n`);
  for (let i = 1; i < count; i++) push(`${String(offsets[i] ?? 0).padStart(10, "0")} 00000 n \n`);
  push(`trailer\n<< /Size ${count} /Root 1 0 R /Info ${infoId} 0 R >>\nstartxref\n${xref}\n%%EOF\n`);
  const out = new Uint8Array(length);
  let p = 0;
  for (const part of parts) { out.set(part, p); p += part.length; }
  return out;
}
