/**
 * The identity cards' design (the University's redesign of 12 November 2026): the student card landscape in the University's navy,
 * the staff card portrait in its green, both with gold and red swooshes across the header and the foot, the crest on a white disc,
 * the University's name in serif capitals over MAKURDI, the holder's number on a red pill, the particulars beside icons, and the
 * session, validity and card number on the coloured foot; the back carries the barcode in a white panel, the conditions with their
 * marks, the verification QR, and the Chief Security Officer's signature. Drawn once on a Surface (lib/card-surface) — the PDF the
 * card desk prints and the SVG the desk shows are the same drawing. Units are tenths of a millimetre of an ID-1 card (856 × 540,
 * landscape; 540 × 856, portrait), y downward. Node-tested.
 */
import { hex, measure, path, Path, SvgSurface, type Font, type Gradient, type Rgb, type Surface } from "./card-surface.ts";
import { currentInstitution } from "./document/institution-cache.ts";

export type { Rgb } from "./card-surface.ts";
export type CardKind = "student" | "staff";

/** the card in units: landscape (the student card) and portrait (the staff card) */
export const LAND = { w: 856, h: 540 };
export const PORT = { w: 540, h: 856 };

/** what the front shows */
export interface CardFace {
  kind: CardKind;
  /** the holder's name, printed in capitals */
  name: string;
  /** the number on the red pill (the matriculation number, the staff number) */
  number: string;
  /** label/value pairs, two to a row: the left column takes the first of each pair, the right the second */
  fields: [string, string][];
  /** the foot's facts before the card number: [label, value] (the student card's validity; the staff card, none) */
  foot: [string, string][];
  /** the card's own number (ID NO.) */
  serial: string;
}

/** what the back shows */
export interface CardBack {
  kind: CardKind;
  /** what the barcode carries and prints under it */
  barcode: string;
  serial: string;
  terms?: string[];
  /** a label and a value beside the QR (the student card: "In an emergency" and the kin's phone) */
  aside?: [string, string];
  /** a place under the card number, with a pin (the staff card: where a found card is returned) */
  place?: string;
  /** who signs for the University — the title under the line, the name above it when held */
  signatory?: { title: string; name?: string | null };
}

/** the verification QR as modules (computed by the server from the card's signed check address); none on a preview */
export interface QrModules { size: number; dark: boolean[] }

/** the conditions every card carries on its back, in the University's words */
export const CONDITIONS = [
  "This ID card must always be in the owner's possession for identification at the gates, examination or wherever identification is necessary.",
  "Any alteration or erasure renders this card invalid.",
  "Loss must be reported immediately to the Chief Security Officer of the University.",
];

export const clean = (s: string | null | undefined) => (s ?? "")
  .replace(/[\u2018\u2019\u201A\u2032]/g, "'").replace(/[\u201C\u201D\u201E\u2033]/g, '"').replace(/[\u2013\u2014\u2212]/g, "-")
  // Ọlábísí → Olabisi, Ñandú → Nandu: the letters kept without their marks
  .normalize("NFD").replace(/\p{M}/gu, "")
  .replace(/[^\x20-\x7E]/g, " ").replace(/\s+/g, " ").trim();

/* ── colours ─────────────────────────────────────────────────────────────────────────────────────────────────────────────── */

const WHITE: Rgb = [1, 1, 1];
const lin = (x1: number, y1: number, x2: number, y2: number, ...stops: [number, string][]): Gradient =>
  ({ from: [x1, y1], to: [x2, y2], stops: stops.map(([o, c]) => [o, hex(c)] as [number, Rgb]) });

interface Palette {
  /** the header's and the strip's colour, dark to light */
  deep: [string, string, string];
  /** the foot's band, left to right */
  band: [string, string, string];
  /** the back's strip and foot (the staff card's are lit in the middle, its front's at the left by the crest) */
  backDeep: [string, string, string];
  backBand: [string, string, string];
  /** the tab (the student card's title), top to bottom */
  tab: [string, string];
  ink: Rgb; label: Rgb; icon: Rgb; value: Rgb; onBand: Rgb; rule: Rgb; pill: [string, string];
  title: string;
}
const PAL: Record<CardKind, Palette> = {
  student: {
    deep: ["#00215A", "#012C6B", "#03367D"], band: ["#012660", "#03397F", "#0A4FA3"], tab: ["#04449A", "#01245E"],
    backDeep: ["#00215A", "#012C6B", "#03367D"], backBand: ["#012660", "#03397F", "#0A4FA3"],
    ink: hex("#0F2158"), label: hex("#0C2C6E"), icon: hex("#0B2F6C"), value: hex("#181818"), onBand: hex("#D3E0F4"), rule: hex("#B8C0C8"),
    pill: ["#0A4FA3", "#02367F"], title: "STUDENT IDENTITY CARD",
  },
  staff: {
    deep: ["#02521F", "#01391A", "#002F17"], band: ["#014A24", "#00301B", "#002E1A"], tab: ["#0B5C2A", "#064220"],
    backDeep: ["#002F18", "#014022", "#003018"], backBand: ["#002E13", "#004117", "#002B13"],
    ink: hex("#073A1D"), label: hex("#14602A"), icon: hex("#12602A"), value: hex("#151515"), onBand: hex("#CFE8D7"), rule: hex("#BCC5BF"),
    pill: ["#0F6A31", "#08491F"], title: "STAFF IDENTITY CARD",
  },
};
const RED_PILL = (x: number, y: number, h: number) => lin(x, y, x, y + h, [0, "#D61C16"], [0.55, "#B80B07"], [1, "#9C0604"]);
const GOLD = (w: number) => lin(0, 0, w, 0, [0, "#C98B12"], [0.16, "#F4CF55"], [0.32, "#FFF0B4"], [0.48, "#E7B22C"], [0.66, "#F8D766"], [0.84, "#FFF3C2"], [1, "#D49617"]);
const RED = (w: number) => lin(0, 0, w, 0, [0, "#A80000"], [0.5, "#D9161B"], [1, "#B50202"]);
const GOLD_TEXT = hex("#F3C94B");

/* ── text ────────────────────────────────────────────────────────────────────────────────────────────────────────────────── */

