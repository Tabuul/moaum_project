/**
 * One staff identity card on an A4 page — front and back side by side, portrait (vertical), as the University issues it — for the
 * card desk's print of one card and (V698) its print of them all, which is these pages one after another.
 */
import { A4, Page, type Image } from "@/lib/pdf-write";
import { C, CARD_PX, clean, drawBack, drawFrontPortrait, type CardBack } from "@/lib/idcard-pdf";
import { staffCardFace, type LiveStaffCard } from "@/lib/staff-card-face";

const day = (iso: string) => new Date(iso).toLocaleDateString("en-GB", { day: "2-digit", month: "long", year: "numeric" });

/** the page, or null for a member of staff with no staff number (a card carries it) */
export function staffCardPage(card: LiveStaffCard, photo: Image | null, crest: Image | null, signatory: CardBack["signatory"], origin: string): Page | null {
  const face = staffCardFace(card);
  if (!face) return null;
  const staffNo = face.number;
  const serial = card.card_no;
  const p = new Page();
  const W = 230, H = Math.round(CARD_PX.w * (W / CARD_PX.h));   // ID-1, portrait
  const gap = 36;
  const x1 = A4.w / 2 - W - gap / 2, x2 = A4.w / 2 + gap / 2;
  p.textCenter(A4.w / 2, A4.h - 54, "Rev. Fr. Moses Orshio Adasu University - Staff Identity Card", 12, true, C.ink);
  p.textCenter(A4.w / 2, A4.h - 70, `Printed for ${clean(face.name)} by the office signed in.`, 8.5, false, C.foot);
  const top = A4.h - 104;
  drawFrontPortrait(p, x1, top - H, W, face, photo, crest);
  p.textCenter(x1 + W / 2, top - H - 18, "FRONT", 7, true, C.foot);
  drawBack(p, x2, top - H, W, H, {
    kind: "staff", barcode: staffNo.replace(/[^A-Za-z0-9]/g, ""), serial, qr: `${origin}${card.verify_path}`,
    aside: ["If found, return to the Security post", "Km 1 Gboko Road, Makurdi"], signatory,
  }, crest);
  p.textCenter(x2 + W / 2, top - H - 18, "BACK", 7, true, C.foot);
  p.text(x1, 46, `${clean(face.name)} · ${staffNo} · generated ${day(new Date().toISOString())}`, 7, false, [0.5, 0.5, 0.5]);
  return p;
}
