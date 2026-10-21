/**
 * The identity card drawn into a PDF: the student card landscape, the staff card portrait; both share every part below.
 * V622 (the University's review of the printed cards): the University's name bolder, with the card's title — STUDENT IDENTITY CARD
 * or STAFF IDENTITY CARD — under it (no tag under the photograph); the student card in the University's blue, the staff card in its
 * green, so the two are told apart at a glance; the photograph and the text larger, the fields spread to fill the card; the back's
 * write-ups centred; the back signed for the University by the Chief Security Officer, with the signature the Directorate of ICT
 * uploads above the line. The colours, the faded crest, the red|green rule, the barcode and the verification QR are as before.
 */
import { Page, type Image } from "@/lib/pdf-write";
import { currentInstitution } from "./document/institution-cache.ts";
import { qrMatrix } from "@/lib/qr";

export type Rgb = [number, number, number];
const hex = (h: string): Rgb => [parseInt(h.slice(1, 3), 16) / 255, parseInt(h.slice(3, 5), 16) / 255, parseInt(h.slice(5, 7), 16) / 255];

/* the card's palette, as the stylesheet names it */
export const C = {
  ink: hex("#17202A"), head: hex("#0E3F55"), headSub: hex("#9EC6DA"), red: hex("#ED1B23"), green: hex("#0CA54E"),
  tag: hex("#D6151C"), number: hex("#B01218"), label: hex("#5E6B78"), foot: hex("#56636E"), terms: hex("#35424D"),
  strip: hex("#17202A"), stripText: hex("#C9D6DE"), border: hex("#C7D2DA"), photoBorder: hex("#B9C8D2"),
  line: hex("#E4EAEF"), sig: hex("#7D8B96"), white: [1, 1, 1] as Rgb, face: hex("#FFFFFF"), back: hex("#FBFCFD"),
  shadow: hex("#102634"),
};

/** V622: whose card it is — the student card in the University's blue, the staff card in its green */
export type CardKind = "student" | "staff";
export const KIND: Record<CardKind, { head: Rgb; headSub: Rgb; strip: Rgb; tint: Rgb; title: string }> = {
  student: { head: hex("#0E3F55"), headSub: hex("#BFDCEB"), strip: hex("#0E3F55"), tint: hex("#0E3F55"), title: "STUDENT IDENTITY CARD" },
  staff: { head: hex("#0B5D3B"), headSub: hex("#BFE6CF"), strip: hex("#0B5D3B"), tint: hex("#0B5D3B"), title: "STAFF IDENTITY CARD" },
};

/** the card's CSS pixel size (85.6 × 54 mm at 96 dpi) — every measure below is in these pixels, scaled */
export const CARD_PX = { w: 323.5, h: 204.1 };

export const clean = (s: string | null | undefined) => (s ?? "").replace(/[^\x20-\x7E]/g, " ").replace(/\s+/g, " ").trim();
/** the width of a run of text, by character class: capitals are wide, lower case narrower, spaces and
 *  punctuation narrower still — Helvetica's proportions, which is what the card is set in */