/** the largest size, down to min, at which the text fits the width (letter-spacing scaled with the size) */
function fit(s: string, maxW: number, size: number, min: number, font: Font, em = 0): number {
  while (size > min && measure(s, size, font, em * size) > maxW) size -= 0.5;
  return size;
}
/** greedy wrap at a size; a word wider than the line is cut with an ellipsis */
function wrap(s: string, maxW: number, size: number, font: Font, em = 0): string[] {
  const out: string[] = [];
  let line = "";
  for (const w of s.split(/\s+/).filter(Boolean)) {
    const t = line ? `${line} ${w}` : w;
    if (line && measure(t, size, font, em * size) > maxW) { out.push(line); line = w; } else line = t;
  }
  if (line) out.push(line);
  return out.map((l) => { let x = l; while (x.length > 2 && measure(x, size, font, em * size) > maxW) x = `${x.slice(0, -2)}…`; return x; });
}
/** text set out from its left end, its centre or its right end */
function put(s: Surface, x: number, y: number, t: string, size: number, font: Font, colour: Rgb, o: { em?: number; align?: "left" | "center" | "right"; alpha?: number } = {}) {
  const sp = (o.em ?? 0) * size;
  const w = measure(t, size, font, sp);
  const x0 = o.align === "center" ? x - w / 2 : o.align === "right" ? x - w : x;
  s.text(x0, y, t, size, font, colour, { spacing: sp, alpha: o.alpha });
  return w;
}
/** the lines and the size for a value given a width: one line at the full size if it fits, else two (then three) at smaller sizes */
function lines(t: string, maxW: number, size: number, font: Font, maxLines = 3): { size: number; lines: string[] } {
  if (measure(t, size, font) <= maxW) return { size, lines: [t] };
  const one = fit(t, maxW, size, size * 0.86, font);
  if (measure(t, one, font) <= maxW) return { size: one, lines: [t] };
  for (const [n, k] of [[2, 0.88], [2, 0.8], [3, 0.78], [3, 0.7], [3, 0.64]] as [number, number][]) {
    if (n > maxLines) continue;
    const z = size * k;
    const l = wrap(t, maxW, z, font);
    if (l.length <= n && l.every((x) => !x.endsWith("…"))) return { size: z, lines: l };
  }
  const z = size * (maxLines >= 3 ? 0.64 : 0.8);
  const l = wrap(t, maxW, z, font);
  return { size: z, lines: l.length > maxLines ? [...l.slice(0, maxLines - 1), `${l[maxLines - 1].replace(/.{2}$/, "")}…`] : l };
}

/** the holder's name: one line, as large as fits down to min; else two lines at the two-line size, both at the size the wider needs
 *  (down to half); every word is printed — measured with the tracking it is drawn with — and a line that cannot fit even then ends in
 *  a visible ellipsis, never in silence */
const NAME_EM = -0.005;
function holderLines(name: string, maxW: number, size: number, min: number, two: number): { size: number; lines: string[] } {
  const w = (t: string, z: number) => measure(t, z, "sansBold", NAME_EM * z);
  const one = fit(name, maxW, size, min, "sansBold", NAME_EM);
  if (w(name, one) <= maxW) return { size: one, lines: [name] };
  const words = name.split(" ").filter(Boolean);
  // the break that evens the two lines out, at a comma where there is one
  let best: string[] = [name], score = Infinity;
  for (let i = 1; i < words.length; i++) {
    const a = words.slice(0, i).join(" "), b = words.slice(i).join(" ");
    const sc = Math.max(w(a, two), w(b, two)) - (a.endsWith(",") ? 40 : 0);
    if (sc < score) { score = sc; best = [a, b]; }
  }
  const z = Math.min(...best.map((l) => fit(l, maxW, two, two * 0.5, "sansBold", NAME_EM)));
  const cut = (l: string) => { let x = l; while (x.length > 2 && w(x, z) > maxW) x = `${x.slice(0, -2)}…`; return x; };
  return { size: z, lines: best.map((l) => (w(l, z) > maxW ? cut(l) : l)) };
}

/* ── icons, drawn in a 24-unit box ───────────────────────────────────────────────────────────────────────────────────────── */

export type IconName = "layers" | "cap" | "calendar" | "calendarLine" | "calendarCheck" | "idCard" | "bars" | "drop" | "people" | "briefcase" | "bank" | "pin" | "checkCircle" | "shieldCheck";

function icon(s: Surface, name: IconName, cx: number, cy: number, size: number, colour: Rgb) {
  const k = size / 24, dx = cx - size / 2, dy = cy - size / 2;
  const P = (p: Path) => p.placed(dx, dy, k);
  const fill = (p: Path, c: Rgb = colour, evenOdd = false) => s.fill(P(p), c, { evenOdd });
  const line = (p: Path, w: number, c: Rgb = colour) => s.stroke(P(p), c, w * k, { cap: "round", join: "round" });
  switch (name) {
    case "layers":
      fill(path().poly([[12, 2.4], [22.2, 7.4], [12, 12.4], [1.8, 7.4]]));
      fill(path().poly([[1.8, 11.4], [4.5, 10.1], [12, 13.8], [19.5, 10.1], [22.2, 11.4], [12, 16.4]]));
      fill(path().poly([[1.8, 15.8], [4.5, 14.5], [12, 18.2], [19.5, 14.5], [22.2, 15.8], [12, 20.8]]));
      break;
    case "cap":
      fill(path().M(5.4, 10.9).L(5.4, 15.4).C(5.4, 17.6, 8.4, 19.4, 12, 19.4).C(15.6, 19.4, 18.6, 17.6, 18.6, 15.4).L(18.6, 10.9).L(12, 14).Z());
      fill(path().poly([[12, 3.6], [23.6, 8.9], [12, 14.2], [0.4, 8.9]]));
      line(path().M(21.4, 9.6).L(21.4, 15.4), 1.3);
      fill(path().circle(21.4, 16.3, 1.25));
      break;
    case "calendar":
      fill(path().round(2.6, 4.4, 18.8, 17.4, 2.6));
      fill(path().round(4.4, 9.2, 15.2, 10.8, 1), WHITE);
      for (const yy of [10.9, 14.9]) for (const xx of [5.9, 9.9, 13.9]) fill(path().rect(xx, yy, 2.6, 2.4));
      fill(path().round(6.4, 2.2, 2.2, 4.6, 1.1)); fill(path().round(15.4, 2.2, 2.2, 4.6, 1.1));
      break;
    case "calendarLine":
      line(path().round(3, 4.8, 18, 16.6, 2.6), 1.7);
      line(path().M(3, 9.6).L(21, 9.6), 1.6);
      line(path().M(8, 2.8).L(8, 6.4), 1.7); line(path().M(16, 2.8).L(16, 6.4), 1.7);
      for (const yy of [12.3, 16]) for (const xx of [6.3, 9.8, 13.3, 16.8]) fill(path().rect(xx - 0.2, yy, 2, 2));
      break;
    case "calendarCheck":
      line(path().M(11.5, 21).L(5.6, 21).C(4.1, 21, 3, 19.9, 3, 18.4).L(3, 7.4).C(3, 5.9, 4.1, 4.8, 5.6, 4.8).L(18.4, 4.8).C(19.9, 4.8, 21, 5.9, 21, 7.4).L(21, 11.4), 1.7);
      line(path().M(3, 9.6).L(21, 9.6), 1.6);
      line(path().M(8, 2.8).L(8, 6.4), 1.7); line(path().M(16, 2.8).L(16, 6.4), 1.7);
      for (const [xx, yy] of [[6.2, 12.2], [9.6, 12.2], [13, 12.2], [6.2, 15.6], [9.6, 15.6]] as [number, number][]) fill(path().rect(xx, yy, 2, 2));
      line(path().circle(17.6, 17.6, 4.6), 1.6);
      line(path().M(15.5, 17.7).L(17, 19.1).L(19.7, 16.2), 1.5);
      break;
    case "idCard":
      line(path().round(1.6, 4.6, 20.8, 14.8, 2.2), 1.7);
      fill(path().circle(7.4, 10.4, 2.1));
      fill(path().M(4, 16.4).C(4.2, 14, 5.6, 13, 7.4, 13).C(9.2, 13, 10.6, 14, 10.8, 16.4).Z());
      line(path().M(13.2, 9.6).L(19, 9.6), 1.5); line(path().M(13.2, 12.4).L(19, 12.4), 1.5); line(path().M(13.2, 15.2).L(17.2, 15.2), 1.5);
      break;
    case "bars":
      fill(path().round(3, 13.4, 4.2, 7.6, 0.6)); fill(path().round(9.9, 8.6, 4.2, 12.4, 0.6)); fill(path().round(16.8, 3.4, 4.2, 17.6, 0.6));
      fill(path().round(1.6, 21.6, 20.8, 1.5, 0.5));
      break;
    case "drop":
      fill(path().M(12, 2.2).C(12, 2.2, 4.9, 10.5, 4.9, 15.1).C(4.9, 19.1, 8.1, 22.2, 12, 22.2).C(15.9, 22.2, 19.1, 19.1, 19.1, 15.1).C(19.1, 10.5, 12, 2.2, 12, 2.2).Z());
      line(path().M(8.6, 15.4).C(8.6, 17.4, 9.9, 18.9, 11.7, 19.2), 1.3, WHITE);
      break;
    case "people":
      fill(path().circle(12, 7.4, 3.3));
      fill(path().M(6.4, 19.6).C(6.4, 15.2, 8.9, 12.9, 12, 12.9).C(15.1, 12.9, 17.6, 15.2, 17.6, 19.6).Z());
      fill(path().circle(5, 9.2, 2.5)); fill(path().circle(19, 9.2, 2.5));
      fill(path().M(0.6, 18.6).C(0.6, 15.3, 2.5, 13.5, 5, 13.5).C(6, 13.5, 6.9, 13.8, 7.6, 14.3).C(6.3, 15.6, 5.6, 17, 5.5, 18.6).Z());
      fill(path().M(23.4, 18.6).C(23.4, 15.3, 21.5, 13.5, 19, 13.5).C(18, 13.5, 17.1, 13.8, 16.4, 14.3).C(17.7, 15.6, 18.4, 17, 18.5, 18.6).Z());
      break;
    case "briefcase":
      line(path().round(8.3, 3.6, 7.4, 5.6, 1.6), 1.9);
      fill(path().round(1.8, 7.2, 20.4, 13.6, 2.2));
      s.fill(P(path().rect(1.8, 12.4, 20.4, 1.1)), WHITE, { alpha: 0.9 });
      fill(path().round(10.3, 11.1, 3.4, 3.6, 0.6)); line(path().round(10.3, 11.1, 3.4, 3.6, 0.6), 0.9, WHITE);
      break;
    case "bank":
      fill(path().poly([[12, 1.8], [22.6, 7.2], [22.6, 8.9], [1.4, 8.9], [1.4, 7.2]]));
      for (const xx of [3.1, 7.9, 12.7, 17.5]) fill(path().rect(xx, 10.2, 3.4, 7.6));
      fill(path().rect(2.2, 18.4, 19.6, 1.6)); fill(path().rect(1.2, 20.6, 21.6, 2));
      break;
    case "pin":
      fill(path().M(12, 1.4).C(7.3, 1.4, 3.5, 5.2, 3.5, 9.8).C(3.5, 15.9, 12, 22.8, 12, 22.8).C(12, 22.8, 20.5, 15.9, 20.5, 9.8).C(20.5, 5.2, 16.7, 1.4, 12, 1.4).Z()
        .circle(12, 9.8, 3.3), colour, true);
      break;
    case "checkCircle":
      fill(path().circle(12, 12, 11));
      line(path().M(6.9, 12.4).L(10.4, 15.9).L(17.3, 8.7), 2.6, WHITE);
      break;
    case "shieldCheck":
      fill(path().M(12, 1.2).L(21.2, 4.8).L(21.2, 11).C(21.2, 16.7, 17.3, 21.2, 12, 23).C(6.7, 21.2, 2.8, 16.7, 2.8, 11).L(2.8, 4.8).Z());
      line(path().M(7.6, 12).L(10.8, 15.2).L(16.6, 8.9), 2.4, WHITE);
      break;
  }
}

