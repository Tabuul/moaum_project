import { A4, Page, pdf, type Image } from "../pdf-write.ts";
import { crestImage } from "../pdf-crest.ts";
import { addressLine, contactLine, formatDocDateTime, nameUpper, type Institution } from "./institution.ts";
import { currentInstitution, currentLogo } from "./institution-cache.ts";
import { documentTitle, profileOf, type DocumentProfile, type DocumentProfileId } from "./profiles.ts";

/**
 * The central PDF document (V320), on the portal's own PDF engine (pdf-write): the official header on
 * the first page, a compact band on the pages after it, a footer with the University, the title, when
 * and by whom it was generated and "Page X of Y", tables whose header repeats on every page and whose
 * serial numbers run on, key–value blocks, paragraphs, signature lines and a QR. A route gives the
 * profile, the title and the data; the institution profile gives the identity.
 *
 * Existing routes that draw their own pages call {@link finishPdf} to stamp the footer and bind them.
 */

export type Rgb = [number, number, number];
export const INK: Rgb = [0.08, 0.14, 0.2];
export const MUTED: Rgb = [0.4, 0.45, 0.5];
export const CHROME: Rgb = [0.05, 0.25, 0.33];
const WHITE: Rgb = [1, 1, 1];

export interface DocumentMeta {
  title: string;
  subtitle?: string | null;
  /** the filters or facts a reader needs when the paper is separated from the portal: "Faculty", "Session"… */
  meta?: [string, string][];
  reference?: string | null;
  generatedBy?: string | null;
  /** overrides the profile's copy label (STUDENT COPY, OFFICIAL COPY, UNOFFICIAL COPY) */
  copy?: string | null;
  /** overrides the profile's confidentiality label */
  confidentiality?: string | null;
  /** DRAFT, UNOFFICIAL COPY, SAMPLE… drawn across every page; null for none */
  watermark?: string | null;
  /** an organisational line under the University: "Faculty of Science · Department of Mathematics" */
  unit?: string | null;
  /** the applicant's or student's passport photograph (a JPEG), at the top right of the letterhead; null with `photoBox` draws a placeholder */
  photo?: Image | null;
  /** keep a passport-sized space even without a photograph, with a placeholder in it */
  photoBox?: boolean;
}

/** the passport container: a standard photo's proportions (35 × 45), the image fitted without distortion */
const PHOTO_W = 70, PHOTO_H = 90;
function drawPhoto(p: Page, x: number, top: number, photo: Image | null | undefined): void {
  p.box(x, top - PHOTO_H, PHOTO_W, PHOTO_H, 0.55);
  if (photo && photo.width > 0 && photo.height > 0) {
    const scale = Math.min((PHOTO_W - 4) / photo.width, (PHOTO_H - 4) / photo.height);
    const w = photo.width * scale, h = photo.height * scale;
    p.jpeg(x + (PHOTO_W - w) / 2, top - PHOTO_H + (PHOTO_H - h) / 2, w, h, photo);
  } else {
    p.text(x + 12, top - PHOTO_H / 2 + 3, "PASSPORT", 7.5, true, MUTED);
    p.text(x + 10, top - PHOTO_H / 2 - 7, "PHOTOGRAPH", 7, false, MUTED);
  }
}

const clean = (s: unknown) => String(s ?? "").replace(/[^\x20-\x7E]/g, " ").replace(/\s+/g, " ").trim();
/** text cut to what fits a width at a size, with an ellipsis */
export function fit(s: string, width: number, size: number): string {
  const max = Math.max(3, Math.floor(width / (size * 0.5)));
  return s.length <= max ? s : s.slice(0, max - 1) + "…";
}

export function pageSize(profile: DocumentProfile): { w: number; h: number } {
  return profile.orientation === "landscape" ? { w: A4.h, h: A4.w } : { w: A4.w, h: A4.h };
}

function logoFor(): Image | null {
  return currentLogo() ?? crestImage();
}

