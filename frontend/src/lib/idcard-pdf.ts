/**
 * The identity card drawn into a PDF exactly as the screen draws it (components/proto/idcard.tsx and
 * the .idc rules in styles/prototype.css): the same colours, the same measurements scaled from the
 * card's CSS pixels to points, the same faces — a serif bold for the University's name, spaced capitals
 * for labels — the rounded corners, the faded crest, the red|green rule, the red holder tag. The
 * student card is landscape, the staff card portrait; both share every part below.
 */
import { Page, type Image } from "@/lib/pdf-write";
import { qrMatrix } from "@/lib/qr";

export type Rgb = [number, number, number];
const hex = (h: string): Rgb => [parseInt(h.slice(1, 3), 16) / 255, parseInt(h.slice(3, 5), 16) / 255, parseInt(h.slice(5, 7), 16) / 255];

/* the card's palette, as the stylesheet names it */
export const C = {
  ink: hex("#17202A"), head: hex("#0E3F55"), headSub: hex("#9EC6DA"), red: hex("#ED1B23"), green: hex("#0CA54E"),
  tag: hex("#D6151C"), number: hex("#B01218"), label: hex("#5E6B78"), foot: hex("#56636E"), terms: hex("#35424D"),
  strip: hex("#17202A"), stripText: hex("#C9D6DE"), border: hex("#C7D2DA"), photoBorder: hex("#B9C8D2"),
  line: hex("#E4EAEF"), sig: hex("#9AA8B3"), white: [1, 1, 1] as Rgb, face: hex("#FFFFFF"), back: hex("#FBFCFD"),
  shadow: hex("#102634"),
};

/** the card's CSS pixel size (85.6 × 54 mm at 96 dpi) — every measure below is in these pixels, scaled */
export const CARD_PX = { w: 323.5, h: 204.1 };

export const clean = (s: string | null | undefined) => (s ?? "").replace(/[^\x20-\x7E]/g, " ").replace(/\s+/g, " ").trim();
/** the width of a run of text, by character class: capitals are wide, lower case narrower, spaces and
 *  punctuation narrower still — Helvetica's proportions, which is what the card is set in */