/** the icon a field's label carries, card by card (the student card's faculty is a stack of layers, the staff card's a cap) */
const FIELD_ICON: Record<CardKind, Record<string, IconName>> = {
  student: { faculty: "layers", programme: "cap", admitted: "calendar", level: "bars", "blood group": "drop", graduates: "people", department: "layers" },
  staff: { rank: "briefcase", category: "people", unit: "layers", department: "layers", faculty: "cap", appointed: "calendar", "blood group": "drop", office: "bank" },
};
const FOOT_ICON = (label: string): IconName => (/valid/i.test(label) ? "calendarCheck" : /id/i.test(label) ? "idCard" : "calendarLine");

/* ── the parts both cards share ──────────────────────────────────────────────────────────────────────────────────────────── */

/** the card's ground: white going to a cool grey, the rounded corners clipping all that follows (restore() at the end) */
function ground(s: Surface, W: number, H: number) {
  const r = 31;
  s.clip(path().round(0, 0, W, H, r));
  s.fill(path().rect(0, 0, W, H), lin(0, 0, W * 0.6, H, [0, "#FFFFFF"], [0.55, "#FAFBFD"], [1, "#EEF2F6"]));
}
/** the crest, faint, as the card's watermark */
function watermark(s: Surface, cx: number, cy: number, d: number) {
  s.image("crest", cx - d / 2, cy - d / 2, d, d, { fit: "contain", alpha: 0.095 });
}
/** the crest on a white disc, with a white band under the ring for its motto ribbon (wider than the ring, as the crest is drawn) */
function crestDisc(s: Surface, cx: number, cy: number, r: number) {
  if (!s.has("crest")) return;
  // both drawn clockwise, so together they are one shape
  const shape = () => path().circle(cx, cy, r).round(cx - 0.9 * r, cy + 0.58 * r, 1.8 * r, 0.36 * r, 0.08 * r);
  s.fill(path().circle(cx, cy, r + 1.2), hex("#E9EEF4"));
  s.fill(shape(), WHITE);
  s.clip(shape());
  s.image("crest", cx - r * 0.96, cy - r * 0.98, r * 1.92, r * 1.96, { fit: "contain" });
  s.restore();
}
/** the University's name in serif capitals, wrapped to the width at the size (at most two lines; the last line, when it is the
 *  shorter, a tenth larger, as the design sets UNIVERSITY), then the city between gold rules starting at the name's left edge */