/** the full letterhead at the top of a page; returns the y to continue from */
export function drawHeader(p: Page, inst: Institution, profile: DocumentProfile, meta: DocumentMeta): number {
  const { w, h } = pageSize(p.size === A4 ? profile : profile);
  const L = profile.margin.left, R = w - profile.margin.right;
  const top = h - profile.margin.top;
  const logo = logoFor();
  const box = 54;
  let y = top;
  const textX = logo ? L + box + 12 : L;
  const withPhoto = !!meta.photo || !!meta.photoBox;
  /* the passport sits at the top right; the letterhead's text stops short of it */
  const textR = withPhoto ? R - PHOTO_W - 12 : R;
  if (withPhoto) drawPhoto(p, R - PHOTO_W, top, meta.photo);
  if (logo) {
    const ratio = logo.width && logo.height ? logo.width / logo.height : 1;
    const lw = ratio >= 1 ? box : box * ratio, lh = ratio >= 1 ? box / ratio : box;
    p.jpeg(L + (box - lw) / 2, top - box + (box - lh) / 2, lw, lh, logo);
  }
  p.text(textX, y - 13, fit(nameUpper(inst), textR - textX, 12.5), 12.5, true, CHROME);
  y -= 13;
  if (inst.motto) { y -= 13; p.textStyled(textX, y, fit(`"${clean(inst.motto)}"`, textR - textX, 9), 9, { font: "F5", colour: MUTED }); }
  const addr = addressLine(inst);
  if (addr) { y -= 12; p.text(textX, y, fit(clean(addr), textR - textX, 8), 8, false, MUTED); }
  const contact = contactLine(inst);
  if (contact) { y -= 11; p.text(textX, y, fit(clean(contact), textR - textX, 8), 8, false, MUTED); }
  if (meta.unit) { y -= 12; p.text(textX, y, fit(clean(meta.unit).toUpperCase(), textR - textX, 8.5), 8.5, true, INK); }
  y = Math.min(y, top - box, withPhoto ? top - PHOTO_H : top) - 8;
  p.rule(L, y, R, y, 1.2, 0.12);
  y -= 20;
  const title = documentTitle(profile, meta.title);
  p.text(L, y, fit(clean(title), R - L - 120, 12), 12, true, INK);
  const copy = meta.copy === undefined ? profile.copy : meta.copy;
  if (copy) p.text(R - 110, y, clean(copy).toUpperCase(), 7.5, true, MUTED);
  if (meta.subtitle) { y -= 14; p.text(L, y, fit(clean(meta.subtitle), R - L, 9.5), 9.5, false, MUTED); }
  if (meta.reference) { y -= 12; p.text(L, y, `Reference ${clean(meta.reference)}`, 8.5, false, MUTED); }
  if (meta.meta && meta.meta.length) {
    y -= 14;
    const colW = (R - L) / 2;
    for (let i = 0; i < meta.meta.length; i++) {
      const [k, v] = meta.meta[i];
      const col = i % 2, x = L + col * colW;
      p.text(x, y, clean(k).toUpperCase(), 6.5, false, MUTED);
      p.text(x + 78, y, fit(clean(v), colW - 84, 8.5), 8.5, true, INK);
      if (col === 1 || i === meta.meta.length - 1) y -= 13;
    }
  }
  y -= 8;
  return y;
}

/** the compact band on a continuation page; returns the y to continue from */
export function drawContinuationHeader(p: Page, inst: Institution, profile: DocumentProfile, meta: DocumentMeta, pageNo: number): number {
  const { w, h } = pageSize(profile);
  const L = profile.margin.left, R = w - profile.margin.right;
  const top = h - profile.margin.top;
  const logo = logoFor();
  const box = 20;
  let x = L;
  if (logo) { p.jpeg(L, top - box, box, box, logo); x = L + box + 8; }
  p.text(x, top - 9, inst.shortName.toUpperCase(), 8.5, true, CHROME);
  p.text(x, top - 19, fit(`${documentTitle(profile, meta.title)}${meta.subtitle ? ` · ${clean(meta.subtitle)}` : ""}`, R - x - 80, 7.5), 7.5, false, MUTED);
  p.text(R - 70, top - 9, `continued · ${pageNo}`, 7.5, false, MUTED);
  const y = top - box - 6;
  p.rule(L, y, R, y, 0.8, 0.3);
  return y - 16;
}

