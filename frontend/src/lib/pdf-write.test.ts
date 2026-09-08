import { test } from "node:test";
import assert from "node:assert/strict";
import { Page, escapePdf, jpegSize, pdf } from "./pdf-write.ts";

test("a document is a PDF with its pages, fonts and a cross-reference table that points where it says", () => {
  const p = new Page();
  p.text(72, 780, "Post-UTME screening slip", 16, true).rule(72, 770, 523, 770).paragraph(72, 750, "Bring this slip and a valid identification document. ".repeat(6), 450);
  const bytes = pdf([p, new Page().text(72, 780, "Page two")], "Slip");
  const text = new TextDecoder("latin1").decode(bytes);
  assert.ok(text.startsWith("%PDF-1.4"));
  assert.ok(text.includes("/Type /Catalog"));
  assert.ok(text.includes("/Count 2"));
  assert.ok(text.includes("/BaseFont /Helvetica-Bold"));
  assert.ok(text.includes("(Post-UTME screening slip) Tj"));
  const startxref = Number(/startxref\n(\d+)\n%%EOF/.exec(text)?.[1]);
  assert.equal(text.slice(startxref, startxref + 4), "xref");
  /* the first object offset in the table is where "1 0 obj" is */
  const firstOffset = Number(/xref\n0 \d+\n0000000000 65535 f \n(\d{10})/.exec(text)?.[1]);
  assert.equal(text.slice(firstOffset, firstOffset + 7), "1 0 obj");
});

test("text is escaped for the content stream and typographic characters become WinAnsi or plain", () => {
  assert.equal(escapePdf("a (b) \\ c"), "a \\(b\\) \\\\ c");
  assert.equal(escapePdf("O’Level — ₦2,300 · é"), "O'Level - NGN 2,300 \\267 \\351");
});

test("a JPEG's size is read from its frame header", () => {
  /* SOI, APP0 (2+14 bytes), SOF0 with height 104 and width 84 */
  const jpg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
    0xff, 0xc0, 0x00, 0x11, 0x08, 0x00, 0x68, 0x00, 0x54, 0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01]);
  assert.deepEqual(jpegSize(jpg), { width: 84, height: 104 });
  assert.equal(jpegSize(new Uint8Array([0x89, 0x50, 0x4e, 0x47])), null);
});