/* the design's serif: Times-Bold at nearly its own width */
const SERIF_H = 0.93;
function universityName(s: Surface, x: number, top: number, maxW: number, size: number, lead: number, placeY: number, placeSize: number, groupFrac: number) {
  const inst = currentInstitution();
  const full = clean(inst.name);
  const main = full.replace(/,.*$/, "").toUpperCase();
  const place = (clean(inst.city) || (full.includes(",") ? full.split(",")[1] : "")).trim().toUpperCase();
  if (!main) return;
  const wrapAt = (z: number) => {
    const out: string[] = [];
    let line = "";
    for (const w of main.split(/\s+/).filter(Boolean)) {
      const t = line ? `${line} ${w}` : w;
      if (line && measure(t, z, "serifBold", 0.01 * z, SERIF_H) > maxW) { out.push(line); line = w; } else line = t;
    }
    if (line) out.push(line);
    return out;
  };
  const sw = (l: string, z: number) => measure(l, z, "serifBold", 0.01 * z, SERIF_H);
  let z = size, ls = wrapAt(z);
  while ((ls.length > 2 || ls.some((l) => sw(l, z) > maxW)) && z > size * 0.5) { z -= 0.5; ls = wrapAt(z); }
  if (ls.length > 2) ls = [ls[0], ls.slice(1).join(" ")];
  const sizes = ls.map((l, i) => {
    if (i === 0 || ls.length < 2 || sw(l, z) >= sw(ls[0], z)) return z;
    let zz = z * 1.1;
    while (zz > z && sw(l, zz) > maxW) zz -= 0.25;
    return zz;
  });
  const blockW = Math.max(...ls.map((l, i) => sw(l, sizes[i])));
  ls.forEach((l, i) => {
    // a second pass a hair to the right reads as the heavier face of the design
    for (const d of [0, 0.35]) s.text(x + d, top + i * lead, l, sizes[i], "serifBold", WHITE, { spacing: 0.01 * sizes[i], hscale: SERIF_H });
  });
  if (!place) return;
  const gap = 12, minRule = 16;
  const groupW = Math.min(maxW, blockW * groupFrac);
  const ps = fit(place, groupW - 2 * (gap + minRule), placeSize, placeSize * 0.6, "sans", 0.42);
  const pw = measure(place, ps, "sans", 0.42 * ps);
  const gx = x, mid = gx + groupW / 2;
  put(s, mid, placeY, place, ps, "sans", WHITE, { em: 0.42, align: "center" });
  const ruleY = placeY - ps * 0.36;
  const gold: Gradient = { ...GOLD(groupW), from: [gx, 0], to: [gx + groupW, 0] };
  const left = mid - pw / 2 - gap - gx, right = gx + groupW - (mid + pw / 2 + gap);
  if (left > 2) s.fill(path().rect(gx, ruleY - 1.3, left, 2.6), gold);
  if (right > 2) s.fill(path().rect(mid + pw / 2 + gap, ruleY - 1.3, right, 2.6), gold);
}
/** the photograph, cropped to its frame, in a rounded border of the card's colour; a silhouette when none is held */
function photograph(s: Surface, x: number, y: number, w: number, h: number, r: number, colour: Rgb) {
  s.fill(path().round(x, y, w, h, r), colour);
  const i = 3.4;
  const inner = path().round(x + i, y + i, w - 2 * i, h - 2 * i, r - i * 0.7);
  s.fill(inner, WHITE);
  s.clip(inner);
  if (!s.image("photo", x + i, y + i, w - 2 * i, h - 2 * i, { fit: "cover" })) {
    s.fill(path().rect(x, y, w, h), lin(x, y, x, y + h, [0, "#E4EAF0"], [1, "#CCD6E0"]));
    const cx = x + w / 2;
    s.fill(path().circle(cx, y + h * 0.4, w * 0.2), hex("#9DAEBD"));
    s.fill(path().M(x + w * 0.14, y + h).C(x + w * 0.14, y + h * 0.7, x + w * 0.3, y + h * 0.62, cx, y + h * 0.62).C(x + w * 0.7, y + h * 0.62, x + w * 0.86, y + h * 0.7, x + w * 0.86, y + h).Z(), hex("#9DAEBD"));
  }
  s.restore();
}
/** text on a pill of a gradient; returns the pill's width */
function pill(s: Surface, cx: number, y: number, h: number, t: string, size: number, em: number, padX: number, paint: (x: number, y: number, h: number) => Gradient) {
  const w = measure(t, size, "sansBold", em * size) + 2 * padX;
  const x = cx - w / 2;
  s.fill(path().round(x, y + 1.4, w, h, h / 2), hex("#000000"), { alpha: 0.12 });
  s.fill(path().round(x, y, w, h, h / 2), paint(x, y, h));
  put(s, cx, y + h / 2 + size * 0.36, t, size, "sansBold", WHITE, { em, align: "center" });
  return w;
}
type ColumnZ = { label: number; value: number; vGap: number; lead: number; icon: number; maxGap: number };
/** a column's blocks at a size k: each an icon, a spaced label, the value under it (wrapped when long), with its height */
function layColumn(items: [string, string][], maxW: number, z: ColumnZ, k: number) {
  return items.map(([label, value]) => {
    const v = lines(clean(value) || "-", maxW, z.value * k, "sansBold");
    const L = clean(label).toUpperCase();
    return { L, ls: fit(L, maxW, z.label * k, z.label * k * 0.8, "sansBold", 0.1), v, h: z.label * k * 0.74 + z.vGap * k * (v.size / (z.value * k)) ** 0.5 + (v.lines.length - 1) * v.size * 1.1 + z.value * k * 0.24 };
  });
}
type Col = { items: [string, string][]; iconX: number; textX: number; maxW: number };
type Block = ReturnType<typeof layColumn>[number];
/** the particulars in rows across two columns, one size and one spacing for both: row by row, each row as tall as its taller value,
 *  so the two columns keep level when a value wraps. The size steps down (to four-fifths) when the rows need more room than there is,
 *  and up (to six-fifths) when fields are few — never so far that a value is cut short that printed in full at the usual size — the
 *  gaps then evening the room out (up to twice the usual gap) and what is left above and below shared, so no room is left where a
 *  field was */
function particulars(s: Surface, kind: CardKind, cols: Col[], top: number, bottom: number, z: ColumnZ) {
  const room = bottom - top;
  const at = (k: number) => {
    const blocks = cols.map((c) => layColumn(c.items, c.maxW, z, k));
    const rows = Math.max(...blocks.map((b) => b.length));
    const heights = Array.from({ length: rows }, (_, i) => Math.max(...blocks.map((b) => b[i]?.h ?? 0)));
    const cut = blocks.flat().filter((b) => b.v.lines.some((l) => l.endsWith("…"))).length;
    return { k, blocks, heights, cut, sum: heights.reduce((a, h) => a + h, 0) };
  };
  const need = (r: ReturnType<typeof at>, gap: number) => r.sum + gap * (r.heights.length - 1);
  let r = at(1);
  while (need(r, 6) > room && r.k > 0.8) r = at(r.k - 0.04);
  if (r.k === 1) {
    for (let next = at(1.04); next.k <= 1.2 + 1e-9 && next.cut <= r.cut && need(next, z.maxGap * next.k) <= room; next = at(next.k + 0.04)) r = next;
  }
  const rows = r.heights.length;
  const gap = rows > 1 ? Math.max(6, Math.min(z.maxGap * r.k * 2, (room - r.sum) / (rows - 1))) : 0;
  const lead = Math.max(0, (room - r.sum - gap * (rows - 1)) / 2);
  const tops: number[] = [];
  let y = top + lead;
  for (const h of r.heights) { tops.push(y); y += h + gap; }
  cols.forEach((c, ci) => column(s, kind, c.items, r.blocks[ci], c.iconX, c.textX, tops, z, r.k));
}
/** one column of particulars at a size, each block at its row's top */
function column(s: Surface, kind: CardKind, items: [string, string][], blocks: Block[], iconX: number, textX: number, tops: number[], z: ColumnZ, k: number) {
  const pal = PAL[kind];
  const zk = { ...z, label: z.label * k, value: z.value * k, vGap: z.vGap * k, icon: z.icon * Math.max(k, 0.9) };
  items.forEach(([label], i) => {
    const b = blocks[i];
    const lb = tops[i] + zk.label * 0.74;
    const name = FIELD_ICON[kind][clean(label).toLowerCase()];
    if (name) icon(s, name, iconX, lb + zk.vGap * 0.18, zk.icon, pal.icon);
    put(s, textX, lb, b.L, b.ls, "sansBold", pal.label, { em: 0.1 });
    b.v.lines.forEach((l, li) => s.text(textX, lb + zk.vGap * (b.v.size / zk.value) ** 0.5 + li * b.v.size * 1.1, l, b.v.size, "sansBold", pal.value));
  });
}
/** the left edge (as footFacts takes it) that centres a foot's only fact on the band — from its icon's left edge to its text's end
 *  (the staff card: the card number alone) */
