import fs from "node:fs";
import path from "node:path";
import { A4, type Image, jpegSize, Page } from "@/lib/pdf-write";

/** The crest as a JPEG image for pdf-write, read once from /public. pdf-write
 *  embeds JPEG (not PNG), so a JPEG copy of the crest lives beside crest.png.
 *  Returns null if it cannot be read, so a document still prints without it. */
let cached: Image | null | undefined;
export function crestImage(): Image | null {
  if (cached !== undefined) return cached;
  try {
    const data = new Uint8Array(fs.readFileSync(path.join(process.cwd(), "public", "crest.jpg")));
    const size = jpegSize(data);
    cached = size ? { data, width: size.width, height: size.height } : null;
  } catch {
    cached = null;
  }
  return cached;
}

/** The branded document header: the crest, the University's name and a subtitle,
 *  and a rule under them. Returns the y to continue writing from. If the crest
 *  cannot be read, the name sits where it always did, so nothing is lost. */
export function brandHeader(p: Page, L: number, subtitle: string): number {
  const img = crestImage();
  const box = 46;
  const top = A4.h - 52;
  const textX = img ? L + box + 12 : L;
  if (img) p.jpeg(L, top - box, box, box, img);
  p.text(textX, top - 13, "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI", 12, true);
  p.text(textX, top - 28, subtitle, 9.5, false, [0.35, 0.35, 0.35]);
  let y = top - box - 6;
  p.rule(L, y, A4.w - L, y, 1, 0.2);
  y -= 26;
  return y;
}