const wText = (s: string, size: number, font: "F1" | "F2" | "F3" = "F1", spacing = 0) => {
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
function wrap(s: string, maxWidth: number, size: number): string[] {
  const out: string[] = [];
  let line = "";
  for (const w of s.split(/\s+/)) {
    const t = (line + " " + w).trim();
    if (wText(t, size) > maxWidth && line) { out.push(line); line = w; } else line = t;
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
  /** the holder's name, printed in capitals */
  name: string;
  /** the number under the name, in the card's red */
  number: string;
  /** the red tag on the photograph: STUDENT · STAFF */
  tag: string;
  /** label/value pairs laid out two to a row (the left column wider) */
  fields: [string, string][];
  /** the foot's left text, with the bold parts marked as [text, bold] */
  foot: [string, boolean][];
  serial: string;
}
export interface CardBack {
  barcode: string;
  serial: string;
  terms?: string[];
  /** the small block under the QR: a label and a value (e.g. "In an emergency" / the kin's phone) */
  aside?: [string, string];
  signatures?: [string, string];
}

/** the card's canvas: rounded, bordered, shadowed and clipped; returns the scale (pt per CSS px) */
function canvas(p: Page, x0: number, y0: number, W: number, H: number, k: number, fill: Rgb): number {
  const r = 12.1 * k;   // 3.2 mm
  // a soft drop shadow: three faint layers stepping out, as the screen's box-shadow reads
  for (const d of [1, 2, 3]) p.roundRect(x0, y0 - d, W, H, r, C.shadow, undefined, 0, true);
  p.roundRect(x0, y0, W, H, r, fill, C.border, 0.8);
  p.clipRound(x0, y0, W, H, r);
  return r;
}

/** a faint diagonal tint, the way a real card is printed (the screen's guilloche) */
function guilloche(p: Page, x0: number, y0: number, W: number, H: number) {
  for (let d = -H; d < W + H; d += 5) {
    p.ops.push(`q /GS5 gs 0.055 0.247 0.333 RG 0.4 w ${(x0 + d).toFixed(2)} ${y0.toFixed(2)} m ${(x0 + d + H * 0.78).toFixed(2)} ${(y0 + H).toFixed(2)} l S Q`);
  }
}

/** the header band: crest, the University's name in serif capitals, the place beneath; returns its height */
function header(p: Page, x0: number, top: number, W: number, k: number, crest: Image | null, twoLines: boolean): number {
  const pad = 9 * k, crestSz = 26 * k, gap = 7 * k;
  const nameSize = 9.4 * k, subSize = 6.2 * k;
  const lines = twoLines ? ["REV. FR. MOSES ORSHIO ADASU", "UNIVERSITY"] : ["REV. FR. MOSES ORSHIO ADASU UNIVERSITY"];
  const textH = lines.length * nameSize * 1.16 + 1.5 * k + subSize * 1.2;
  const hb = 6 * k + Math.max(crestSz, textH) + 5 * k;
  p.fillRgb(x0, top - hb, W, hb, C.head);
  if (crest) p.jpeg(x0 + pad, top - 6 * k - (hb - 11 * k) / 2 - crestSz / 2, crestSz, crestSz, crest);
  const tx = x0 + pad + (crest ? crestSz + gap : 0);
  let ty = top - 6 * k - (hb - 11 * k - textH) / 2 - nameSize * 0.85;
  for (const l of lines) { p.textStyled(tx, ty, l, nameSize, { font: "F3", colour: C.white, spacing: 0.012 * nameSize }); ty -= nameSize * 1.16; }
  p.textStyled(tx, ty - 1.5 * k + nameSize * 0.2, "MAKURDI · BENUE STATE · NIGERIA", subSize, { colour: C.headSub, spacing: 0.06 * subSize });
  // the red | green rule
  p.fillRgb(x0, top - hb - 2 * k, W * 0.75, 2 * k, C.red);
  p.fillRgb(x0 + W * 0.75, top - hb - 2 * k, W * 0.25, 2 * k, C.green);
  return hb + 2 * k;
}

/** the photograph with its border and the red tag beneath; returns the block's height */
function photoBlock(p: Page, x: number, top: number, pw: number, ph: number, k: number, tag: string, photo: Image | null): number {
  const y = top - ph;
  if (photo) { p.clipRound(x, y, pw, ph, 2 * k); p.jpeg(x, y, pw, ph, photo); p.restore(); }
  else {
    p.roundRect(x, y, pw, ph, 2 * k, hex("#D7E2E9"));
    // the silhouette the screen shows when there is no photograph
    p.ops.push(`q 0.561 0.647 0.706 rg ${(x + pw / 2).toFixed(2)} ${(y + ph * 0.64).toFixed(2)} m `
      + `${(x + pw / 2 + pw * 0.21).toFixed(2)} ${(y + ph * 0.64).toFixed(2)} ${(x + pw / 2 + pw * 0.21).toFixed(2)} ${(y + ph * 0.36).toFixed(2)} ${(x + pw / 2).toFixed(2)} ${(y + ph * 0.36).toFixed(2)} c `
      + `${(x + pw / 2 - pw * 0.21).toFixed(2)} ${(y + ph * 0.36).toFixed(2)} ${(x + pw / 2 - pw * 0.21).toFixed(2)} ${(y + ph * 0.64).toFixed(2)} ${(x + pw / 2).toFixed(2)} ${(y + ph * 0.64).toFixed(2)} c f `
      + `${(x + pw * 0.15).toFixed(2)} ${y.toFixed(2)} m ${(x + pw * 0.15).toFixed(2)} ${(y + ph * 0.2).toFixed(2)} ${(x + pw * 0.85).toFixed(2)} ${(y + ph * 0.2).toFixed(2)} ${(x + pw * 0.85).toFixed(2)} ${y.toFixed(2)} c f Q`);
  }
  p.ops.push(`q ${C.photoBorder.map((v) => v.toFixed(3)).join(" ")} RG 0.8 w ${x.toFixed(2)} ${y.toFixed(2)} ${pw.toFixed(2)} ${ph.toFixed(2)} re S Q`);
  const tagH = 10.6 * k, tagY = y - 3 * k - tagH, tagSize = 6.6 * k;
  p.roundRect(x, tagY, pw, tagH, 2 * k, C.tag);
  const t = tag.toUpperCase();
  p.textStyled(x + pw / 2 - wText(t, tagSize, "F2", 0.12 * tagSize) / 2, tagY + tagH / 2 - tagSize * 0.35, t, tagSize, { font: "F2", colour: C.white, spacing: 0.12 * tagSize });
  return ph + 3 * k + tagH;
}

/** the label/value grid, two to a row, the left column 1.55 to the right's 1; returns the y beneath it */
function grid(p: Page, x: number, top: number, width: number, k: number, fields: [string, string][]): number {
  const gapC = 7 * k, gapR = 3.5 * k, labelSize = 5.4 * k, valueSize = 8.2 * k;
  const colL = (width - gapC) * (1.55 / 2.55), colR = (width - gapC) - colL;
  let y = top;
  for (let i = 0; i < fields.length; i += 2) {
    // each cell: the value at full size if it fits, a touch smaller if that makes it fit, else on two lines
    const cells = [0, 1].filter((j) => i + j < fields.length).map((j) => {
      const cw = j === 0 ? colL : colR;
      const v = clean(fields[i + j][1]) || "—";
      let vs = valueSize;
      while (wText(v, vs, "F2") > cw && vs > 7 * k) vs -= 0.3;
      const lines = wText(v, vs, "F2") > cw ? wrapBold(v, cw, vs).slice(0, 2) : [v];
      return { j, cw, vs, lines };
    });
    const rows = Math.max(...cells.map((c) => c.lines.length));
    const rowH = labelSize * 1.2 + valueSize * 1.25 * rows;
    for (const c of cells) {
      const cx = x + (c.j === 0 ? 0 : colL + gapC);
      p.textStyled(cx, y - labelSize * 0.9, fields[i + c.j][0].toUpperCase(), labelSize, { font: "F2", colour: C.label, spacing: 0.1 * labelSize });
      c.lines.forEach((line, li) => p.textStyled(cx, y - labelSize * 1.2 - valueSize * 0.95 - li * valueSize * 1.25, line, c.vs, { font: "F2", colour: C.ink }));
    }
    y -= rowH + gapR;
  }
  return y;
}

/** wrap a bold value to a width; a line that still overflows is cut with an ellipsis */
function wrapBold(s: string, maxWidth: number, size: number): string[] {
  const out: string[] = [];
  let line = "";
  for (const w of s.split(/\s+/)) {
    const t = (line + " " + w).trim();
    if (wText(t, size, "F2") > maxWidth && line) { out.push(line); line = w; } else line = t;
  }
  if (line) out.push(line);
  return out.map((l) => { let x = l; while (wText(x, size, "F2") > maxWidth && x.length > 3) x = x.slice(0, -2) + "…"; return x; });
}

/** the foot: a rule, the session/validity line with its bold parts, the serial on the right */
function foot(p: Page, x0: number, y0: number, W: number, k: number, parts: [string, boolean][], serial: string) {
  const pad = 9 * k, size = 6.6 * k;
  const footH = 4 * k + size * 1.2 + 5 * k;
  p.ops.push(`q ${C.line.map((v) => v.toFixed(3)).join(" ")} RG 0.8 w ${x0.toFixed(2)} ${(y0 + footH).toFixed(2)} m ${(x0 + W).toFixed(2)} ${(y0 + footH).toFixed(2)} l S Q`);
  let x = x0 + pad;
  const ty = y0 + 5 * k + size * 0.25;
  for (const [t, bold] of parts) {
    p.textStyled(x, ty, t, size, { font: bold ? "F2" : "F1", colour: bold ? C.ink : C.foot });
    x += wText(t, size, bold ? "F2" : "F1");
  }
  p.textStyled(x0 + W - pad - wText(serial, size, "F1", 0.04 * size), ty, serial, size, { colour: C.foot, spacing: 0.04 * size });
}

/** the front, landscape (the student card): photograph left, the holder right */
export function drawFrontLandscape(p: Page, x0: number, y0: number, W: number, f: CardFace, photo: Image | null, crest: Image | null): number {
  const k = W / CARD_PX.w, H = CARD_PX.h * k;
  canvas(p, x0, y0, W, H, k, C.face);
  guilloche(p, x0, y0, W, H);
  if (crest) p.imageFaint(x0 + W - 76 * k, y0 + 8 * k, 96 * k, 96 * k, crest);
  const top = y0 + H;
  const used = header(p, x0, top, W, k, crest, false);
  const pad = 9 * k, bodyTop = top - used - 7 * k;
  photoBlock(p, x0 + pad, bodyTop, 62 * k, 76 * k, k, f.tag, photo);
  const wx = x0 + pad + 62 * k + 8 * k, ww = x0 + W - pad - wx;
  const nameSize = 11.6 * k;
  const name = clean(f.name).toUpperCase();
  let ns = nameSize;
  while (wText(name, ns, "F2") > ww && ns > 8 * k) ns -= 0.4;
  p.textStyled(wx, bodyTop - ns * 0.95, name, ns, { font: "F2", colour: C.ink, spacing: -0.2 });
  const numSize = 9.6 * k;
  p.textStyled(wx, bodyTop - nameSize * 1.18 - numSize * 0.95, clean(f.number), numSize, { font: "F2", colour: C.number, spacing: 0.01 * numSize });
  grid(p, wx, bodyTop - nameSize * 1.18 - numSize * 1.2 - 3 * k - 1 * k, ww, k, f.fields);
  foot(p, x0, y0, W, k, f.foot, f.serial);
  p.restore();
  return H;
}

/** the front, portrait (the staff card): the photograph centred beneath the header, the holder beneath it */
export function drawFrontPortrait(p: Page, x0: number, y0: number, W: number, f: CardFace, photo: Image | null, crest: Image | null): number {
  const k = W / CARD_PX.h, H = CARD_PX.w * k;
  canvas(p, x0, y0, W, H, k, C.face);
  guilloche(p, x0, y0, W, H);
  if (crest) p.imageFaint(x0 + W - 76 * k, y0 + 8 * k, 96 * k, 96 * k, crest);
  const top = y0 + H;
  const used = header(p, x0, top, W, k, crest, true);
  const pad = 9 * k;
  const pw = 78 * k, ph = 96 * k;
  const photoTop = top - used - 8 * k;
  const blockH = photoBlock(p, x0 + (W - pw) / 2, photoTop, pw, ph, k, f.tag, photo);
  let y = photoTop - blockH - 7 * k;
  const nameSize = 11.6 * k;
  const name = clean(f.name).toUpperCase();
  let ns = nameSize;
  while (wText(name, ns, "F2") > W - 2 * pad && ns > 8 * k) ns -= 0.4;
  p.textStyled(x0 + W / 2 - wText(name, ns, "F2") / 2, y - ns * 0.95, name, ns, { font: "F2", colour: C.ink, spacing: -0.2 });
  y -= nameSize * 1.18;
  const numSize = 9.6 * k;
  p.textStyled(x0 + W / 2 - wText(clean(f.number), numSize, "F2") / 2, y - numSize * 0.95, clean(f.number), numSize, { font: "F2", colour: C.number, spacing: 0.01 * numSize });
  y -= numSize * 1.2 + 5 * k;
  grid(p, x0 + pad, y, W - 2 * pad, k, f.fields);
  foot(p, x0, y0, W, k, f.foot, f.serial);
  p.restore();
  return H;
}

/** the back — the same on both cards, laid out to the given size: the strip, the barcode, the conditions
 *  across the width, then the verification QR with the serial and the address beside it, and the
 *  Registrar's signature line; the crest faintly behind, as on the front */
export function drawBack(p: Page, x0: number, y0: number, W: number, H: number, b: CardBack, crest: Image | null = null) {
  const k = W / (W > H ? CARD_PX.w : CARD_PX.h);
  canvas(p, x0, y0, W, H, k, C.back);
  guilloche(p, x0, y0, W, H);
  if (crest) p.imageFaint(x0 + W - 76 * k, y0 + 8 * k, 96 * k, 96 * k, crest);
  const top = y0 + H, pad = 9 * k;
  // the strip
  const stripSize = 6.2 * k, stripH = 4 * k + stripSize * 1.2 + 4 * k;
  p.fillRgb(x0, top - stripH, W, stripH, C.strip);
  const stripText = "PROPERTY OF THE UNIVERSITY · NOT TRANSFERABLE";
  let ss = stripSize;
  while (wText(stripText, ss, "F2", 0.1 * ss) > W - 2 * pad && ss > 4.5 * k) ss -= 0.2;
  p.textStyled(x0 + pad, top - stripH / 2 - ss * 0.35, stripText, ss, { font: "F2", colour: C.stripText, spacing: 0.1 * ss });
  // the barcode, full width with its quiet zones
  const runs = c128Runs(b.barcode);
  const units = runs.reduce((a, c) => a + c, 0) + 20;
  const bw = W - 2 * pad, unit = bw / units, bh = 34 * k, by = top - stripH - 7 * k - bh;
  p.fill(x0 + pad, by, bw, bh, 1);
  let bx = x0 + pad + 10 * unit; let dark = true;
  for (const r of runs) { if (dark) p.fill(bx, by, r * unit, bh, 0.07); bx += r * unit; dark = !dark; }
  const numSize = 8.6 * k;
  p.textStyled(x0 + W / 2 - wText(b.barcode, numSize, "F2", 0.22 * numSize) / 2, by - 2 * k - numSize * 0.95, b.barcode, numSize, { font: "F2", colour: C.ink, spacing: 0.22 * numSize });
  // the conditions, across the width
  const hSize = 6 * k, pSize = 5.9 * k;
  let ty = by - 2 * k - numSize * 1.2 - 6 * k;
  p.textStyled(x0 + pad, ty - hSize * 0.9, "CONDITIONS", hSize, { font: "F2", colour: C.foot, spacing: 0.1 * hSize });
  ty -= hSize * 1.2 + 2 * k;
  for (const t of b.terms ?? CONDITIONS) {
    for (const line of wrap(t, W - 2 * pad, pSize)) { p.textStyled(x0 + pad, ty - pSize * 0.9, line, pSize, { colour: C.terms }); ty -= pSize * 1.5; }
    ty -= 2 * k;
  }
  // the verification QR, the serial and the address beside it
  const sigSize = 5.6 * k;
  const sigTop = y0 + 6 * k + sigSize * 1.2 + 2 * k + 10 * k;      // the top of the signature block
  const qDim = Math.min(34 * k, Math.max(22 * k, ty - 4 * k - sigTop - 4 * k));
  const { size, dark: qd } = qrMatrix(`MOAUM ID ${b.serial}`);
  const cell = qDim / size, qx = x0 + pad, qy = ty - 4 * k - qDim;
  p.fill(qx, qy, qDim, qDim, 1);
  for (let rr = 0; rr < size; rr++) for (let cc = 0; cc < size; cc++) if (qd[rr * size + cc]) p.fill(qx + cc * cell, qy + qDim - (rr + 1) * cell, cell, cell, 0.09);
  const tx = qx + qDim + 6 * k, vt = 5.5 * k;
  let vy = qy + qDim - vt * 0.95;
  p.textStyled(tx, vy, b.serial, vt, { font: "F2", colour: C.ink }); vy -= vt * 1.4;
  if (b.aside) {
    const ks = 5.6 * k, kv = 6.6 * k;
    p.textStyled(tx, vy, b.aside[0], ks, { colour: C.foot }); vy -= ks * 1.35;
    for (const line of wrap(b.aside[1], x0 + W - pad - tx, kv)) { p.textStyled(tx, vy, line, kv, { font: "F2", colour: C.ink }); vy -= kv * 1.3; }
  }
  // the Registrar's signature line, on the right
  const lineW = (W - 2 * pad) * 0.48, sx = x0 + W - pad - lineW;
  p.ops.push(`q ${C.sig.map((v) => v.toFixed(3)).join(" ")} RG 0.8 w ${sx.toFixed(2)} ${sigTop.toFixed(2)} m ${(sx + lineW).toFixed(2)} ${sigTop.toFixed(2)} l S Q`);
  p.textStyled(sx, y0 + 6 * k + sigSize * 0.25, b.signatures?.[1] ?? "Registrar", sigSize, { colour: C.label, spacing: 0.04 * sigSize });
  p.restore();
}
