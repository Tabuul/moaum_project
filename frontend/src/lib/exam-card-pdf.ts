import { A4, Page, textWidth, type Image } from "@/lib/pdf-write";
import { crestImage } from "@/lib/pdf-crest";
import { qrMatrix } from "@/lib/qr";

/**
 * The examination card's design, shared (V492): the page with its watermarks, the centred header, the photograph with the name
 * under it, the student's particulars, the table's dark header row, the instructions and regulations in two columns, the
 * verification QR with its check code, and the footer line. The examination card and the GST & EPS examination permit card are
 * both drawn with these, so the permit looks like the card it sits beside; each document draws only its own table.
 */

/** the left (and right) margin of the card */
export const CARD_L = 56;

/** printable ASCII, single-spaced — what the PDF's standard fonts can show */
export const cardClean = (s: string | null | undefined) => (s ?? "").replace(/[^\x20-\x7E]/g, " ").replace(/\s+/g, " ").trim();
export const cardCut = (s: string, n: number) => (s.length > n ? s.slice(0, n - 1).trimEnd() + "..." : s);
export const cardDay = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");

export const EXAM_INSTRUCTIONS = [
  "Do not write anything on your examination card.",
  "Do not write anything on your question paper.",
  "Do not exchange your examination card.",
  "Do not impersonate or be impersonated.",
  "Fill in your particulars accurately on the examination booklet.",
  "Ensure your attendance slip is fully completed and submitted.",
  "Submit your answer script before you leave the hall.",
  "Have your student I.D. card on your person.",
];
export const EXAM_REGULATIONS = [
  "Only writing materials, or items specially allowed, may be introduced into the hall.",
  "Candidates must be seated at least 10 minutes before the scheduled time.",
  "No candidate is admitted 30 minutes after commencement, or may leave before the first 45 minutes or during the last 15.",
  "Assisting, aiding or abetting cheating is prohibited.",
  "Silence must be maintained; raise your hand to call the invigilator.",
  "Smoking is prohibited in the examination hall.",
  "No answer script or sheet may be taken out by any candidate.",
  "Cheat-notes or any other material, relevant or not, are prohibited.",
  "Mobile phones or similar devices, on or off, are prohibited in the hall.",
  "No candidate may leave the hall unaccompanied and return to it.",
  "Any infraction of this card constitutes an examination irregularity and is subject to sanctions.",
  "Your examination card is a security document; protect it.",
  "Exchange of the examination card is misconduct.",
  "Avoid misplacement of your examination card.",
];

/**
 * The page and its header: the faint crest and the matric number as watermarks, the crest, the University's name, the office,
 * and the document's title. With a band, the title is set white on the card's ink colour with a line under it (the session and
 * semester), so a document that is not the examination card is told apart at a glance. Returns the page and where the body starts.
 */
export function cardPage(o: { matric: string; institution: string; office: string; title: string; band?: string }): { p: Page; y: number } {
  const p = new Page();
  const L = CARD_L;
  const crest = crestImage();
  if (crest) p.imageWatermark((A4.w - 340) / 2, (A4.h - 360) / 2, 340, 340, crest);   // big faint centred crest
  p.watermark(o.matric);   // the matric number, tiled faint at 45°, as a security watermark
  p.bigDiagonalWatermark(o.matric);   // one bold matric number, large and diagonal, centred as the main watermark

  // ── centred header ──
  const cx = A4.w / 2;
  const htop = A4.h - 38;
  if (crest) p.jpeg(cx - 21, htop - 42, 42, 42, crest);
  p.textCenter(cx, htop - 55, o.institution, 12, true);
  p.textCenter(cx, htop - 68, o.office, 9, false, [0.35, 0.35, 0.35]);
  let y: number;
  if (o.band === undefined) {
    p.textCenter(cx, htop - 84, o.title, 12, true, [0.1, 0.25, 0.4]);
    y = htop - 96;
  } else {
    p.fillRgb(L, htop - 90, A4.w - 2 * L, 19, [0.1, 0.25, 0.4]);
    p.textCenter(cx, htop - 84, o.title, 12, true, [1, 1, 1]);
    p.textCenter(cx, htop - 104, o.band, 9, true, [0.1, 0.25, 0.4]);
    y = htop - 114;
  }
  p.rule(L, y, A4.w - L, y, 1, 0.2);
  y -= 22;
  return { p, y };
}

/** the photograph top-right with the name centred under it (and "Original"), and the particulars down the left; returns where
 *  the table starts, below both */
