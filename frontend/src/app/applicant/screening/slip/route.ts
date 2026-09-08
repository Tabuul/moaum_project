import { NextResponse } from "next/server";
import { api, API_URL } from "@/lib/api";
import { sessionToken } from "@/lib/session";
import type { Application } from "@/lib/applicant";
import { A4, Page, jpegSize, pdf } from "@/lib/pdf-write";

export const dynamic = "force-dynamic";

const day = (iso: string) => new Date(iso).toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long", year: "numeric" });
const clock = (t: string) => String(t).slice(0, 5);

/** the screening slip as a PDF: the same facts as the screen, on one A4 page, with the photograph on file */
export async function GET() {
  const me = await api<Application>("/api/v1/applicant/me");
  if (!me.ok) return NextResponse.json(me.problem, { status: me.problem.status });
  const a = me.data;
  const slip = a.screeningSlip;
  if (!slip) return NextResponse.json({ status: 409, title: "No screening slip yet", detail: "The slip appears when the batch is published." }, { status: 409 });

  const p = new Page();
  const L = 60;
  let y = A4.h - 70;
  p.text(L, y, "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI", 12, true);
  y -= 16;
  p.text(L, y, `Post-UTME screening slip · ${a.session} session`, 10);
  y -= 10;
  p.rule(L, y, A4.w - L, y, 1, 0.2);
  y -= 24;

  /* the photograph, top right, if a JPEG is on file */
  const passport = a.documents.find((d) => d.kind === "PASSPORT");
  const token = await sessionToken();
  if (passport && token && passport.contentType === "image/jpeg") {
    const r = await fetch(`${API_URL}/api/v1/applicant/me/documents/${passport.id}/content`, { headers: { authorization: `Bearer ${token}` }, cache: "no-store" }).catch(() => null);
    if (r && r.ok) {
      const bytes = new Uint8Array(await r.arrayBuffer());
      const size = jpegSize(bytes);
      if (size) p.jpeg(A4.w - L - 84, y - 104, 84, 104, { data: bytes, width: size.width, height: size.height });
    }
  } else {
    p.box(A4.w - L - 84, y - 104, 84, 104);
    p.text(A4.w - L - 78, y - 56, "no photograph", 7);
  }

  p.text(L, y, a.name, 16, true);
  y -= 18;
  p.text(L, y, `${a.applicationNo} · JAMB ${a.jambKey}`, 10);
  y -= 14;
  p.text(L, y, `${a.programme ?? ""}${a.faculty ? ` · Faculty of ${a.faculty}` : ""}`, 10);
  y -= 30;
  p.rule(L, y, A4.w - L - 100, y);
  y -= 22;
  const rows: [string, string][] = [
    ["Batch", slip.batch], ["Date", day(slip.heldOn)],
    ["Session", `${clock(slip.startsAt)} – ${clock(slip.endsAt)}`], ["Venue", slip.venue],
    ["Seat", slip.seat], ["Bring", "This slip and photo identification"],
  ];
  for (const [k, v] of rows) {
    p.text(L, y, k.toUpperCase(), 7.5, false, [0.4, 0.4, 0.4]);
    p.text(L + 110, y, v, 11, k === "Seat" || k === "Batch");
    y -= 20;
  }
  y -= 10;
  p.fill(L, y - 74, A4.w - 2 * L, 84);
  p.text(L + 10, y - 4, "What to bring, and what you may not", 10, true);
  y = p.paragraph(L + 10, y - 20, "Bring this slip, printed or on your phone; your JAMB result slip; a valid photo identification document; a dark pen. Do not bring any phone, watch or electronic device into the hall, written material of any kind, or bags — there is no storage at the venue.", A4.w - 2 * L - 20, 9);
  y -= 24;
  y = p.paragraph(L, y, "Your photograph is checked at the door and again at your seat. If the person who arrives is not the person in the photograph, both are reported to the Board and both lose the place. Arrive thirty minutes before your session; the doors close when it begins.", A4.w - 2 * L, 9);
  p.text(L, 50, `Issued by the portal on ${new Date().toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" })} · ${a.applicationNo} · verify against the hall list`, 7.5, false, [0.4, 0.4, 0.4]);

  const bytes = pdf([p], `Screening slip ${a.applicationNo}`);
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="screening-slip-${a.applicationNo.replace(/\//g, "-")}.pdf"` } });
}