function alone([label, value]: [string, string], W: number, iconDx: number, iconSize: number, textDx: number, labelSize: number, valueSize: number) {
  const L = clean(label).toUpperCase(), v = clean(value) || "-";
  const lead = iconDx - iconSize / 2;
  const span = textDx - lead + Math.max(measure(L, labelSize, "sans", 0.1 * labelSize), measure(v, valueSize, "sansBold"));
  return Math.max(0, (W - span) / 2 - lead);
}
/** the foot's facts in columns on the band: an outline icon, a spaced label, the value; white rules between the columns */
function footFacts(s: Surface, kind: CardKind, facts: [string, string][], bounds: number[], W: number, iconDx: number, textDx: number, labelY: number, valueY: number,
  z: { label: number; value: number; icon: number; ruleTop: number; ruleBottom: number }) {
  const pal = PAL[kind];
  facts.forEach(([label, value], i) => {
    const x0 = bounds[i], x1 = bounds[i + 1] ?? W;
    if (i > 0) s.stroke(path().M(x0, z.ruleTop).L(x0, z.ruleBottom), WHITE, 1.7, { alpha: 0.85 });
    icon(s, FOOT_ICON(label), x0 + iconDx, (labelY + valueY) / 2 - z.label * 0.2, z.icon, WHITE);
    const room = x1 - (x0 + textDx) - 30;
    const L = clean(label).toUpperCase();
    put(s, x0 + textDx, labelY, L, fit(L, room, z.label, z.label * 0.7, "sans", 0.1), "sans", pal.onBand, { em: 0.1 });
    const v = clean(value) || "-";
    s.text(x0 + textDx, valueY, v, fit(v, room, z.value, z.value * 0.62, "sansBold"), "sansBold", WHITE);
  });
}

/* ── the student card's front, landscape ─────────────────────────────────────────────────────────────────────────────────── */

export function drawStudentFront(s: Surface, f: CardFace) {
  const { w: W, h: H } = LAND, pal = PAL[f.kind];
  ground(s, W, H);
  watermark(s, 500, 300, 330);

  // the header: the red and gold swooshes under the navy, the tab with the card's title on the right
  s.fill(path().M(0, 138).C(110, 134, 220, 126, 330, 117).C(220, 131, 110, 150, 0, 163).Z(), RED(W));
  s.fill(path().M(0, 90).L(612, 86).L(612, 101.5).C(430, 102, 200, 124, 0, 141).Z(), GOLD(W));
  s.fill(path().M(640, 100).C(720, 106, 800, 122, 856, 128).L(856, 150).C(790, 140, 720, 120, 640, 103).Z(), GOLD(W));
  s.fill(path().M(682, 101).C(760, 103, 820, 103, 856, 104).L(856, 129).C(800, 121, 740, 107, 682, 101.5).Z(), RED(W));
  const deep = lin(0, 0, W, 120, [0, pal.deep[0]], [0.55, pal.deep[1]], [1, pal.deep[2]]);
  s.fill(path().M(0, 0).L(W, 0).L(W, 99).L(612, 98).C(430, 99, 200, 118, 0, 124.5).Z(), deep);
  // the tab
  const tab = path().M(578, 99).C(598, 99, 603, 31, 642, 31).L(W, 31).L(W, 99).Z();
  s.fill(tab, lin(0, 31, 0, 99, [0, pal.tab[0]], [1, pal.tab[1]]));
  s.stroke(path().M(572, 100).C(596, 99.5, 601, 31, 642, 31).L(W + 2, 31), hex("#F2C440"), 3.4);
  s.stroke(path().M(600, 100.5).L(W + 2, 100.5), hex("#E9B934"), 2.4);
  icon(s, "cap", 642, 64, 42, hex("#F4C542"));
  const [w1, ...rest] = pal.title.split(" ");
  const w2 = rest.join(" ");
  const tx = 680, room = W - tx - 18;
  put(s, tx, 61, w1, fit(w1, room, 23, 16, "sansBold", 0.14), "sansBold", WHITE, { em: 0.14 });
  put(s, tx, 86, w2, fit(w2, room, 19.5, 13, "sans", 0.09), "sans", WHITE, { em: 0.09 });

  crestDisc(s, 95, 58, 49);
  s.stroke(path().M(170, 20).L(170, 95), WHITE, 1.7, { alpha: 0.85 });
  universityName(s, 191, 37.5, 603 - 191, 27, 30.5, 92.5, 15.5, 0.62);

  // the photograph and the holder
  photograph(s, 38, 152, 209, 278, 15, hex("#1E458C"));
  s.stroke(path().M(263, 148).L(263, 436), pal.ink, 1.9);
  const x = 292, maxW = W - x - 24;
  const nl = holderLines(clean(f.name).toUpperCase(), maxW, 33, 24, 27);
  let y = 172;
  for (const l of nl.lines) { s.text(x, y, l, nl.size, "sansBold", pal.ink, { spacing: -0.005 * nl.size }); y += nl.size * 1.08; }
  const pillY = y - nl.size * 1.08 + 13;
  // a card is keyed on the number; a preview of a student without one says so rather than show an empty pill
  const num = clean(f.number) || "NUMBER NOT YET ISSUED";
  const ps = fit(num, maxW - 52, clean(f.number) ? 24 : 17, 14, "sansBold", 0.06);
  const pw = measure(num, ps, "sansBold", 0.06 * ps) + 50;
  pill(s, 283 + pw / 2, pillY, 31.5, num, ps, 0.06, 25, RED_PILL);

  // the particulars, two columns with a rule between
  const left = f.fields.filter((_, i) => i % 2 === 0), right = f.fields.filter((_, i) => i % 2 === 1);
  const z = { label: 15, value: 21.5, vGap: 22.5, lead: 21.5, icon: 34, maxGap: 24 };
  const gTop = pillY + 31.5 + 17.5;
  s.stroke(path().M(585, gTop + 2).L(585, 416), pal.rule, 1.4);
  particulars(s, f.kind, [{ items: left, iconX: 304, textX: 343, maxW: 585 - 343 - 12 }, { items: right, iconX: 643, textX: 681, maxW: W - 681 - 16 }], gTop, 422, z);

  // the foot: the gold swoosh over the navy band, the facts on it
  s.fill(path().M(0, 447).C(150, 439, 330, 462, 512, 462.5).C(640, 463, 760, 440, 856, 403).L(856, 540).L(0, 540).Z(), GOLD(W));
  s.fill(path().M(0, 464.5).C(150, 450, 330, 468, 512, 468.5).C(650, 469, 770, 452, 856, 423).L(856, 540).L(0, 540).Z(),
    lin(0, 0, W, 0, [0, pal.band[0]], [0.55, pal.band[1]], [1, pal.band[2]]));
  s.fill(path().M(560, 540).C(700, 520, 790, 470, 856, 440).L(856, 540).Z(), hex("#FFFFFF"), { alpha: 0.05 });
  const facts: [string, string][] = [...f.foot, ["ID No.", f.serial]];
  const bounds = facts.length === 3 ? [0, 248, 541] : facts.length === 1 ? [alone(facts[0], W, 57, 36, 99, 16.5, 23)] : facts.map((_, i) => (W * i) / facts.length);
  footFacts(s, f.kind, facts, bounds, W, 57, 99, 485, 511, { label: 16.5, value: 23, icon: 36, ruleTop: 474, ruleBottom: 516 });
  s.restore();
  s.stroke(path().round(0.5, 0.5, W - 1, H - 1, 30.5), hex("#D3DAE2"), 1);
}

