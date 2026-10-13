/** V441: the one PDF the public page downloads, drawn by the portal's own document engine with the University's letterhead
 *  and footer. Server side only (the engine reads files); the text helpers and types live in lib/legal-text.ts. */
import { PdfDocument } from "./document/pdf.ts";
import type { Institution } from "./document/institution.ts";
import { blocks, legalDay, type LegalDocument } from "./legal-text.ts";

export { anchor, blocks, legalDay, type Block, type LegalDocument, type LegalSection } from "./legal-text.ts";

/** the document engine's writer keeps to ASCII: typographic marks are given their plain forms rather than dropped */
const plain = (s: string) => s.replace(/[—–]/g, "-").replace(/[“”]/g, '"').replace(/[‘’]/g, "'").replace(/·/g, "-").replace(/…/g, "...");

/** the whole document as one PDF: letterhead, version and dates, every section in order, the contact block; page numbers from the profile */
export function legalPdf(doc: LegalDocument, inst?: Institution): Uint8Array {
  const meta = {
    title: doc.title,
    subtitle: `Version ${doc.version}${doc.status !== "PUBLISHED" ? ` (${doc.status.toLowerCase()})` : ""}`,
    meta: [
      ["Version", String(doc.version)],
      ["Effective date", legalDay(doc.effectiveOn)],
      ["Published", legalDay(doc.publishedAt)],
      ["Last updated", legalDay(doc.updatedAt)],
    ] as [string, string][],
    copy: "",
    confidentiality: "Public document",
    watermark: doc.status === "PUBLISHED" ? null : "DRAFT",
  };
  const d = inst ? new PdfDocument("STANDARD_REPORT", meta, inst) : new PdfDocument("STANDARD_REPORT", meta);
  if (doc.summary) {
    d.paragraph(plain(doc.summary), 9.5);
    d.space(4);
  }
  d.heading("Contents", 9);
  const toc = doc.sections.map((s) => `${s.no}. ${plain(s.heading)}`);
  for (let i = 0; i < toc.length; i += 2) {
    d.keyValues([[" ", toc[i]], [" ", toc[i + 1] ?? ""]], 2, 8);
  }
  d.space(6);
  for (const s of doc.sections) {
    d.heading(`${s.no}. ${plain(s.heading)}`);
    for (const b of blocks(s.body)) {
      if (b.kind === "p") d.paragraph(plain(b.text));
      else for (const item of b.items) d.paragraph("- " + plain(item), 9.5, 1.35);
    }
    d.space(2);
  }
  d.space(6);
  d.heading("Privacy contact");
  d.keyValues([
    ["Name", plain(doc.contact.name || "—")], ["Title", plain(doc.contact.title || "—")],
    ["Office", plain(doc.contact.office || "—")], ["E-mail", plain(doc.contact.email || "—")],
    ["Telephone", plain(doc.contact.phone || "—")], ["Address", plain(doc.contact.address || doc.institution.address || "—")],
  ]);
  return d.finish();
}