/** the footer on every page: the University and the title, when and by whom, the reference, the page, the labels */
export function drawFooter(p: Page, inst: Institution, profile: DocumentProfile, meta: DocumentMeta, pageNo: number, total: number, title?: string): void {
  const { w } = pageSize(profile);
  const L = profile.margin.left, R = w - profile.margin.right;
  const base = 28;
  p.rule(L, base + 18, R, base + 18, 0.6, 0.6);
  const t = title ?? documentTitle(profile, meta.title);
  p.text(L, base + 7, fit(`${clean(inst.name)}  |  ${clean(t)}`, R - L - 90, 7.5), 7.5, false, MUTED);
  if (profile.pageNumbers && inst.showPageNumbers) p.text(R - 60, base + 7, `Page ${pageNo} of ${total}`, 7.5, true, MUTED);
  const bits = [`Generated ${formatDocDateTime(new Date(), inst)}`];
  if (meta.generatedBy && inst.showGeneratedBy) bits.push(`by ${clean(meta.generatedBy)}`);
  if (meta.reference) bits.push(`Ref ${clean(meta.reference)}`);
  const conf = meta.confidentiality === undefined ? profile.confidentiality : meta.confidentiality;
  if (conf) bits.push(clean(conf).toUpperCase());
  p.text(L, base - 4, fit(bits.join("  ·  "), R - L, 7), 7, false, MUTED);
  if (inst.footerNote) p.text(L, base - 14, fit(clean(inst.footerNote), R - L, 6.5), 6.5, false, MUTED);
}

function watermarkPage(p: Page, meta: DocumentMeta): void {
  if (meta.watermark) p.bigDiagonalWatermark(clean(meta.watermark).toUpperCase(), 54, 0.88);
}

/**
 * Stamp the footer (and the watermark, when one applies) on pages a route drew itself, then bind them.
 * The pages keep their own headers; the footer gives them the University, the generation line and the
 * page numbers the profile asks for.
 */
export function finishPdf(pages: Page[], title: string, profileId: DocumentProfileId | string = "FORM", meta: Partial<DocumentMeta> = {}): Uint8Array {
  const profile = profileOf(profileId);
  const inst = currentInstitution();
  const m: DocumentMeta = { title, ...meta };
  if (profile.footer) {
    pages.forEach((p, i) => {
      // a page drawn landscape by its route is footed on its own width
      const prof = p.size.w > p.size.h && profile.orientation !== "landscape" ? { ...profile, orientation: "landscape" as const } : profile;
      drawFooter(p, inst, prof, m, i + 1, pages.length, documentTitle(profile, title));
      watermarkPage(p, m);
    });
  }
  return pdf(pages, clean(title) || documentTitle(profile, title));
}

export interface TableOptions {
  /** column widths in points; proportional to content when absent */
  widths?: number[];
  /** columns right-aligned (numbers) — detected when absent */
  numeric?: boolean[];
  /** a serial column leads the table (the profile's default) */
  serial?: boolean;
  /** the serial the first row carries, for a table continued from another */
  serialFrom?: number;
  size?: number;
}

/**
 * A document built page by page: give the profile and the metadata, then add blocks; the header, the
 * continuation bands, the page breaks, the footer and the numbering are the document's own business.
 */
export class PdfDocument {
  readonly profile: DocumentProfile;
  readonly inst: Institution;
  readonly meta: DocumentMeta;
  readonly pages: Page[] = [];
  readonly w: number;
  readonly h: number;
  readonly L: number;
  readonly R: number;
  readonly bottom: number;
  y = 0;
  private serial = 0;