export function cardIdentity(p: Page, top: number, o: { photo: Image | null; name: string; details: [string, string][] }): number {
  const L = CARD_L;
  let y = top;
  const pw = 74, ph = 88, px = A4.w - L - pw, ptop = y + 8;
  if (o.photo) p.jpeg(px, ptop - ph, pw, ph, o.photo);
  else { for (const [a, b, cc, d] of [[px, ptop, px + pw, ptop], [px, ptop - ph, px + pw, ptop - ph], [px, ptop, px, ptop - ph], [px + pw, ptop, px + pw, ptop - ph]]) p.rule(a, b, cc, d, 0.6, 0.7); p.text(px + 20, ptop - ph / 2, "PHOTO", 8, false, [0.6, 0.6, 0.6]); }
  // the student's name centred under the photo (auto-fit to the photo's width), with "Original" beneath it
  const nameCx = px + pw / 2;
  const nm = o.name;
  const nmSize = Math.max(5, Math.min(7.5, pw / (Math.max(1, nm.length) * 0.54)));
  p.textCenter(nameCx, ptop - ph - 9, nm, nmSize, true);
  p.textCenter(nameCx, ptop - ph - 19, "Original", 6.5, false, [0.5, 0.5, 0.5]);

  for (const [k, val] of o.details) {
    p.text(L, y, k.toUpperCase(), 7, false, [0.4, 0.4, 0.4]);
    p.text(L + 140, y, val, 10, true);
    y -= 15;
  }
  return Math.min(y, ptop - ph - 30) - 4;   // leave room under the photo for the name and the "Original" line
}

/** the table's dark header row, its labels white at the given x positions */
export function cardTableHead(p: Page, y: number, cells: [number, string][]): void {
  p.fill(CARD_L, y - 4, A4.w - 2 * CARD_L, 16, 0.16);
  for (const [x, label] of cells) p.text(x, y, label, 8, true, [1, 1, 1]);
}

/** the rule under the table and the line that counts it; returns where the instructions start */
export function cardTableEnd(p: Page, y: number, summary: string): number {
  p.rule(CARD_L, y + 7, A4.w - CARD_L, y + 7, 0.8, 0.55);
  p.text(CARD_L + 8, y - 4, summary, 9, true);
  return y - 22;
}

/** the instructions to the candidate and the examination regulations, two compact columns; returns where they end */
export function cardRules(p: Page, y: number, instructions: string[], regulations: string[]): number {
  const L = CARD_L;
  const colW = (A4.w - 2 * L - 16) / 2;
  const colX2 = L + colW + 16;
  const column = (x: number, top: number, title: string, items: string[]) => {
    p.fill(x, top - 4, colW, 15, 0.16);
    p.text(x + 6, top, title, 7.5, true, [1, 1, 1]);
    let yy = top - 18;
    items.forEach((t, i) => {
      p.text(x, yy, `${i + 1}.`, 7, true);
      yy = p.paragraph(x + 14, yy, t, colW - 14, 7, 1.25) - 2;
    });
    return yy;
  };
  const colTop = y;
  const endL = column(L, colTop, "INSTRUCTIONS TO THE CANDIDATE", instructions);
  const endR = column(colX2, colTop, "EXAMINATION REGULATIONS", regulations);
  return Math.min(endL, endR) - 14;
}

/** the small verify QR, bottom-left, with the check code beside it (and any further lines under the note) */
export function cardVerify(p: Page, y: number, url: string, code: string, more: string[] = []): void {
  const L = CARD_L;
  const { size, dark } = qrMatrix(url);
  const cell = 1.7, qDim = size * cell, qy = Math.max(y, 96);
  for (let rr = 0; rr < size; rr++) for (let cc = 0; cc < size; cc++) if (dark[rr * size + cc]) p.fill(L + cc * cell, qy - (rr + 1) * cell, cell, cell, 0);
  p.text(L + qDim + 12, qy - 10, "SCAN TO VERIFY", 8, true, [0.4, 0.4, 0.4]);
  p.text(L + qDim + 12, qy - 24, `Check code  ${code}`, 8.5, true);
  p.text(L + qDim + 12, qy - 37, "Verified against the register — the invigilator checks the face against the photograph.", 7, false, [0.45, 0.45, 0.45]);
  more.forEach((t, i) => p.text(L + qDim + 12, qy - 50 - i * 12, t, 8, true));
}

/** the line at the foot of the card: whose it is, when it was issued, what it is valid for */
export function cardFooter(p: Page, text: string, y = 40): void {
  p.text(CARD_L, y, text, 7, false, [0.45, 0.45, 0.45]);
}

/** text broken into lines that fit a width at a size (Helvetica's own widths), at most `max` lines, the last cut with "..." */
export function cardWrap(s: string, width: number, size: number, bold = false, max = 2): string[] {
  const words = s.split(" ").filter(Boolean);
  const lines: string[] = [];
  let line = "";
  for (const w of words) {
    const next = line ? `${line} ${w}` : w;
    if (textWidth(next, size, bold) <= width || !line) { line = next; continue; }
    lines.push(line);
    line = w;
  }
  if (line) lines.push(line);
  if (lines.length <= max) return lines.map((l) => cardFit(l, width, size, bold));
  const kept = lines.slice(0, max);
  kept[max - 1] = cardFit(`${kept[max - 1]} ${lines.slice(max).join(" ")}`, width, size, bold);
  return kept;
}

/** text cut to fit a width at a size, with "..." */
export function cardFit(s: string, width: number, size: number, bold = false): string {
  if (textWidth(s, size, bold) <= width) return s;
  let t = s;
  while (t.length > 1 && textWidth(`${t}...`, size, bold) > width) t = t.slice(0, -1);
  return `${t.trimEnd()}...`;
}
