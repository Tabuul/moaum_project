/**
 * A drawing surface for the identity cards: one design, drawn once, to two ends — the PDF the card desk prints (pdf-write's Page) and
 * the SVG the desk shows on screen. The design is written in card units, y downward from the card's top-left corner, as a picture is
 * measured; each surface maps the units to its own space. Only what the cards need: paths (lines and Béziers), solid or linear-gradient
 * fills, strokes, text in Helvetica / Helvetica-Bold / Times-Bold, images (cover or contain, faded or multiplied), clips. Node-tested.
 */
import { Page, escapePdf, textWidth, type Image } from "./pdf-write.ts";

export type Rgb = [number, number, number];
export const hex = (h: string): Rgb => [parseInt(h.slice(1, 3), 16) / 255, parseInt(h.slice(3, 5), 16) / 255, parseInt(h.slice(5, 7), 16) / 255];

/** a linear gradient in card units: from one point to another, the colours at offsets 0..1 */
export interface Gradient { from: [number, number]; to: [number, number]; stops: [number, Rgb][] }
export type Paint = Rgb | Gradient;
export type Font = "sans" | "sansBold" | "serifBold";

type Cmd = ["M", number, number] | ["L", number, number] | ["C", number, number, number, number, number, number] | ["R", number, number, number, number] | ["Z"];

/** a path in card units */
export class Path {
  cmds: Cmd[] = [];
  M(x: number, y: number): this { this.cmds.push(["M", x, y]); return this; }
  L(x: number, y: number): this { this.cmds.push(["L", x, y]); return this; }
  C(x1: number, y1: number, x2: number, y2: number, x: number, y: number): this { this.cmds.push(["C", x1, y1, x2, y2, x, y]); return this; }
  /** a quadratic Bézier, written as the cubic it equals */
  Q(cx: number, cy: number, x: number, y: number): this {
    const last = this.cmds[this.cmds.length - 1];
    const [x0, y0] = !last || last[0] === "Z" || last[0] === "R" ? [x, y] : last[0] === "C" ? [last[5], last[6]] : [last[1], last[2]];
    return this.C(x0 + (2 / 3) * (cx - x0), y0 + (2 / 3) * (cy - y0), x + (2 / 3) * (cx - x), y + (2 / 3) * (cy - y), x, y);
  }
  Z(): this { this.cmds.push(["Z"]); return this; }
  /** a rectangle (written as one `re` in the PDF: the QR's modules and the barcode's bars are hundreds of them) */
  rect(x: number, y: number, w: number, h: number): this { this.cmds.push(["R", x, y, w, h]); return this; }
  /** a rounded rectangle; r is capped at half the shorter side (a pill when it reaches it) */
  round(x: number, y: number, w: number, h: number, r: number): this {
    r = Math.max(0, Math.min(r, w / 2, h / 2));
    const k = 0.5523 * r;
    return this.M(x + r, y).L(x + w - r, y).C(x + w - r + k, y, x + w, y + r - k, x + w, y + r)
      .L(x + w, y + h - r).C(x + w, y + h - r + k, x + w - r + k, y + h, x + w - r, y + h)
      .L(x + r, y + h).C(x + r - k, y + h, x, y + h - r + k, x, y + h - r)
      .L(x, y + r).C(x, y + r - k, x + r - k, y, x + r, y).Z();
  }
  ellipse(cx: number, cy: number, rx: number, ry: number): this {
    const kx = 0.5523 * rx, ky = 0.5523 * ry;
    return this.M(cx + rx, cy).C(cx + rx, cy + ky, cx + kx, cy + ry, cx, cy + ry).C(cx - kx, cy + ry, cx - rx, cy + ky, cx - rx, cy)
      .C(cx - rx, cy - ky, cx - kx, cy - ry, cx, cy - ry).C(cx + kx, cy - ry, cx + rx, cy - ky, cx + rx, cy).Z();
  }
  circle(cx: number, cy: number, r: number): this { return this.ellipse(cx, cy, r, r); }
  poly(points: [number, number][], close = true): this {
    points.forEach(([x, y], i) => (i ? this.L(x, y) : this.M(x, y)));
    return close ? this.Z() : this;
  }
  /** the path moved and scaled: (x, y) → (dx + x·s, dy + y·s) — an icon drawn in its own 24-unit box, placed */
  placed(dx: number, dy: number, s: number): Path {
    const out = new Path();
    for (const c of this.cmds) {
      if (c[0] === "Z") out.cmds.push(["Z"]);
      else if (c[0] === "R") out.cmds.push(["R", dx + c[1] * s, dy + c[2] * s, c[3] * s, c[4] * s]);
      else if (c[0] === "C") out.cmds.push(["C", dx + c[1] * s, dy + c[2] * s, dx + c[3] * s, dy + c[4] * s, dx + c[5] * s, dy + c[6] * s]);
      else out.cmds.push([c[0], dx + c[1] * s, dy + c[2] * s]);
    }
    return out;
  }
}
export const path = () => new Path();

