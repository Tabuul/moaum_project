import { NextResponse } from "next/server";
import { cookies } from "next/headers";
import { api, API_URL } from "@/lib/api";
import { sessionToken } from "@/lib/session";
import { jpegSize, type Image } from "@/lib/pdf-write";
import { crestImage } from "@/lib/pdf-crest";
import { loadInstitution } from "@/lib/document/institution-server";
import { cardSignatory } from "@/lib/idcard-signatory-server";
import { finishPdf } from "@/lib/document/pdf";
import type { LiveStaffCard } from "@/lib/staff-card-face";
import { staffCardPage } from "@/lib/staff-card-page";

export const dynamic = "force-dynamic";

/**
 * The staff identity card as a printable PDF — portrait (vertical), as the University issues it, for the card desk (?id names the
 * member of staff). Portal gap audit: a person never prints their own card — the card desk produces and issues it.
 * V439: the card printed is the one in the register — its number and validity — and its QR carries the signed check address.
 * V698: the page is the one the print of every staff card repeats (lib/staff-card-page).
 */
export async function GET(req: Request) {
  await loadInstitution();
  const id = new URL(req.url).searchParams.get("id");
  if (!id) {
    return NextResponse.json({ status: 403, title: "The identity card is issued by the card desk", detail: "Your card is printed and handed over in person; your record shows its status." }, { status: 403 });
  }
  const cardR = await api<LiveStaffCard>(`/api/v1/credentials/identity-cards/staff/${encodeURIComponent(id)}/card`);
  if (!cardR.ok) return NextResponse.json(cardR.problem, { status: cardR.problem.status });
  const card = cardR.data;
  if (!card.face.staff_number) {
    return NextResponse.json({ status: 409, title: "No staff number", detail: "A staff identity card carries the staff number the Registry issued; this person has none on record yet." }, { status: 409 });
  }

  let photo: Image | null = null;
  if (card.face.has_photo) {
    try {
      const tok = await sessionToken();
      const office = (await cookies()).get("moaum_office")?.value;
      const headers: Record<string, string> = tok ? { Authorization: `Bearer ${tok}` } : {};
      if (office) headers["X-Active-Office"] = office;
      const res = await fetch(`${API_URL}/api/v1/credentials/identity-cards/staff/${encodeURIComponent(id)}/photo`, { headers, cache: "no-store" });
      // the writer embeds JPEG; a PNG photograph leaves the frame blank on the print (the screen shows it)
      if (res.ok && (res.headers.get("content-type") ?? "").includes("jpeg")) {
        const buf = new Uint8Array(await res.arrayBuffer()); const dim = jpegSize(buf);
        if (dim) photo = { data: buf, width: dim.width, height: dim.height };
      }
    } catch { /* the blank frame */ }
  }

  const page = staffCardPage(card, photo, crestImage(), await cardSignatory(), new URL(req.url).origin);
  if (!page) return NextResponse.json({ status: 409, title: "No staff number" }, { status: 409 });
  const staffNo = card.face.staff_number;
  const bytes = finishPdf([page], `Staff identity card ${staffNo}`, "ID_CARD");
  return new NextResponse(Buffer.from(bytes), {
    status: 200,
    headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="staff-id-${staffNo.replace(/[^A-Za-z0-9]/g, "-")}.pdf"` },
  });
}