/* ── the staff card's front, portrait ────────────────────────────────────────────────────────────────────────────────────── */

export function drawStaffFront(s: Surface, f: CardFace) {
  const { w: W, h: H } = PORT, pal = PAL[f.kind];
  ground(s, W, H);
  watermark(s, 270, 470, 440);

  // the header: green over gold over red, sweeping down at the left
  s.fill(path().M(0, 205).C(45, 192, 95, 178, 155, 166).C(100, 186, 50, 214, 0, 252).Z(), RED(W));
  s.fill(path().M(0, 120).L(540, 100).L(540, 157).C(500, 128, 440, 125, 380, 130).C(260, 148, 120, 154, 60, 179).C(30, 189, 10, 202, 0, 216).Z(), GOLD(W));
  s.fill(path().M(0, 0).L(W, 0).L(W, 133).C(500, 109, 440, 112, 380, 122).C(260, 142, 120, 148, 60, 167).C(30, 177, 10, 189, 0, 201).Z(),
    lin(0, 0, W, 160, [0, pal.deep[0]], [0.55, pal.deep[1]], [1, pal.deep[2]]));
  crestDisc(s, 95, 74, 57);
  s.stroke(path().M(177, 26).L(177, 118), WHITE, 1.7, { alpha: 0.85 });
  universityName(s, 198, 48.5, W - 198 - 18, 28, 31.5, 111, 14.5, 0.84);
  const ts = fit(pal.title, 380, 25, 18, "sansBold", 0.06);
  pill(s, W / 2, 159, 36.5, pal.title, ts, 0.06, 32, RED_PILL);

  // the photograph and the holder, centred; a name of two lines takes its room from the photograph
  const maxW = W - 40;
  const nl = holderLines(clean(f.name).toUpperCase(), maxW, 40, 27, 29);
  const extra = (nl.lines.length - 1) * nl.size * 1.06;
  const ph = 219 - extra, pw0 = ph * (190 / 219);
  photograph(s, W / 2 - pw0 / 2, 213, pw0, ph, 13, hex("#1C5A33"));
  let y = 213 + ph + 45;
  for (const l of nl.lines) { put(s, W / 2, y, l, nl.size, "sansBold", pal.ink, { em: -0.005, align: "center" }); y += nl.size * 1.06; }
  const num = clean(f.number) || "NUMBER NOT YET ISSUED";
  const ps = fit(num, 300, clean(f.number) ? 27 : 17, 14, "sansBold", 0.08);
  const pw = pill(s, W / 2, 488, 32, num, ps, 0.08, 26, RED_PILL);
  const ruleY = 504, gap = 20;
  s.stroke(path().M(Math.max(40, W / 2 - pw / 2 - gap - 104), ruleY).L(W / 2 - pw / 2 - gap, ruleY), pal.icon, 1.4);
  s.stroke(path().M(W / 2 + pw / 2 + gap, ruleY).L(Math.min(W - 40, W / 2 + pw / 2 + gap + 104), ruleY), pal.icon, 1.4);

  // the particulars
  const left = f.fields.filter((_, i) => i % 2 === 0), right = f.fields.filter((_, i) => i % 2 === 1);
  const z = { label: 15, value: 21.8, vGap: 22.6, lead: 21, icon: 32, maxGap: 22 };
  s.stroke(path().M(286, 541).L(286, 740), pal.rule, 1.3);
  particulars(s, f.kind, [{ items: left, iconX: 45, textX: 79, maxW: 286 - 79 - 10 }, { items: right, iconX: 329, textX: 365, maxW: W - 365 - 12 }], 538, 744, z);

  // the foot
  s.fill(path().M(0, 775).C(60, 764, 160, 764, 250, 773).C(360, 783, 470, 752, 540, 730).L(540, 856).L(0, 856).Z(), GOLD(W));
  s.fill(path().M(0, 792).C(50, 775, 150, 770, 250, 778).C(360, 785, 470, 765, 540, 753).L(540, 856).L(0, 856).Z(),
    lin(0, 0, W, 0, [0, pal.band[0]], [0.55, pal.band[1]], [1, pal.band[2]]));
  const facts: [string, string][] = [...f.foot, ["ID No.", f.serial]];
  const bounds = facts.length === 2 ? [0, 263] : facts.length === 1 ? [alone(facts[0], W, 48, 31, 80, 15, 21)] : facts.map((_, i) => (W * i) / facts.length);
  footFacts(s, f.kind, facts, bounds, W, 48, 80, 808, 832, { label: 15, value: 21, icon: 31, ruleTop: 792, ruleBottom: 836 });
  s.restore();
  s.stroke(path().round(0.5, 0.5, W - 1, H - 1, 30.5), hex("#D3DAE2"), 1);
}

/* ── the back, landscape (the student card) or portrait (the staff card) ─────────────────────────────────────────────────── */