export interface StrokeOptions { alpha?: number; cap?: "butt" | "round"; join?: "miter" | "round"; dash?: number[] }
export interface ImageOptions { fit?: "cover" | "contain"; alpha?: number; multiply?: boolean }
/** letter-spacing in units; hscale narrows (below 1) or widens the glyphs and the spacing alike, as a condensed face is set */
export interface TextOptions { spacing?: number; alpha?: number; hscale?: number }

export interface Surface {
  fill(p: Path, paint: Paint, o?: { alpha?: number; evenOdd?: boolean }): void;
  stroke(p: Path, colour: Rgb, width: number, o?: StrokeOptions): void;
  /** text with its baseline's left end at (x, y) */
  text(x: number, y: number, s: string, size: number, font: Font, colour: Rgb, o?: TextOptions): void;
  /** an image the surface holds under the key (the photograph, the crest, the signature); false when it holds none */
  image(key: string, x: number, y: number, w: number, h: number, o?: ImageOptions): boolean;
  has(key: string): boolean;
  /** everything drawn until restore() is clipped to the path */
  clip(p: Path, evenOdd?: boolean): void;
  restore(): void;
}

/* Times-Bold advance widths (Adobe's AFM), space (32) to tilde (126) — the University's name is set in it */
const TIMES_BOLD = [
  250, 333, 555, 500, 500, 1000, 833, 278, 333, 333, 500, 570, 250, 333, 250, 278,
  500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 333, 333, 570, 570, 570, 500,
  930, 722, 667, 722, 722, 667, 611, 778, 778, 389, 500, 778, 667, 944, 722, 778,
  611, 778, 722, 556, 667, 722, 722, 1000, 722, 722, 667, 333, 278, 333, 581, 500,
  333, 500, 556, 444, 556, 444, 333, 500, 556, 278, 333, 556, 278, 833, 556, 500,
  556, 556, 444, 389, 333, 556, 500, 722, 500, 500, 444, 394, 220, 394, 520,
];

/** the width of a run of text as it prints: the font's own widths, and the letter-spacing between the characters (not after the
 *  last), both narrowed by hscale */
export function measure(s: string, size: number, font: Font, spacing = 0, hscale = 1): number {
  const n = [...s].length;
  const gaps = Math.max(0, n - 1) * spacing;
  if (font === "serifBold") {
    let u = 0;
    for (const ch of s) { const c = ch.codePointAt(0) ?? 32; u += c >= 32 && c <= 126 ? TIMES_BOLD[c - 32] : 500; }
    return ((u * size) / 1000 + gaps) * hscale;
  }
  return (textWidth(s, size, font === "sansBold") + gaps) * hscale;
}

const f2 = (n: number) => (Math.round(n * 100) / 100).toString();
const isGradient = (p: Paint): p is Gradient => !Array.isArray(p);

/* ── PDF ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────── */

const PDF_FONT: Record<Font, string> = { sans: "F1", sansBold: "F2", serifBold: "F3" };

