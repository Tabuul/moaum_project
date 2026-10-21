import { NextResponse } from "next/server";
import { cookies } from "next/headers";
import { api, API_URL } from "@/lib/api";
import { sessionToken } from "@/lib/session";
import { A4, Page, jpegSize, type Image } from "@/lib/pdf-write";
import { crestImage } from "@/lib/pdf-crest";
import { C, CARD_PX, clean, drawBack, drawFrontLandscape, type CardFace } from "@/lib/idcard-pdf";
import { loadInstitution } from "@/lib/document/institution-server";
import { cardSignatory } from "@/lib/idcard-signatory-server";
import { finishPdf } from "@/lib/document/pdf";

export const dynamic = "force-dynamic";

/**
 * The student identity card as the card desk prints it (?id names the student): the card in the register — its number and validity —
 * drawn to the same design as on screen, its QR the signed check address (/verify/idcard), so a guard's scan shows the University's
 * record. Only the desk prints; a student sees the card's status on their own page.
 */

const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "2-digit", month: "long", year: "numeric" }) : "—");

interface LiveCard {
  card_no: string; valid_to: string; verify_path: string; name: string; matric_no: string; programme: string | null; faculty: string | null;
  level: number | null; entry_session: string | null; session: string | null; reach_phone: string | null; has_photo: boolean;
  /** V622: the blood group on the record (set at the card desk or by the student's biodata) */
  blood_group?: string | null;
}

export async function GET(req: Request) {
  await loadInstitution();
  const id = new URL(req.url).searchParams.get("id");
  if (!id) return NextResponse.json({ status: 400, title: "Name the student", detail: "The print is made for one student: ?id= their record." }, { status: 400 });
  const r = await api<LiveCard>(`/api/v1/credentials/identity-cards/students/${encodeURIComponent(id)}/card`);
  if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status });
  const s = r.data;

  let photo: Image | null = null;
  if (s.has_photo) {
    try {
      const tok = await sessionToken();
      const office = (await cookies()).get("moaum_office")?.value;
      const headers: Record<string, string> = tok ? { Authorization: `Bearer ${tok}` } : {};
      if (office) headers["X-Active-Office"] = office;
      const res = await fetch(`${API_URL}/api/v1/credentials/identity-cards/students/${encodeURIComponent(id)}/photo`, { headers, cache: "no-store" });
      if (res.ok) { const buf = new Uint8Array(await res.arrayBuffer()); const dim = jpegSize(buf); if (dim) photo = { data: buf, width: dim.width, height: dim.height }; }
    } catch { /* the blank frame, as on screen */ }
  }

  const matric = s.matric_no;
  const face: CardFace = {
    kind: "student", name: s.name, number: matric,
    fields: [
      ["Faculty", s.faculty ?? "—"], ["Level", s.level ? String(s.level) : "—"],
      ["Programme", s.programme ?? "—"], ["Blood group", s.blood_group ?? "—"],
      ["Admitted", (s.entry_session ?? "").slice(0, 4) || "—"], ["Graduates", "—"],
    ],
    foot: [["Session ", false], [s.session ?? "—", true], [" · valid to ", false], [day(s.valid_to), true]],
    serial: s.card_no,
  };

  const signatory = await cardSignatory();
  const p = new Page();
  const crest = crestImage();
  const W = 360, H = Math.round(CARD_PX.h * (W / CARD_PX.w));
  const x0 = (A4.w - W) / 2;
  p.textCenter(A4.w / 2, A4.h - 54, "Rev. Fr. Moses Orshio Adasu University - Student Identity Card", 12, true, C.ink);
  p.textCenter(A4.w / 2, A4.h - 70, `Card ${clean(s.card_no)}, printed at the card desk.`, 8.5, false, C.foot);
  const frontTop = A4.h - 100;
  drawFrontLandscape(p, x0, frontTop - H, W, face, photo, crest);
  p.textCenter(A4.w / 2, frontTop - H - 18, "FRONT", 7, true, C.foot);
  const backTop = frontTop - H - 44;
  drawBack(p, x0, backTop - H, W, H, {
    kind: "student", barcode: matric.replace(/[^A-Za-z0-9]/g, ""), serial: s.card_no, qr: `${new URL(req.url).origin}${s.verify_path}`,
    aside: ["In an emergency", s.reach_phone ? clean(s.reach_phone) : "—"], signatory,
  }, crest);
  p.textCenter(A4.w / 2, backTop - H - 18, "BACK", 7, true, C.foot);
  p.text(x0, 46, `${clean(s.name)} · ${matric} · generated ${day(new Date().toISOString())}`, 7, false, [0.5, 0.5, 0.5]);

  const bytes = finishPdf([p], `Identity card ${matric}`, "ID_CARD");
  return new NextResponse(Buffer.from(bytes), {
    status: 200,
    headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="identity-card-${matric.replace(/[^A-Za-z0-9]/g, "-")}.pdf"` },
  });
}
