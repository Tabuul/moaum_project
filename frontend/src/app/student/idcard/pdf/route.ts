import { NextResponse } from "next/server";
import { api, API_URL } from "@/lib/api";
import { sessionToken } from "@/lib/session";
import type { Me, Card } from "@/lib/student-portal";
import { A4, Page, pdf, jpegSize, type Image } from "@/lib/pdf-write";
import { crestImage } from "@/lib/pdf-crest";
import { C, CARD_PX, clean, drawBack, drawFrontLandscape, type CardFace } from "@/lib/idcard-pdf";

export const dynamic = "force-dynamic";

const day = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "2-digit", month: "long", year: "numeric" }) : "—");

/** the student identity card as a printable PDF — front and back, drawn to the same design as on screen (idcard.tsx) */
export async function GET() {
  const meR = await api<Me>("/api/v1/me");
  if (!meR.ok) return NextResponse.json(meR.problem, { status: meR.problem.status });
  const s = meR.data;
  const cardR = await api<Card>("/api/v1/me/id-card");
  if (!cardR.ok) return NextResponse.json(cardR.problem, { status: cardR.problem.status });
  const live = cardR.data.cards.find((x) => x.state === "ISSUED") ?? null;
  if (!live) {
    return NextResponse.json({ status: 409, title: "No identity card issued", detail: "The Library prints your card after matriculation and clearance; there is nothing to print yet." }, { status: 409 });
  }

  let photo: Image | null = null;
  try {
    const tok = await sessionToken();
    const res = await fetch(`${API_URL}/api/v1/me/passport`, { headers: tok ? { Authorization: `Bearer ${tok}` } : {}, cache: "no-store" });
    if (res.ok) { const buf = new Uint8Array(await res.arrayBuffer()); const dim = jpegSize(buf); if (dim) photo = { data: buf, width: dim.width, height: dim.height }; }
  } catch { /* the blank frame, as on screen */ }

  const matric = s.matricNo ?? "";
  const kin = s.contact?.reach_phone ?? null;
  const face: CardFace = {
    name: s.name, number: matric, tag: "Student",
    fields: [
      ["Faculty", s.faculty], ["Level", String(s.level)],
      ["Programme", s.programme], ["Blood group", "—"],
      ["Admitted", (s.entrySession ?? "").slice(0, 4) || "—"], ["Graduates", "—"],
    ],
    foot: [["Session ", false], [s.session, true], [" · valid to ", false], [day(live.valid_to), true]],
    serial: live.card_no,
  };

  const p = new Page();
  const crest = crestImage();
  const W = 360, H = Math.round(CARD_PX.h * (W / CARD_PX.w));
  const x0 = (A4.w - W) / 2;
  p.textCenter(A4.w / 2, A4.h - 54, "Rev. Fr. Moses Orshio Adasu University - Student Identity Card", 12, true, C.ink);
  p.textCenter(A4.w / 2, A4.h - 70, "A printed copy of your card. The card itself is issued by the Library.", 8.5, false, C.foot);
  const frontTop = A4.h - 100;
  drawFrontLandscape(p, x0, frontTop - H, W, face, photo, crest);
  p.textCenter(A4.w / 2, frontTop - H - 18, "FRONT", 7, true, C.foot);
  const backTop = frontTop - H - 44;
  drawBack(p, x0, backTop - H, W, H, {
    barcode: matric.replace(/[^A-Za-z0-9]/g, ""), serial: live.card_no,
    aside: ["In an emergency", kin ? clean(kin) : "—"],
  });
  p.textCenter(A4.w / 2, backTop - H - 18, "BACK", 7, true, C.foot);
  p.text(x0, 46, `${clean(s.name)} · ${matric} · generated ${day(new Date().toISOString())}`, 7, false, [0.5, 0.5, 0.5]);

  const bytes = pdf([p], `Identity card ${matric}`);
  return new NextResponse(Buffer.from(bytes), {
    status: 200,
    headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="identity-card-${matric.replace(/[^A-Za-z0-9]/g, "-")}.pdf"` },
  });
}