/** the PDF end: the card's units mapped onto a Page — its top-left at (x0, top) in points, k points to the unit. begin() and end()
 *  bracket the card (one graphics state, y turned downward), so the page's own drawing around the card is untouched */
export class PdfSurface implements Surface {
  private p: Page; private x0: number; private top: number; private k: number; private images: Record<string, Image | null | undefined>;
  constructor(p: Page, x0: number, top: number, k: number, images: Record<string, Image | null | undefined>) {
    this.p = p; this.x0 = x0; this.top = top; this.k = k; this.images = images;
  }
  /** the scale at full precision: a card drawn W points wide is W points wide (rounded to 0.01, a staff card printed 1 % large) */
  begin(): this { this.p.ops.push(`q ${this.k.toFixed(6)} 0 0 ${(-this.k).toFixed(6)} ${f2(this.x0)} ${f2(this.top)} cm`); return this; }
  end(): void { this.p.ops.push("Q"); }
  private d(p: Path): string {
    return p.cmds.map((c) => (c[0] === "Z" ? "h" : c[0] === "R" ? `${f2(c[1])} ${f2(c[2])} ${f2(c[3])} ${f2(c[4])} re` : c[0] === "M" ? `${f2(c[1])} ${f2(c[2])} m`
      : c[0] === "L" ? `${f2(c[1])} ${f2(c[2])} l` : `${f2(c[1])} ${f2(c[2])} ${f2(c[3])} ${f2(c[4])} ${f2(c[5])} ${f2(c[6])} c`)).join(" ");
  }
  private alpha(a: number | undefined): string {
    if (a === undefined || a >= 1) return "";
    const pc = Math.max(1, Math.min(99, Math.round(a * 100)));
    this.p.gs.set(`A${pc}`, `<< /ca ${(pc / 100).toFixed(2)} /CA ${(pc / 100).toFixed(2)} >>`);
    return `/A${pc} gs `;
  }
  private rgb = (c: Rgb) => c.map((v) => v.toFixed(3)).join(" ");
  private shading(g: Gradient): string {
    const stops = [...g.stops].sort((a, b) => a[0] - b[0]);
    if (stops[0][0] > 0) stops.unshift([0, stops[0][1]]);
    if (stops[stops.length - 1][0] < 1) stops.push([1, stops[stops.length - 1][1]]);
    const seg = (a: Rgb, b: Rgb) => `<< /FunctionType 2 /Domain [0 1] /C0 [${this.rgb(a)}] /C1 [${this.rgb(b)}] /N 1 >>`;
    const fn = stops.length === 2 ? seg(stops[0][1], stops[1][1])
      : `<< /FunctionType 3 /Domain [0 1] /Functions [${stops.slice(1).map((s, i) => seg(stops[i][1], s[1])).join(" ")}] /Bounds [${stops.slice(1, -1).map((s) => s[0].toFixed(4)).join(" ")}] /Encode [${stops.slice(1).map(() => "0 1").join(" ")}] >>`;
    const dict = `<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [${f2(g.from[0])} ${f2(g.from[1])} ${f2(g.to[0])} ${f2(g.to[1])}] /Function ${fn} /Extend [true true] >>`;
    for (const [name, d] of this.p.shadings) if (d === dict) return name;
    const name = `Sh${this.p.shadings.size + 1}`;
    this.p.shadings.set(name, dict);
    return name;
  }
  fill(p: Path, paint: Paint, o: { alpha?: number; evenOdd?: boolean } = {}): void {
    if (!p.cmds.length) return;
    if (isGradient(paint)) {
      this.p.ops.push(`q ${this.alpha(o.alpha)}${this.d(p)} W${o.evenOdd ? "*" : ""} n /${this.shading(paint)} sh Q`);
    } else {
      this.p.ops.push(`q ${this.alpha(o.alpha)}${this.rgb(paint)} rg ${this.d(p)} f${o.evenOdd ? "*" : ""} Q`);
    }
  }
  stroke(p: Path, colour: Rgb, width: number, o: StrokeOptions = {}): void {
    if (!p.cmds.length) return;
    const cap = o.cap === "round" ? 1 : 0, join = o.join === "round" ? 1 : 0;
    const dash = o.dash ? `[${o.dash.map(f2).join(" ")}] 0 d ` : "";
    this.p.ops.push(`q ${this.alpha(o.alpha)}${this.rgb(colour)} RG ${f2(width)} w ${cap} J ${join} j ${dash}${this.d(p)} S Q`);
  }
  text(x: number, y: number, s: string, size: number, font: Font, colour: Rgb, o: TextOptions = {}): void {
    if (!s) return;
    const tz = o.hscale && o.hscale !== 1 ? `${f2(o.hscale * 100)} Tz ` : "";
    this.p.ops.push(`q ${this.alpha(o.alpha)}BT /${PDF_FONT[font]} ${f2(size)} Tf ${f2(o.spacing ?? 0)} Tc ${tz}${this.rgb(colour)} rg 1 0 0 -1 ${f2(x)} ${f2(y)} Tm (${escapePdf(s)}) Tj ET Q`);
  }
  has(key: string): boolean { return !!this.images[key]; }
  image(key: string, x: number, y: number, w: number, h: number, o: ImageOptions = {}): boolean {
    const img = this.images[key];
    if (!img) return false;
    const name = `Im${this.p.images.length + 1}`;
    this.p.images.push({ name, img });
    const ir = img.width / img.height, br = w / h;
    let dw = w, dh = h;
    if (o.fit === "cover" ? ir > br : ir < br) dw = h * ir; else dh = w / ir;
    const dx = x + (w - dw) / 2, dy = y + (h - dh) / 2;
    const clip = o.fit === "cover" ? `${f2(x)} ${f2(y)} ${f2(w)} ${f2(h)} re W n ` : "";
    const gs = o.multiply ? "/GSM gs " : this.alpha(o.alpha);
    // the image's top row at the top: the unit square flipped into the downward units
    this.p.ops.push(`q ${clip}${gs}${f2(dw)} 0 0 ${f2(-dh)} ${f2(dx)} ${f2(dy + dh)} cm /${name} Do Q`);
    return true;
  }
  clip(p: Path, evenOdd = false): void { this.p.ops.push(`q ${this.d(p)} W${evenOdd ? "*" : ""} n`); }
  restore(): void { this.p.ops.push("Q"); }
}