  constructor(profileId: DocumentProfileId | string, meta: DocumentMeta, inst: Institution = currentInstitution()) {
    this.profile = profileOf(profileId);
    this.inst = inst;
    this.meta = meta;
    const s = pageSize(this.profile);
    this.w = s.w;
    this.h = s.h;
    this.L = this.profile.margin.left;
    this.R = s.w - this.profile.margin.right;
    this.bottom = this.profile.margin.bottom;
    this.newPage();
  }

  get page(): Page {
    return this.pages[this.pages.length - 1];
  }

  get width(): number {
    return this.R - this.L;
  }

  newPage(): Page {
    const p = new Page();
    p.size = { w: this.w, h: this.h };
    this.pages.push(p);
    const first = this.pages.length === 1;
    if (first && this.profile.header === "full") this.y = drawHeader(p, this.inst, this.profile, this.meta);
    else if (this.profile.continuation === "compact" || (first && this.profile.header === "compact")) this.y = drawContinuationHeader(p, this.inst, this.profile, this.meta, this.pages.length);
    else this.y = this.h - this.profile.margin.top;
    return p;
  }

  /** room for a block this tall, or a new page */
  ensure(height: number): void {
    if (this.y - height < this.bottom) this.newPage();
  }

  space(n = 10): this {
    this.y -= n;
    return this;
  }

  heading(text: string, size = 10.5): this {
    this.ensure(size + 10);
    this.page.text(this.L, this.y, clean(text).toUpperCase(), size, true, CHROME);
    this.y -= size + 8;
    return this;
  }

  paragraph(text: string, size = 9.5, lead = 1.4): this {
    const lines = Math.ceil((clean(text).length * size * 0.5) / this.width) + 1;
    this.ensure(lines * size * lead + 6);
    const end = this.page.paragraph(this.L, this.y, clean(text), this.width, size, lead);
    this.y = end - 6;
    return this;
  }

  /** labelled values in two columns: Name / Matriculation number / Programme… */
  keyValues(pairs: [string, string | number | null | undefined][], cols = 2, size = 9): this {
    const colW = this.width / cols;
    const rowH = size + 8;
    for (let i = 0; i < pairs.length; i += cols) {
      this.ensure(rowH + 4);
      for (let c = 0; c < cols && i + c < pairs.length; c++) {
        const [k, v] = pairs[i + c];
        const x = this.L + c * colW;
        this.page.text(x, this.y, clean(k).toUpperCase(), 6.5, false, MUTED);
        this.page.text(x, this.y - 10, fit(clean(v ?? "—") || "—", colW - 10, size), size, true, INK);
      }
      this.y -= rowH + 8;
    }
    return this;
  }

  private columnWidths(headers: string[], rows: (string | number | null | undefined)[][], size: number): number[] {
    const cw = size * 0.52;
    const want = headers.map((h, i) => {
      let m = h.length;
      for (const r of rows.slice(0, 400)) m = Math.max(m, Math.min(48, clean(r[i] ?? "").length));
      return Math.max(4, m) * cw + 12;
    });
    const sum = want.reduce((a, b) => a + b, 0);
    const k = sum > this.width ? this.width / sum : 1;
    return want.map((x) => x * k);
  }

