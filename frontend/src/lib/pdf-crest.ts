import fs from "node:fs";
import path from "node:path";
import { A4, type Image, jpegSize, Page } from "./pdf-write.ts";
import { currentInstitution, currentLogo } from "./document/institution-cache.ts";
import { addressLine, contactLine, nameUpper } from "./document/institution.ts";

/** The built-in crest as a JPEG image for pdf-write, read once from /public. pdf-write embeds JPEG
 *  (not PNG), so a JPEG copy of the crest lives beside crest.png. Null if it cannot be read. */
let cached: Image | null | undefined;
function fileCrest(): Image | null {
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

/** The University's logo for a PDF (V320): the one on the institution profile once a route has loaded it
 *  (loadInstitution), else the built-in crest, else null — so a document still prints without it. */
export function crestImage(): Image | null {
  return currentLogo() ?? fileCrest();
}

/** A signatory's signature as a JPEG for pdf-write, read once from /public/signatures/<name>.jpg — for example
 *  signatures/registrar.jpg for the letter of admission. Null when the file is not there, so the letter prints
 *  with the space above the name left for a hand signature. */
const signatures = new Map<string, Image | null>();
export function signatureImage(name: string): Image | null {
  const hit = signatures.get(name);
  if (hit !== undefined) return hit;
  let img: Image | null = null;
  try {
    const data = new Uint8Array(fs.readFileSync(path.join(process.cwd(), "public", "signatures", `${name.replace(/[^a-z0-9_-]/gi, "")}.jpg`)));
    const size = jpegSize(data);
    img = size ? { data, width: size.width, height: size.height } : null;
  } catch {
    img = null;
  }
  signatures.set(name, img);
  return img;
}

/** The branded document header (V320): the logo, the University's name, its motto and contacts from the
 *  institution profile, a subtitle, and a rule under them. Returns the y to continue writing from. If the
 *  logo cannot be read, the name sits where it always did, so nothing is lost. */
export function brandHeader(p: Page, L: number, subtitle: string): number {
  const inst = currentInstitution();
  const img = crestImage();
  const box = 46;
  const top = A4.h - 52;
  const textX = img ? L + box + 12 : L;
  if (img) {
    const ratio = img.width && img.height ? img.width / img.height : 1;
    const w = ratio >= 1 ? box : box * ratio, h = ratio >= 1 ? box / ratio : box;
    p.jpeg(L + (box - w) / 2, top - box + (box - h) / 2, w, h, img);
  }
  const clean = (s: string) => s.replace(/[^\x20-\x7E]/g, " ").replace(/\s+/g, " ").trim();
  const name = clean(nameUpper(inst));
  p.text(textX, top - 13, name.length > 62 ? name.slice(0, 61) + "…" : name, 12, true);
  let ty = top - 26;
  if (inst.motto) { p.textStyled(textX, ty, clean(`"${inst.motto}"`), 8.5, { font: "F5", colour: [0.4, 0.4, 0.4] }); ty -= 10; }
  const line = [addressLine(inst), contactLine(inst)].filter(Boolean).join("  ·  ");
  if (line) { p.text(textX, ty, clean(line).slice(0, 110), 7.5, false, [0.4, 0.4, 0.4]); ty -= 10; }
  p.text(textX, ty, subtitle, 9.5, false, [0.35, 0.35, 0.35]);
  let y = Math.min(top - box, ty - 6) - 6;
  p.rule(L, y, A4.w - L, y, 1, 0.2);
  y -= 26;
  return y;
}