/* ── SVG ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────── */

const SVG_FONT: Record<Font, string> = {
  sans: `font-family="Helvetica, Arial, 'Liberation Sans', sans-serif"`,
  sansBold: `font-family="Helvetica, Arial, 'Liberation Sans', sans-serif" font-weight="700"`,
  serifBold: `font-family="'Times New Roman', Times, 'Liberation Serif', serif" font-weight="700"`,
};
export const xml = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
const css = (c: Rgb) => `#${c.map((v) => Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, "0")).join("")}`;

/** the screen's end: the card as an SVG document in its own units (viewBox), the images by address; ids carry a prefix so two cards
 *  on one page never share a gradient or a clip */
export class SvgSurface implements Surface {
  private parts: string[] = [];
  private defs: string[] = [];
  private open = 0;
  private n = 0;
  private W: number; private H: number; private hrefs: Record<string, string | null | undefined>; private id: string;
  constructor(W: number, H: number, hrefs: Record<string, string | null | undefined>, id: string) {
    this.W = W; this.H = H; this.hrefs = hrefs; this.id = id;
  }
  private d(p: Path): string {
    return p.cmds.map((c) => (c[0] === "Z" ? "Z" : c[0] === "R" ? `M${f2(c[1])} ${f2(c[2])}h${f2(c[3])}v${f2(c[4])}h${f2(-c[3])}Z`
      : c[0] === "C" ? `C${f2(c[1])} ${f2(c[2])} ${f2(c[3])} ${f2(c[4])} ${f2(c[5])} ${f2(c[6])}` : `${c[0]}${f2(c[1])} ${f2(c[2])}`)).join("");
  }
  private next(kind: string) { this.n += 1; return `${this.id}-${kind}${this.n}`; }
  private paint(p: Paint): string {
    if (!isGradient(p)) return css(p);
    const id = this.next("g");
    this.defs.push(`<linearGradient id="${id}" gradientUnits="userSpaceOnUse" x1="${f2(p.from[0])}" y1="${f2(p.from[1])}" x2="${f2(p.to[0])}" y2="${f2(p.to[1])}">`
      + [...p.stops].sort((a, b) => a[0] - b[0]).map(([o, c]) => `<stop offset="${o.toFixed(4)}" stop-color="${css(c)}"/>`).join("") + `</linearGradient>`);
    return `url(#${id})`;
  }
  fill(p: Path, paint: Paint, o: { alpha?: number; evenOdd?: boolean } = {}): void {
    if (!p.cmds.length) return;
    this.parts.push(`<path d="${this.d(p)}" fill="${this.paint(paint)}"${o.alpha !== undefined && o.alpha < 1 ? ` fill-opacity="${o.alpha}"` : ""}${o.evenOdd ? ` fill-rule="evenodd"` : ""}/>`);
  }
  stroke(p: Path, colour: Rgb, width: number, o: StrokeOptions = {}): void {
    if (!p.cmds.length) return;
    this.parts.push(`<path d="${this.d(p)}" fill="none" stroke="${css(colour)}" stroke-width="${f2(width)}"${o.cap === "round" ? ` stroke-linecap="round"` : ""}`
      + `${o.join === "round" ? ` stroke-linejoin="round"` : ""}${o.dash ? ` stroke-dasharray="${o.dash.map(f2).join(" ")}"` : ""}${o.alpha !== undefined && o.alpha < 1 ? ` stroke-opacity="${o.alpha}"` : ""}/>`);
  }
  text(x: number, y: number, s: string, size: number, font: Font, colour: Rgb, o: TextOptions = {}): void {
    if (!s) return;
    const h = o.hscale && o.hscale !== 1 ? o.hscale : 1;
    const at = h === 1 ? `x="${f2(x)}" y="${f2(y)}"` : `transform="translate(${f2(x)} ${f2(y)}) scale(${h} 1)" x="0" y="0"`;
    this.parts.push(`<text ${at} ${SVG_FONT[font]} font-size="${f2(size)}"${o.spacing ? ` letter-spacing="${f2(o.spacing)}"` : ""} fill="${css(colour)}"`
      + `${o.alpha !== undefined && o.alpha < 1 ? ` fill-opacity="${o.alpha}"` : ""} xml:space="preserve">${xml(s)}</text>`);
  }
  has(key: string): boolean { return !!this.hrefs[key]; }
  image(key: string, x: number, y: number, w: number, h: number, o: ImageOptions = {}): boolean {
    const href = this.hrefs[key];
    if (!href) return false;
    const style = o.multiply ? ` style="mix-blend-mode:multiply"` : "";
    this.parts.push(`<image href="${xml(href)}" x="${f2(x)}" y="${f2(y)}" width="${f2(w)}" height="${f2(h)}" preserveAspectRatio="xMidYMid ${o.fit === "cover" ? "slice" : "meet"}"`
      + `${o.alpha !== undefined && o.alpha < 1 ? ` opacity="${o.alpha}"` : ""}${style}/>`);
    return true;
  }
  clip(p: Path, evenOdd = false): void {
    const id = this.next("c");
    this.defs.push(`<clipPath id="${id}"><path d="${this.d(p)}"${evenOdd ? ` clip-rule="evenodd"` : ""}/></clipPath>`);
    this.parts.push(`<g clip-path="url(#${id})">`);
    this.open += 1;
  }
  restore(): void { if (this.open > 0) { this.parts.push("</g>"); this.open -= 1; } }
  /** the document; a label for assistive technology */
  toString(label = "Identity card"): string {
    while (this.open > 0) this.restore();
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${f2(this.W)} ${f2(this.H)}" role="img" aria-label="${xml(label)}"><defs>${this.defs.join("")}</defs>${this.parts.join("")}</svg>`;
  }
}
