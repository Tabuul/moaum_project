/**
 * The identity card drawn into a PDF: the student card landscape, the staff card portrait. The design is lib/idcard-design (the
 * University's redesign of 12 November 2026, the same drawing the card desk shows on screen); this places it on a page — the card's
 * top-left corner, its width in points, a soft shadow under it — with the photograph, the crest and the Chief Security Officer's
 * signature as the JPEGs the writer embeds, and the verification QR built from the card's signed check address.
 */
import { Page, type Image } from "@/lib/pdf-write";
import { PdfSurface, hex, path } from "@/lib/card-surface";
import { LAND, PORT, clean, drawCardBack, drawStaffFront, drawStudentFront, type CardBack as DesignBack, type CardFace } from "@/lib/idcard-design";
import { qrMatrix } from "@/lib/qr";

export { clean };
export type { CardFace };
export type { Rgb, CardKind } from "@/lib/idcard-design";

/* the page's own words around the card (the title over it, FRONT/BACK under it) */
export const C = { ink: hex("#17202A"), foot: hex("#56636E") };

/** the card's CSS pixel size (85.6 × 54 mm at 96 dpi) — the proportion a page gives the card it prints */
export const CARD_PX = { w: 323.5, h: 204.1 };

export interface CardBack extends DesignBack {
  /** what the QR carries: the card's signed check address (V439); without one, the card's number */
  qr?: string;
  /** who signs for the University — the title under the line, the name above it when held, and the signature image */
  signatory?: { title: string; name?: string | null; image?: Image | null };
}

function surface(p: Page, x0: number, y0: number, W: number, unitsW: number, unitsH: number, images: Record<string, Image | null | undefined>) {
  const k = W / unitsW, H = unitsH * k;
  const s = new PdfSurface(p, x0, y0 + H, k, images).begin();
  // a soft shadow under the card, on the page
  for (const [d, a] of [[1.6, 0.05], [3.2, 0.04], [4.8, 0.03]] as [number, number][]) {
    s.fill(path().round((d * 0.3) / k, d / k, unitsW, unitsH, 31), [0.06, 0.12, 0.2], { alpha: a });
  }
  return { s, H };
}

/** the front, landscape (the student card), its bottom-left corner at (x0, y0) and W points wide; returns its height */
export function drawFrontLandscape(p: Page, x0: number, y0: number, W: number, f: CardFace, photo: Image | null, crest: Image | null): number {
  const { s, H } = surface(p, x0, y0, W, LAND.w, LAND.h, { photo, crest });
  drawStudentFront(s, f);
  s.end();
  return H;
}

/** the front, portrait (the staff card); returns its height */
export function drawFrontPortrait(p: Page, x0: number, y0: number, W: number, f: CardFace, photo: Image | null, crest: Image | null): number {
  const { s, H } = surface(p, x0, y0, W, PORT.w, PORT.h, { photo, crest });
  drawStaffFront(s, f);
  s.end();
  return H;
}

/** the back — the strip, the barcode, the conditions, the verification QR and the signature — across a landscape card or down a
 *  portrait one (W against H says which) */
export function drawBack(p: Page, x0: number, y0: number, W: number, H: number, b: CardBack, crest: Image | null = null) {
  const landscape = W > H;
  const units = landscape ? LAND : PORT;
  const { s } = surface(p, x0, y0, W, units.w, units.h, { crest, signature: b.signatory?.image ?? null });
  drawCardBack(s, { ...b, signatory: b.signatory ? { title: b.signatory.title, name: b.signatory.name } : undefined }, landscape, qrMatrix(b.qr ?? `MOAUM ID ${clean(b.serial)}`));
  s.end();
}