/* Code 128-B */
const C128 = [
  "212222", "222122", "222221", "121223", "121322", "131222", "122213", "122312", "132212", "221213",
  "221312", "231212", "112232", "122132", "122231", "113222", "123122", "123221", "223211", "221132",
  "221231", "213212", "223112", "312131", "311222", "321122", "321221", "312212", "322112", "322211",
  "212123", "212321", "232121", "111323", "131123", "131321", "112313", "132113", "132311", "211313",
  "231113", "231311", "112133", "112331", "132131", "113123", "113321", "133121", "313121", "211331",
  "231131", "213113", "213311", "213131", "311123", "311321", "331121", "312113", "312311", "332111",
  "314111", "221411", "431111", "111224", "111422", "121124", "121421", "141122", "141221", "112214",
  "112412", "122114", "122411", "142112", "142211", "241211", "221114", "413111", "241112", "134111",
  "111242", "121142", "121241", "114212", "124112", "124211", "411212", "421112", "421211", "212141",
  "214121", "412121", "111143", "111341", "131141", "114113", "114311", "411113", "411311", "113141",
  "114131", "311141", "411131", "211412", "211214", "211232", "2331112",
];
/** the bar and space widths, in modules, of the text in Code 128-B (start, data, check, stop) */
export function c128Runs(text: string): number[] {
  const vals: number[] = [104];
  let sum = 104;
  for (let i = 0; i < text.length; i++) {
    let v = text.charCodeAt(i) - 32;
    if (v < 0 || v > 94) v = 63;
    vals.push(v); sum += v * (i + 1);
  }
  vals.push(sum % 103); vals.push(106);
  const runs: number[] = [];
  for (const val of vals) for (const ch of C128[val]) runs.push(Number(ch));
  return runs;
}
function barcode(s: Surface, text: string, x: number, y: number, w: number, h: number) {
  const runs = c128Runs(text);
  const units = runs.reduce((a, c) => a + c, 0);
  const u = w / units;
  let bx = x, dark = true;
  const bars = path();
  for (const r of runs) { if (dark) bars.rect(bx, y, r * u, h); bx += r * u; dark = !dark; }
  s.fill(bars, hex("#0B0B0B"));
}
function qr(s: Surface, q: QrModules | null | undefined, x: number, y: number, d: number, colour: Rgb) {
  s.fill(path().rect(x, y, d, d), WHITE);
  if (!q) {
    s.stroke(path().rect(x + 3, y + 3, d - 6, d - 6), colour, 1.4, { dash: [6, 5] });
    put(s, x + d / 2, y + d / 2 - 3, "QR ON", d * 0.12, "sansBold", colour, { align: "center", em: 0.08 });
    put(s, x + d / 2, y + d / 2 + d * 0.13, "THE PRINT", d * 0.12, "sansBold", colour, { align: "center", em: 0.08 });
    return;
  }
  const cell = d / q.size;
  const dots = path();
  for (let r = 0; r < q.size; r++) for (let c = 0; c < q.size; c++) if (q.dark[r * q.size + c]) dots.rect(x + c * cell, y + r * cell, cell + 0.05, cell + 0.05);
  s.fill(dots, hex("#0B0B0B"));
}
/** the signature fitted above the line, the name (when held) and the title under it, centred on cx */
function signature(s: Surface, cx: number, lineY: number, lineW: number, imgH: number, pal: Palette, b: CardBack, z: { name: number; title: number; nameDy: number; titleDy: number; room: number }) {
  s.image("signature", cx - lineW * 0.36, lineY - imgH - 2, lineW * 0.72, imgH, { fit: "contain", multiply: true });
  s.stroke(path().M(cx - lineW / 2, lineY).L(cx + lineW / 2, lineY), pal.ink, 1.5);
  const name = clean(b.signatory?.name ?? "");
  const title = clean(b.signatory?.title ?? "Chief Security Officer").toUpperCase();
  const ty = lineY + z.titleDy - (name ? 0 : z.nameDy);
  if (name) {
    const ns = fit(name, z.room, z.name, z.name * 0.5, "sansBold");
    let t = name;
    while (t.length > 2 && measure(t, ns, "sansBold") > z.room) t = `${t.slice(0, -2)}…`;
    put(s, cx, lineY + z.nameDy, t, ns, "sansBold", pal.ink, { align: "center" });
  }
  put(s, cx, ty, title, fit(title, lineW + 20, z.title, z.title * 0.7, "sans", 0.16), "sans", hex("#2A2A2A"), { em: 0.16, align: "center" });
}
/** the conditions, each with its mark; returns the y under the last */
function conditions(s: Surface, terms: string[], mark: IconName, colour: Rgb, iconX: number, textX: number, maxW: number, top: number, size: number, lead: number, itemGap: number, iconD: number) {
  let y = top;
  for (const t of terms) {
    const ls = wrap(t, maxW, size, "sans");
    icon(s, mark, iconX, y - size * 0.36, iconD, colour);
    for (const l of ls) { s.text(textX, y, l, size, "sans", hex("#1E1E1E")); y += lead; }
    y += itemGap;
  }
  return y - lead - itemGap;
}