  /** a table whose header repeats on every page and whose serial numbers run on across pages */
  table(headers: string[], rows: (string | number | null | undefined)[][], opts: TableOptions = {}): this {
    const serial = opts.serial ?? this.profile.serialColumn;
    const hdr = serial ? ["S/N", ...headers] : headers;
    if (opts.serialFrom !== undefined) this.serial = opts.serialFrom - 1;
    const body = serial ? rows.map((r) => [++this.serial, ...r]) : rows;
    const size = opts.size ?? (hdr.length > 12 ? 6.5 : hdr.length > 8 ? 7.5 : 8.5);
    const rowH = size * 2;
    const widths = opts.widths ? (serial ? [26, ...opts.widths] : opts.widths) : this.columnWidths(hdr, body, size);
    const numeric = hdr.map((_, i) => opts.numeric ? (serial ? i === 0 || !!opts.numeric[i - 1] : !!opts.numeric[i])
      : body.length > 0 && body.every((r) => r[i] == null || r[i] === "" || typeof r[i] === "number" || /^-?[\d,]+(\.\d+)?%?$/.test(String(r[i]).trim())) && body.some((r) => r[i] != null && r[i] !== ""));
    const headerRow = () => {
      this.ensure(rowH * 2);
      const y = this.y;
      this.page.fillRgb(this.L, y - rowH + 4, this.width, rowH, CHROME);
      let x = this.L;
      hdr.forEach((h, i) => {
        const w = widths[i];
        const t = fit(clean(h).toUpperCase(), w - 8, size - 1);
        this.page.text(numeric[i] ? x + w - 4 - t.length * (size - 1) * 0.5 : x + 4, y - rowH + 10, t, size - 1, true, WHITE);
        x += w;
      });
      this.y = y - rowH;
    };
    headerRow();
    body.forEach((r, ri) => {
      if (this.y - rowH < this.bottom) { this.newPage(); headerRow(); }
      const y = this.y;
      if (ri % 2 === 1) this.page.fill(this.L, y - rowH + 4, this.width, rowH, 0.965);
      let x = this.L;
      hdr.forEach((_, i) => {
        const w = widths[i];
        const raw = r[i];
        const t = fit(typeof raw === "number" ? raw.toLocaleString("en-NG") : clean(raw ?? ""), w - 8, size);
        this.page.text(numeric[i] ? x + w - 4 - t.length * size * 0.5 : x + 4, y - rowH + 10, t, size, false, INK);
        x += w;
      });
      this.page.rule(this.L, y - rowH + 4, this.R, y - rowH + 4, 0.3, 0.85);
      this.y = y - rowH;
    });
    this.y -= 10;
    return this;
  }

  /** signature lines kept together: a name and designation under each */
  signatures(signatories: { name?: string | null; designation: string }[]): this {
    const block = 54;
    this.ensure(block + 20);
    const n = Math.max(1, signatories.length);
    const colW = this.width / n;
    signatories.forEach((s, i) => {
      const x = this.L + i * colW;
      const y = this.y - 30;
      this.page.rule(x, y, x + colW - 24, y, 0.6, 0.55);
      if (s.name) this.page.text(x, y - 11, fit(clean(s.name), colW - 28, 8.5), 8.5, true, INK);
      this.page.text(x, y - (s.name ? 22 : 11), fit(clean(s.designation), colW - 28, 7.5), 7.5, false, MUTED);
    });
    this.y -= block + 10;
    return this;
  }

  /** a QR for the verification address, with the address and a check code under it */
  qr(matrix: { size: number; dark: boolean[] }, caption: string, side = 72): this {
    this.ensure(side + 36);
    const cell = side / matrix.size;
    const top = this.y;
    for (let r = 0; r < matrix.size; r++) for (let c = 0; c < matrix.size; c++) if (matrix.dark[r * matrix.size + c]) this.page.fill(this.L + c * cell, top - (r + 1) * cell, cell, cell, 0);
    this.page.text(this.L, top - side - 10, "SCAN TO VERIFY", 7, true, MUTED);
    this.page.text(this.L, top - side - 20, fit(clean(caption), this.width, 6.5), 6.5, false, MUTED);
    this.y = top - side - 32;
    return this;
  }

  /** the pages footed and bound */
  finish(): Uint8Array {
    const total = this.pages.length;
    this.pages.forEach((p, i) => {
      if (this.profile.footer) drawFooter(p, this.inst, this.profile, this.meta, i + 1, total);
      watermarkPage(p, this.meta);
    });
    return pdf(this.pages, clean(documentTitle(this.profile, this.meta.title)));
  }
}