export const wText = (s: string, size: number, font: "F1" | "F2" | "F3" = "F1", spacing = 0) => {
  const bold = font === "F2" || font === "F3";
  let w = 0;
  for (const ch of s) {
    if (/[A-Z]/.test(ch)) w += bold ? 0.72 : 0.68;
    else if (/[a-z]/.test(ch)) w += bold ? 0.56 : 0.52;
    else if (/[0-9]/.test(ch)) w += 0.56;
    else if (/[ .,:;'\-]/.test(ch)) w += 0.3;
    else w += 0.55;
  }
  return w * size + Math.max(0, s.length - 1) * spacing;
};

/** greedy wrap by the same width heuristic the writer uses */
export function wrap(s: string, maxWidth: number, size: number, font: "F1" | "F2" = "F1"): string[] {
  const out: string[] = [];
  let line = "";
  for (const w of s.split(/\s+/)) {
    const t = (line + " " + w).trim();
    if (wText(t, size, font) > maxWidth && line) { out.push(line); line = w; } else line = t;
  }
  if (line) out.push(line);
  return out;
}

/* Code 128-B, as the screen's Barcode() draws it */
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
function c128Runs(text: string): number[] {
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

/** the two conditions every card carries on its back, in the University's words */
export const CONDITIONS = [
  "This ID card must always be in the owner's possession for identification at the gates, examination or wherever identification is necessary.",
  "Any alteration or erasure renders this card invalid. Loss must be reported immediately to the Chief Security Officer of the University.",
];

export interface CardFace {
  /** V622: whose card — the colours and the title under the University's name */
  kind: CardKind;
  /** the holder's name, printed in capitals */
  name: string;
  /** the number under the name, in the card's red */
  number: string;
  /** label/value pairs laid out two to a row (the left column wider) */
  fields: [string, string][];
  /** the foot's left text, with the bold parts marked as [text, bold] */
  foot: [string, boolean][];
  serial: string;
}
export interface CardBack {
  /** V622: whose card — the strip's colour */
  kind: CardKind;
  barcode: string;
  serial: string;
  terms?: string[];
  /** the small block beside (or under) the QR: a label and a value (e.g. "In an emergency" / the kin's phone) */
  aside?: [string, string];
  /** what the QR carries: the card's signed check address (V439); without one, the serial */
  qr?: string;
  /** V622: who signs for the University — the title under the line, the name above it when held, and the signature image */
  signatory?: { title: string; name?: string | null; image?: Image | null };
}

/** the card's canvas: rounded, bordered, shadowed and clipped */
function canvas(p: Page, x0: number, y0: number, W: number, H: number, k: number, fill: Rgb) {
  const r = 12.1 * k;   // 3.2 mm
  for (const d of [1, 2, 3]) p.roundRect(x0, y0 - d, W, H, r, C.shadow, undefined, 0, true);
  p.roundRect(x0, y0, W, H, r, fill, C.border, 0.8);
  p.clipRound(x0, y0, W, H, r);
}

/** a faint diagonal tint in the card's colour, the way a real card is printed */
function guilloche(p: Page, x0: number, y0: number, W: number, H: number, tint: Rgb) {
  const rgb = tint.map((v) => v.toFixed(3)).join(" ");
  for (let d = -H; d < W + H; d += 5) {
    p.ops.push(`q /GS5 gs ${rgb} RG 0.4 w ${(x0 + d).toFixed(2)} ${y0.toFixed(2)} m ${(x0 + d + H * 0.78).toFixed(2)} ${(y0 + H).toFixed(2)} l S Q`);
  }
}

/** the header band: the crest, the University's name in bold serif capitals and the card's title under it; returns its height */
function header(p: Page, x0: number, top: number, W: number, k: number, crest: Image | null, kind: CardKind, twoLines: boolean): number {
  const pal = KIND[kind];
  const pad = 9 * k, crestSz = (twoLines ? 30 : 30) * k, gap = 7 * k;
  const room = W - 2 * pad - (crest ? crestSz + gap : 0);
  const fullName = currentInstitution().name.replace(/,.*$/, "").toUpperCase();
  const words = fullName.split(/\s+/);
  const lines = twoLines && words.length > 2 ? [words.slice(0, -1).join(" "), words[words.length - 1]] : [fullName];
  let nameSize = (twoLines ? 11.2 : 11.4) * k;
  while (lines.some((l) => wText(l, nameSize, "F3", 0.02 * nameSize) > room) && nameSize > 7 * k) nameSize -= 0.2;
  let titleSize = (twoLines ? 7.6 : 7.8) * k;
  while (wText(pal.title, titleSize, "F2", 0.16 * titleSize) > room && titleSize > 5 * k) titleSize -= 0.2;
  const textH = lines.length * nameSize * 1.12 + 2.2 * k + titleSize * 1.1;
  const hb = 6 * k + Math.max(crestSz, textH) + 6 * k;
  p.fillRgb(x0, top - hb, W, hb, pal.head);
  if (crest) p.jpeg(x0 + pad, top - hb / 2 - crestSz / 2, crestSz, crestSz, crest);
  const tx = x0 + pad + (crest ? crestSz + gap : 0);
  let ty = top - hb / 2 + textH / 2 - nameSize * 0.82;
  // a second pass a hair to the right reads as a heavier face than the font alone
  for (const l of lines) {
    for (const dx of [0, 0.25 * k]) p.textStyled(tx + dx, ty, l, nameSize, { font: "F3", colour: C.white, spacing: 0.02 * nameSize });
    ty -= nameSize * 1.12;
  }
  p.textStyled(tx, ty - 2.2 * k + nameSize * 0.12 - titleSize * 0.1, pal.title, titleSize, { font: "F2", colour: pal.headSub, spacing: 0.16 * titleSize });
  // the red | green rule
  p.fillRgb(x0, top - hb - 2.2 * k, W * 0.75, 2.2 * k, C.red);
  p.fillRgb(x0 + W * 0.75, top - hb - 2.2 * k, W * 0.25, 2.2 * k, C.green);
  return hb + 2.2 * k;
}

/** the photograph with its border; returns its height */
function photoBlock(p: Page, x: number, top: number, pw: number, ph: number, k: number, photo: Image | null): number {
  const y = top - ph;
  if (photo) {
    // fill the frame without stretching: the photograph cropped to the frame's proportions
    const fr = pw / ph, ir = photo.width / photo.height;
    let dw = pw, dh = ph;
    if (ir > fr) dw = ph * ir; else dh = pw / ir;
    p.clipRound(x, y, pw, ph, 2 * k); p.jpeg(x + (pw - dw) / 2, y + (ph - dh) / 2, dw, dh, photo); p.restore();
  } else {
    p.roundRect(x, y, pw, ph, 2 * k, hex("#D7E2E9"));
    p.ops.push(`q 0.561 0.647 0.706 rg ${(x + pw / 2).toFixed(2)} ${(y + ph * 0.64).toFixed(2)} m `
      + `${(x + pw / 2 + pw * 0.21).toFixed(2)} ${(y + ph * 0.64).toFixed(2)} ${(x + pw / 2 + pw * 0.21).toFixed(2)} ${(y + ph * 0.36).toFixed(2)} ${(x + pw / 2).toFixed(2)} ${(y + ph * 0.36).toFixed(2)} c `
      + `${(x + pw / 2 - pw * 0.21).toFixed(2)} ${(y + ph * 0.36).toFixed(2)} ${(x + pw / 2 - pw * 0.21).toFixed(2)} ${(y + ph * 0.64).toFixed(2)} ${(x + pw / 2).toFixed(2)} ${(y + ph * 0.64).toFixed(2)} c f `
      + `${(x + pw * 0.15).toFixed(2)} ${y.toFixed(2)} m ${(x + pw * 0.15).toFixed(2)} ${(y + ph * 0.2).toFixed(2)} ${(x + pw * 0.85).toFixed(2)} ${(y + ph * 0.2).toFixed(2)} ${(x + pw * 0.85).toFixed(2)} ${y.toFixed(2)} c f Q`);
  }
  p.ops.push(`q ${C.photoBorder.map((v) => v.toFixed(3)).join(" ")} RG 0.9 w ${x.toFixed(2)} ${y.toFixed(2)} ${pw.toFixed(2)} ${ph.toFixed(2)} re S Q`);
  return ph;
}

/** wrap a bold value to a width; a line that still overflows is cut with an ellipsis */
function wrapBold(s: string, maxWidth: number, size: number): string[] {
  return wrap(s, maxWidth, size, "F2").map((l) => { let x = l; while (wText(x, size, "F2") > maxWidth && x.length > 3) x = x.slice(0, -2) + "…"; return x; });
}

interface GridCell { j: number; cw: number; vs: number; lines: string[] }
/** the label/value grid, two to a row (the left column 1.4 to the right's 1): the rows measured first, then laid down with the
 *  gap between them that fills the height given (never more than maxGap) */
function grid(p: Page, x: number, top: number, width: number, height: number, k: number, fields: [string, string][], maxGap: number): number {
  const gapC = 8 * k, labelSize = 6.1 * k, valueSize = 9.2 * k;
  const colL = (width - gapC) * (1.4 / 2.4), colR = (width - gapC) - colL;
  const rows: { cells: GridCell[]; h: number }[] = [];
  for (let i = 0; i < fields.length; i += 2) {
    const cells = [0, 1].filter((j) => i + j < fields.length).map((j) => {
      // a value of a single cell alone in its row may use the whole width
      const alone = j === 0 && i + 1 >= fields.length;
      const cw = alone ? width : j === 0 ? colL : colR;
      const v = clean(fields[i + j][1]) || "—";
      let vs = valueSize;
      while (wText(v, vs, "F2") > cw && vs > 7.4 * k) vs -= 0.3;
      const lines = wText(v, vs, "F2") > cw ? wrapBold(v, cw, vs).slice(0, 2) : [v];
      return { j: i + j, cw, vs, lines };
    });
    rows.push({ cells, h: labelSize * 1.25 + valueSize * 1.2 * Math.max(...cells.map((c) => c.lines.length)) });
  }
  const content = rows.reduce((a, r) => a + r.h, 0);
  const gap = rows.length > 1 ? Math.min(maxGap, Math.max(3 * k, (height - content) / (rows.length - 1))) : 0;
  let y = top;
  for (const r of rows) {
    for (const c of r.cells) {
      const cx = x + (c.j % 2 === 0 ? 0 : colL + gapC);
      p.textStyled(cx, y - labelSize * 0.9, fields[c.j][0].toUpperCase(), labelSize, { font: "F2", colour: C.label, spacing: 0.1 * labelSize });
      c.lines.forEach((line, li) => p.textStyled(cx, y - labelSize * 1.25 - valueSize * 0.92 - li * valueSize * 1.2, line, c.vs, { font: "F2", colour: C.ink }));
    }
    y -= r.h + gap;
  }
  return top - y - gap;
}

/** the grid's natural height (no gap stretching), to plan the body */
function gridHeight(k: number, width: number, fields: [string, string][]): number {
  const gapC = 8 * k, labelSize = 6.1 * k, valueSize = 9.2 * k;
  const colL = (width - gapC) * (1.4 / 2.4), colR = (width - gapC) - colL;
  let h = 0;
  for (let i = 0; i < fields.length; i += 2) {
    let lines = 1;
    for (const j of [0, 1]) {
      if (i + j >= fields.length) continue;
      const cw = j === 0 && i + 1 >= fields.length ? width : j === 0 ? colL : colR;
      const v = clean(fields[i + j][1]) || "—";
      let vs = valueSize;
      while (wText(v, vs, "F2") > cw && vs > 7.4 * k) vs -= 0.3;
      if (wText(v, vs, "F2") > cw) lines = 2;
    }
    h += labelSize * 1.25 + valueSize * 1.2 * lines;
  }
  return h;
}

/** the foot: a rule, the session/validity line with its bold parts, the serial on the right; returns its height */
function foot(p: Page, x0: number, y0: number, W: number, k: number, parts: [string, boolean][], serial: string): number {
  const pad = 9 * k, size = 7 * k;
  const footH = 4 * k + size * 1.2 + 4.5 * k;
  p.ops.push(`q ${C.line.map((v) => v.toFixed(3)).join(" ")} RG 0.8 w ${x0.toFixed(2)} ${(y0 + footH).toFixed(2)} m ${(x0 + W).toFixed(2)} ${(y0 + footH).toFixed(2)} l S Q`);
  let x = x0 + pad;
  const ty = y0 + 4.5 * k + size * 0.25;
  for (const [t, bold] of parts) {
    p.textStyled(x, ty, t, size, { font: bold ? "F2" : "F1", colour: bold ? C.ink : C.foot });
    x += wText(t, size, bold ? "F2" : "F1");
  }
  p.textStyled(x0 + W - pad - wText(serial, size, "F1", 0.04 * size), ty, serial, size, { colour: C.foot, spacing: 0.04 * size });
  return footH;
}

const footHeight = (k: number) => 4 * k + 7 * k * 1.2 + 4.5 * k;

/** the holder's name and number; returns the height used */
function holder(p: Page, x: number, top: number, width: number, k: number, f: CardFace, centred: boolean): number {
  const name = clean(f.name).toUpperCase();
  let ns = 13 * k;
  while (wText(name, ns, "F2") > width && ns > 8.5 * k) ns -= 0.3;
  const nameLines = wText(name, ns, "F2") > width ? wrapBold(name, width, ns).slice(0, 2) : [name];
  let y = top;
  for (const l of nameLines) {
    p.textStyled(centred ? x + width / 2 - wText(l, ns, "F2") / 2 : x, y - ns * 0.92, l, ns, { font: "F2", colour: C.ink, spacing: -0.15 });
    y -= ns * 1.12;
  }
  const num = clean(f.number), numSize = 11 * k;
  p.textStyled(centred ? x + width / 2 - wText(num, numSize, "F2", 0.01 * numSize) / 2 : x, y - 1 * k - numSize * 0.92, num, numSize, { font: "F2", colour: C.number, spacing: 0.01 * numSize });
  y -= 1 * k + numSize * 1.15;
  return top - y;
}

/** the front, landscape (the student card): the photograph left, the holder right, the fields spread to the photograph's foot */
export function drawFrontLandscape(p: Page, x0: number, y0: number, W: number, f: CardFace, photo: Image | null, crest: Image | null): number {
  const k = W / CARD_PX.w, H = CARD_PX.h * k;
  canvas(p, x0, y0, W, H, k, C.face);
  guilloche(p, x0, y0, W, H, KIND[f.kind].tint);
  if (crest) p.imageFaint(x0 + W - 84 * k, y0 + 18 * k, 100 * k, 100 * k, crest);
  const top = y0 + H;
  const used = header(p, x0, top, W, k, crest, f.kind, false);
  const pad = 9 * k, bodyTop = top - used - 6 * k;
  const bodyBottom = y0 + footHeight(k) + 5 * k;
  const ph = Math.min(132 * k, bodyTop - bodyBottom), pw = ph * 0.8;
  photoBlock(p, x0 + pad, bodyTop, pw, ph, k, photo);
  const wx = x0 + pad + pw + 9 * k, ww = x0 + W - pad - wx;
  const hh = holder(p, wx, bodyTop, ww, k, f, false);
  const gTop = bodyTop - hh - 4 * k;
  grid(p, wx, gTop, ww, gTop - (bodyTop - ph), k, f.fields, 14 * k);
  foot(p, x0, y0, W, k, f.foot, f.serial);
  p.restore();
  return H;
}

/** the front, portrait (the staff card): the photograph centred beneath the header, the holder beneath it, the fields to the foot */
export function drawFrontPortrait(p: Page, x0: number, y0: number, W: number, f: CardFace, photo: Image | null, crest: Image | null): number {
  const k = W / CARD_PX.h, H = CARD_PX.w * k;
  canvas(p, x0, y0, W, H, k, C.face);
  guilloche(p, x0, y0, W, H, KIND[f.kind].tint);
  if (crest) p.imageFaint(x0 + W - 84 * k, y0 + 24 * k, 100 * k, 100 * k, crest);
  const top = y0 + H;
  const used = header(p, x0, top, W, k, crest, f.kind, true);
  const pad = 10 * k;
  const bodyBottom = y0 + footHeight(k) + 6 * k;
  // the photograph as large as the body allows once the holder and the fields are placed
  const gH = gridHeight(k, W - 2 * pad, f.fields);
  const photoTop = top - used - 8 * k;
  const room = photoTop - bodyBottom - 6 * k - 26 * k - 6 * k - gH;
  const ph = Math.max(90 * k, Math.min(128 * k, room)), pw = ph * 0.8;
  photoBlock(p, x0 + (W - pw) / 2, photoTop, pw, ph, k, photo);
  const hTop = photoTop - ph - 6 * k;
  const hh = holder(p, x0 + pad, hTop, W - 2 * pad, k, f, true);
  const gTop = hTop - hh - 5 * k;
  grid(p, x0 + pad, gTop, W - 2 * pad, gTop - bodyBottom, k, f.fields, 10 * k);
  foot(p, x0, y0, W, k, f.foot, f.serial);
  p.restore();
  return H;
}

/** the signature block: the signature image fitted above the line, the name (when held) and the title under it, centred on cx */
function signatureBlock(p: Page, cx: number, bottom: number, lineW: number, imgH: number, k: number, s: CardBack["signatory"]) {
  const titleSize = 5.9 * k, nameSize = 6.4 * k;
  const title = (s?.title ?? "Chief Security Officer").toUpperCase();
  const name = clean(s?.name ?? "");
  let y = bottom;
  p.textStyled(cx - wText(title, titleSize, "F2", 0.08 * titleSize) / 2, y, title, titleSize, { font: "F2", colour: C.label, spacing: 0.08 * titleSize });
  y += titleSize * 1.25;
  if (name) { p.textStyled(cx - wText(name, nameSize, "F2") / 2, y, name, nameSize, { font: "F2", colour: C.ink }); y += nameSize * 1.25; }
  const lineY = y + 1.5 * k;
  p.ops.push(`q ${C.sig.map((v) => v.toFixed(3)).join(" ")} RG 0.8 w ${(cx - lineW / 2).toFixed(2)} ${lineY.toFixed(2)} m ${(cx + lineW / 2).toFixed(2)} ${lineY.toFixed(2)} l S Q`);
  const img = s?.image;
  if (img) {
    const r = img.width / img.height;
    let w = lineW * 0.9, h = w / r;
    if (h > imgH) { h = imgH; w = h * r; }
    p.inkJpeg(cx - w / 2, lineY + 0.5 * k, w, h, img);
  }
}

const sigBlockHeight = (k: number, s: CardBack["signatory"]) => 5.9 * k * 1.25 + (clean(s?.name ?? "") ? 6.4 * k * 1.25 : 0) + 1.5 * k;

/** the back — the strip, the barcode, the conditions, the verification QR and the Chief Security Officer's signature, every write-up
 *  centred; laid out across a landscape card (the QR and the signature side by side) or down a portrait one (one under the other) */
export function drawBack(p: Page, x0: number, y0: number, W: number, H: number, b: CardBack, crest: Image | null = null) {
  const landscape = W > H;
  const k = W / (landscape ? CARD_PX.w : CARD_PX.h);
  const pal = KIND[b.kind];
  canvas(p, x0, y0, W, H, k, C.back);
  guilloche(p, x0, y0, W, H, pal.tint);
  if (crest) p.imageFaint(x0 + W / 2 - 50 * k, y0 + H / 2 - 50 * k, 100 * k, 100 * k, crest);
  const top = y0 + H, pad = 10 * k, cx = x0 + W / 2;
  // the strip, in the card's colour
  const stripSize = 6.6 * k, stripH = 4.5 * k + stripSize * 1.2 + 4.5 * k;
  p.fillRgb(x0, top - stripH, W, stripH, pal.strip);
  const stripText = "PROPERTY OF THE UNIVERSITY · NOT TRANSFERABLE";
  let ss = stripSize;
  while (wText(stripText, ss, "F2", 0.1 * ss) > W - 2 * pad && ss > 4.5 * k) ss -= 0.2;
  p.textStyled(cx - wText(stripText, ss, "F2", 0.1 * ss) / 2, top - stripH / 2 - ss * 0.35, stripText, ss, { font: "F2", colour: C.white, spacing: 0.1 * ss });
  // the barcode, centred with its quiet zones
  const runs = c128Runs(b.barcode);
  const units = runs.reduce((a, c) => a + c, 0) + 20;
  const bw = Math.min(W - 2 * pad, units * 1.6 * k), unit = bw / units, bh = (landscape ? 30 : 34) * k, by = top - stripH - 6 * k - bh;
  const bx0 = cx - bw / 2;
  p.fill(bx0, by, bw, bh, 1);
  let bx = bx0 + 10 * unit; let dark = true;
  for (const r of runs) { if (dark) p.fill(bx, by, r * unit, bh, 0.07); bx += r * unit; dark = !dark; }
  const numSize = 8.8 * k;
  p.textStyled(cx - wText(b.barcode, numSize, "F2", 0.22 * numSize) / 2, by - 2 * k - numSize * 0.95, b.barcode, numSize, { font: "F2", colour: C.ink, spacing: 0.22 * numSize });
  // the conditions, centred line by line
  const hSize = 6.4 * k, pSize = (landscape ? 6.5 : 6.6) * k;
  let ty = by - 2 * k - numSize * 1.2 - (landscape ? 5 : 8) * k;
  const head = "CONDITIONS";
  p.textStyled(cx - wText(head, hSize, "F2", 0.12 * hSize) / 2, ty - hSize * 0.9, head, hSize, { font: "F2", colour: C.foot, spacing: 0.12 * hSize });
  ty -= hSize * 1.3 + 1.5 * k;
  for (const t of b.terms ?? CONDITIONS) {
    for (const line of wrap(t, W - 2 * pad, pSize)) { p.textStyled(cx - wText(line, pSize) / 2, ty - pSize * 0.9, line, pSize, { colour: C.terms }); ty -= pSize * 1.42; }
    ty -= 2 * k;
  }
  const bottom = y0 + 7 * k;
  const qrOf = (qx: number, qy: number, dim: number) => {
    const { size, dark: qd } = qrMatrix(b.qr ?? `MOAUM ID ${b.serial}`);
    const cell = dim / size;
    p.fill(qx, qy, dim, dim, 1);
    for (let rr = 0; rr < size; rr++) for (let cc = 0; cc < size; cc++) if (qd[rr * size + cc]) p.fill(qx + cc * cell, qy + dim - (rr + 1) * cell, cell, cell, 0.09);
  };
  const vt = 6 * k, ks = 5.8 * k, kv = 6.8 * k;
  if (landscape) {
    // the QR with the serial and the aside beside it on the left half; the signature on the right half; both sized to the room left
    const room = ty - 3 * k - bottom;
    const qDim = Math.max(26 * k, Math.min(48 * k, room));
    const half = (W - 2 * pad) / 2;
    const textW = half - qDim - 6 * k;
    const asideLines = b.aside ? wrap(b.aside[1], textW, kv, "F2") : [];
    const textH = vt * 1.45 + (b.aside ? ks * 1.35 + asideLines.length * kv * 1.3 : 0);
    const groupW = qDim + 6 * k + Math.min(textW, Math.max(wText(b.serial, vt, "F2"), ...(b.aside ? [wText(b.aside[0], ks), ...asideLines.map((l) => wText(l, kv, "F2"))] : [0])));
    const qx = x0 + pad + (half - groupW) / 2, qy = bottom + (room - qDim) / 2;
    qrOf(qx, qy, qDim);
    const tx = qx + qDim + 6 * k;
    let vy = qy + qDim / 2 + textH / 2 - vt * 0.95;
    p.textStyled(tx, vy, b.serial, vt, { font: "F2", colour: C.ink }); vy -= vt * 1.45;
    if (b.aside) {
      p.textStyled(tx, vy, b.aside[0], ks, { colour: C.foot }); vy -= ks * 1.35;
      for (const line of asideLines) { p.textStyled(tx, vy, line, kv, { font: "F2", colour: C.ink }); vy -= kv * 1.3; }
    }
    const sx = x0 + pad + half + half / 2;
    const imgH = Math.max(12 * k, Math.min(30 * k, room - sigBlockHeight(k, b.signatory) - 2 * k));
    const blockH = sigBlockHeight(k, b.signatory) + imgH;
    signatureBlock(p, sx, bottom + Math.max(0, (room - blockH) / 2), half * 0.82, imgH, k, b.signatory);
  } else {
    // one under the other, centred: the QR, the serial and the aside under it, then the signature
    const sigH = sigBlockHeight(k, b.signatory);
    const asideLines = b.aside ? wrap(b.aside[1], W - 2 * pad, kv, "F2") : [];
    const textH = vt * 1.45 + (b.aside ? ks * 1.35 + asideLines.length * kv * 1.3 : 0);
    const imgH = 30 * k;
    const room = ty - 4 * k - bottom - sigH - imgH - 8 * k - textH - 4 * k;
    const qDim = Math.max(40 * k, Math.min(70 * k, room));
    const spare = Math.max(0, room - qDim);
    const qy = ty - 4 * k - spare / 3 - qDim;
    qrOf(cx - qDim / 2, qy, qDim);
    let vy = qy - 3 * k - vt * 0.95;
    p.textStyled(cx - wText(b.serial, vt, "F2") / 2, vy, b.serial, vt, { font: "F2", colour: C.ink }); vy -= vt * 1.45;
    if (b.aside) {
      p.textStyled(cx - wText(b.aside[0], ks) / 2, vy, b.aside[0], ks, { colour: C.foot }); vy -= ks * 1.35;
      for (const line of asideLines) { p.textStyled(cx - wText(line, kv, "F2") / 2, vy, line, kv, { font: "F2", colour: C.ink }); vy -= kv * 1.3; }
    }
    signatureBlock(p, cx, bottom + spare / 6, (W - 2 * pad) * 0.7, imgH, k, b.signatory);
  }
  p.restore();
}