export function drawCardBack(s: Surface, b: CardBack, landscape: boolean, q: QrModules | null) {
  const { w: W, h: H } = landscape ? LAND : PORT;
  const pal = PAL[b.kind];
  ground(s, W, H);
  const deep = lin(0, 0, W, 90, [0, pal.backDeep[0]], [0.5, pal.backDeep[1]], [1, pal.backDeep[2]]);
  const band = lin(0, 0, W, 0, [0, pal.backBand[0]], [0.5, pal.backBand[1]], [1, pal.backBand[2]]);
  const terms = (b.terms ?? CONDITIONS).map(clean).filter(Boolean);
  const caption = clean(b.barcode);
  if (landscape) {
    watermark(s, 428, 300, 320);
    // the strip: gold under the ends of a navy band that dips at the middle-left
    s.fill(path().M(0, 50).L(340, 36).C(200, 47, 80, 62, 0, 88).Z(), GOLD(W));
    s.fill(path().M(640, 44).C(740, 50, 810, 58, 856, 62).L(856, 86).C(800, 78, 720, 60, 640, 47).Z(), GOLD(W));
    s.fill(path().M(0, 0).L(W, 0).L(W, 70).C(760, 52, 560, 41, 300, 39).C(180, 39, 90, 46, 0, 66).Z(), deep);
    const st = "PROPERTY OF THE UNIVERSITY - NOT TRANSFERABLE";
    const ss = fit(st, 560, 22.5, 15, "sansBold", 0.075);
    const sw = put(s, W / 2, 30.5, st, ss, "sansBold", WHITE, { em: 0.075, align: "center" });
    for (const side of [-1, 1]) {
      const x0 = W / 2 + side * (sw / 2 + 20), x1 = x0 + side * 54;
      s.fill(path().rect(Math.min(x0, x1), 23.2, 54, 2.6), hex("#F2C440"));
    }
    // the barcode in its white panel, the number under the bars
    for (const [d, a] of [[6, 0.05], [4, 0.06], [2, 0.08]] as [number, number][]) s.fill(path().round(131 - d / 2, 64 + d, 595 + d, 105, 11), hex("#1B2733"), { alpha: a });
    s.fill(path().round(131, 64, 595, 105, 11), WHITE);
    s.stroke(path().round(131, 64, 595, 105, 11), hex("#E2E7EC"), 1);
    if (caption) {
      barcode(s, caption, 158, 72, 542, 62);
      put(s, W / 2, 161.5, caption, fit(caption, 540, 27, 16, "sansBold", 0.26), "sansBold", hex("#141414"), { em: 0.26, align: "center" });
    } else put(s, W / 2, 124, "THE BARCODE IS PRINTED WITH THE NUMBER", 16, "sansBold", hex("#7A8590"), { em: 0.08, align: "center" });
    // CONDITIONS
    const cw = pill(s, W / 2, 185, 32, "CONDITIONS", 21, 0.13, 32, (x, y, h) => lin(x, y, x, y + h, [0, pal.pill[0]], [1, pal.pill[1]]));
    s.stroke(path().M(135, 201).L(W / 2 - cw / 2 - 14, 201), pal.ink, 1.6);
    s.stroke(path().M(W / 2 + cw / 2 + 14, 201).L(722, 201), pal.ink, 1.6);
    const end = conditions(s, terms, "checkCircle", hex("#0A3377"), 94, 124, 830 - 124, 239, 18.2, 21.5, 6, 22);
    // the QR, the card number and the emergency contact; the signature on the right
    const bottomTop = Math.max(end + 22, 340);
    const qd = Math.max(84, Math.min(124, 472 - bottomTop - 4));
    const qy = Math.min(bottomTop, 470 - qd);
    qr(s, q, 80, qy, qd, pal.ink);
    const mid = qy + qd / 2;
    s.stroke(path().M(226, mid - 46).L(226, mid + 46), pal.ink, 2);
    const asideX = 242, serialSize = fit(clean(b.serial), 548 - asideX - 20, 21.5, 14, "sansBold");
    s.text(asideX, mid - 20, clean(b.serial), serialSize, "sansBold", hex("#111111"));
    if (b.aside) {
      s.text(asideX, mid + 2, clean(b.aside[0]), 18.5, "sans", hex("#222222"));
      s.text(asideX, mid + 26, clean(b.aside[1]) || "-", fit(clean(b.aside[1]) || "-", 548 - asideX - 20, 21, 14, "sansBold"), "sansBold", hex("#111111"));
    }
    signature(s, 677, Math.min(qy + 72, 418), 258, 68, pal, b, { name: 22.5, title: 16, nameDy: 22, titleDy: 44, room: 2 * (W - 18 - 677) });
    // the foot: gold and red over the navy band
    s.fill(path().M(0, 471).C(200, 488, 450, 516, 620, 519).C(720, 517, 800, 490, 856, 478).L(856, 540).L(0, 540).Z(), GOLD(W));
    s.fill(path().M(540, 517).C(680, 507, 790, 475, 856, 456).L(856, 478).C(790, 493, 680, 513, 540, 518).Z(), RED(W));
    s.fill(path().M(0, 487).C(200, 500, 450, 522, 620, 523.5).C(720, 523, 800, 512, 856, 497).L(856, 540).L(0, 540).Z(), band);
  } else {
    watermark(s, 270, 515, 420);
    // the strip: green over a gold sweep, its two lines in gold
    s.fill(path().M(0, 60).L(540, 40).L(540, 62).C(520, 70, 490, 82, 450, 86).C(380, 92, 300, 72, 200, 70).C(110, 72, 40, 90, 0, 113).Z(), GOLD(W));
    s.fill(path().M(0, 0).L(W, 0).L(W, 50).C(520, 62, 490, 76, 450, 80).C(380, 86, 280, 68, 180, 64).C(110, 62, 40, 70, 0, 88).Z(), deep);
    const l1 = "PROPERTY OF THE UNIVERSITY", l2 = "NOT TRANSFERABLE";
    const ss = fit(l1, W - 70, 19.5, 13, "sansBold", 0.13);
    put(s, W / 2, 30, l1, ss, "sansBold", GOLD_TEXT, { em: 0.13, align: "center" });
    put(s, W / 2, 54, l2, ss, "sansBold", GOLD_TEXT, { em: 0.13, align: "center" });
    for (const [d, a] of [[6, 0.05], [4, 0.06], [2, 0.08]] as [number, number][]) s.fill(path().round(70 - d / 2, 96 + d, 402 + d, 108, 12), hex("#1B2A22"), { alpha: a });
    s.fill(path().round(70, 96, 402, 108, 12), WHITE);
    s.stroke(path().round(70, 96, 402, 108, 12), hex("#E2E7EC"), 1);
    if (caption) {
      const runs = c128Runs(caption).reduce((a, c) => a + c, 0);
      const bw = Math.min(334, runs * 3.6);
      barcode(s, caption, W / 2 - bw / 2, 107, bw, 84);
      put(s, W / 2, 232, caption, fit(caption, 440, 31, 18, "sansBold", 0.15), "sansBold", pal.ink, { em: 0.15, align: "center" });
    } else put(s, W / 2, 156, "THE BARCODE IS PRINTED WITH THE NUMBER", 14, "sansBold", hex("#7A8590"), { em: 0.06, align: "center" });
    const cw = pill(s, W / 2, 253, 29.5, "CONDITIONS", 19.5, 0.12, 30, (x, y, h) => lin(x, y, x, y + h, [0, pal.pill[0]], [1, pal.pill[1]]));
    s.stroke(path().M(70, 267.5).L(W / 2 - cw / 2 - 10, 267.5), pal.icon, 1.5);
    s.stroke(path().M(W / 2 + cw / 2 + 10, 267.5).L(472, 267.5), pal.icon, 1.5);
    const end = conditions(s, terms, "shieldCheck", pal.icon, 51, 78, W - 78 - 30, 308, 17.6, 21, 6, 26);
    // the QR in its green frame, the card number, where to return it, the signature; laid up from the foot
    const titleY = 787, lineY = 738, placeY = 650, serialY = 618;
    const qBottom = 593;
    const qd = Math.max(96, Math.min(150, qBottom - (end + 18)));
    const qx = W / 2 - qd / 2, qy = qBottom - qd;
    s.fill(path().round(qx - 2, qy - 2, qd + 4, qd + 4, 11), WHITE);
    s.stroke(path().round(qx, qy, qd, qd, 10), pal.icon, 2.8);
    // four modules of white between the symbol and the frame, as the QR standard asks
    const inset = q ? Math.max(9, (1.4 + (4 * qd) / q.size) / (1 + 8 / q.size)) : 9;
    qr(s, q, qx + inset, qy + inset, qd - 2 * inset, pal.ink);
    put(s, W / 2, serialY, clean(b.serial), fit(clean(b.serial), W - 80, 20, 14, "sans", 0.01), "sans", hex("#111111"), { em: 0.01, align: "center" });
    if (b.place) {
      const t = clean(b.place), ts = fit(t, W - 110, 22, 15, "sansBold");
      const tw = measure(t, ts, "sansBold");
      const gx = W / 2 - (tw + 32) / 2;
      icon(s, "pin", gx + 11, placeY - ts * 0.36, 26, pal.icon);
      s.text(gx + 32, placeY, t, ts, "sansBold", pal.icon);
    } else if (b.aside) {
      put(s, W / 2, placeY, `${clean(b.aside[0])}: ${clean(b.aside[1]) || "-"}`, 18, "sans", hex("#222222"), { align: "center" });
    }
    signature(s, W / 2, lineY, 318, 72, pal, b, { name: 25, title: 17.5, nameDy: 27, titleDy: titleY - lineY, room: W - 40 });
    s.fill(path().M(0, 784).C(100, 790, 200, 825, 330, 834).C(420, 836, 490, 812, 540, 794).L(540, 856).L(0, 856).Z(), GOLD(W));
    s.fill(path().M(320, 836).C(420, 828, 480, 790, 540, 765).L(540, 789).C(490, 806, 420, 831, 320, 837).Z(), RED(W));
    s.fill(path().M(0, 801).C(100, 806, 200, 830, 330, 839).C(420, 842, 490, 826, 540, 806).L(540, 856).L(0, 856).Z(), band);
  }
  s.restore();
  s.stroke(path().round(0.5, 0.5, W - 1, H - 1, 30.5), hex("#D3DAE2"), 1);
}

/* ── the screen's copy ───────────────────────────────────────────────────────────────────────────────────────────────────── */

/** the card as SVG for the desk's screen: the same drawing as the print, the photograph, the crest and the signature by address */
export function cardSvg(side: "front" | "back", card: { face: CardFace; back: CardBack }, hrefs: { photo?: string | null; crest?: string | null; signature?: string | null }, id: string, q: QrModules | null = null): string {
  const landscape = card.face.kind === "student";
  const { w, h } = landscape ? LAND : PORT;
  const s = new SvgSurface(w, h, hrefs, id);
  if (side === "front") (landscape ? drawStudentFront : drawStaffFront)(s, card.face);
  else drawCardBack(s, card.back, landscape, q);
  return s.toString(side === "front" ? `Front of the ${card.face.kind} identity card` : `Back of the ${card.face.kind} identity card`);
}
