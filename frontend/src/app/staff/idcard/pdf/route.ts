import { NextResponse } from "next/server";
import { cookies } from "next/headers";
import { api, API_URL } from "@/lib/api";
import { sessionToken } from "@/lib/session";
import { A4, Page, pdf, jpegSize, type Image } from "@/lib/pdf-write";
import { crestImage } from "@/lib/pdf-crest";
import { C, CARD_PX, clean, drawBack, drawFrontPortrait, type CardFace } from "@/lib/idcard-pdf";

export const dynamic = "force-dynamic";

/**
 * The staff identity card as a printable PDF — portrait (vertical), as the University issues it, drawn
 * to the same design as the student card on screen. Without ?id the card is the signed-in person's own;
 * with ?id it is the named member of staff's, for the offices that read the staff register.
 */

const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "2-digit", month: "long", year: "numeric" }) : "—");
const rankCase = (r: string | null) => (r ? r.toLowerCase().replace(/\b[a-z]/g, (c) => c.toUpperCase()).replace(/\bIi\b/g, "II") : "");

interface Person {
  id: string; staff_number: string | null; surname: string; given_names: string; rank: string | null; department: string | null;
  faculty: string | null; category: string | null; date_first_appointment: string | null; appointment_date: string | null;
  status: string; has_photo: boolean; phone: string | null; email: string | null;
}
interface Office { office: string; office_code: string; live: boolean }
interface StaffRecord { person: Person; offices: Office[] }

export async function GET(req: Request) {
  const id = new URL(req.url).searchParams.get("id");
  const self = !id;
  const r = await api<StaffRecord>(self ? "/api/v1/hr/staff/me" : `/api/v1/hr/staff/${encodeURIComponent(id!)}`);
  if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status });
  const s = r.data.person;
  if (!s.staff_number) {
    return NextResponse.json({ status: 409, title: "No staff number", detail: "A staff identity card carries the staff number the Registry issued; this person has none on record yet." }, { status: 409 });
  }

  let photo: Image | null = null;
  if (s.has_photo) {
    try {
      const tok = await sessionToken();
      const office = (await cookies()).get("moaum_office")?.value;
      const headers: Record<string, string> = tok ? { Authorization: `Bearer ${tok}` } : {};
      if (office) headers["X-Active-Office"] = office;
      const res = await fetch(`${API_URL}${self ? "/api/v1/hr/staff/me/photo" : `/api/v1/hr/staff/${encodeURIComponent(id!)}/photo`}`, { headers, cache: "no-store" });
      // the writer embeds JPEG; a PNG photograph leaves the frame blank on the print (the screen shows it)
      if (res.ok && (res.headers.get("content-type") ?? "").includes("jpeg")) {
        const buf = new Uint8Array(await res.arrayBuffer()); const dim = jpegSize(buf);
        if (dim) photo = { data: buf, width: dim.width, height: dim.height };
      }
    } catch { /* the blank frame */ }
  }

  const live = r.data.offices.filter((o) => o.live);
  const office = live.find((o) => o.office_code !== "lecturer")?.office ?? live[0]?.office ?? "";
  const academic = s.category === "ACADEMIC" || (!s.category && live.some((o) => ["lecturer", "hod", "dean"].includes(o.office_code)));
  const expiresOn = new Date(); expiresOn.setFullYear(expiresOn.getFullYear() + 3); expiresOn.setMonth(11, 31);
  const staffNo = s.staff_number;
  const serial = `STF-${staffNo.replace(/[^A-Za-z0-9]/g, "").slice(-8)}-${new Date().getFullYear()}`;
  const face: CardFace = {
    name: `${s.surname}, ${s.given_names}`, number: staffNo, tag: "Staff",
    fields: [
      ["Rank", rankCase(s.rank) || office || "—"], ["Category", academic ? "Academic" : s.category ? "Non-teaching" : "Staff"],
      [s.faculty ? "Department" : "Unit", s.department ?? office ?? "—"], ["Faculty", s.faculty ?? "—"],
      ["Appointed", day(s.date_first_appointment ?? s.appointment_date)], ["Office", office || "—"],
    ],
    foot: [["Valid to ", false], [day(expiresOn.toISOString()), true]],
    serial,
  };

  const p = new Page();
  const crest = crestImage();
  const W = 230, H = Math.round(CARD_PX.w * (W / CARD_PX.h));   // ID-1, portrait
  const gap = 36;
  const x1 = A4.w / 2 - W - gap / 2, x2 = A4.w / 2 + gap / 2;
  p.textCenter(A4.w / 2, A4.h - 54, "Rev. Fr. Moses Orshio Adasu University - Staff Identity Card", 12, true, C.ink);
  p.textCenter(A4.w / 2, A4.h - 70, self ? "A printed copy of your card. The card itself is issued by the Registry." : `Printed for ${clean(face.name)} by the office signed in.`, 8.5, false, C.foot);
  const top = A4.h - 104;
  drawFrontPortrait(p, x1, top - H, W, face, photo, crest);
  p.textCenter(x1 + W / 2, top - H - 18, "FRONT", 7, true, C.foot);
  drawBack(p, x2, top - H, W, H, {
    barcode: staffNo.replace(/[^A-Za-z0-9]/g, ""), serial,
    aside: ["If found, return to the Security post", "Km 1 Gboko Road, Makurdi"],
  }, crest);
  p.textCenter(x2 + W / 2, top - H - 18, "BACK", 7, true, C.foot);
  p.text(x1, 46, `${clean(face.name)} · ${staffNo} · generated ${day(new Date().toISOString())}`, 7, false, [0.5, 0.5, 0.5]);

  const bytes = pdf([p], `Staff identity card ${staffNo}`);
  return new NextResponse(Buffer.from(bytes), {
    status: 200,
    headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="staff-id-${staffNo.replace(/[^A-Za-z0-9]/g, "-")}.pdf"` },
  });
}
