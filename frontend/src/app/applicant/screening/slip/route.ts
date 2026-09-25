import { NextResponse } from "next/server";
import { api, API_URL } from "@/lib/api";
import { sessionToken } from "@/lib/session";
import { putmeVerifyPath, reportingTime, type Application } from "@/lib/applicant";
import { A4, Page, jpegSize, pdf } from "@/lib/pdf-write";
import { brandHeader } from "@/lib/pdf-crest";
import { qrMatrix } from "@/lib/qr";

export const dynamic = "force-dynamic";

const day = (iso: string) => new Date(iso).toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long", year: "numeric" });
const clock = (t: string) => String(t).slice(0, 5);
const clean = (s: string | null | undefined) => (s ?? "").replace(/[^\x20-\x7E]/g, " ").replace(/\s+/g, " ").trim();

function originOf(req: Request): string {
  const h = req.headers;
  const host = h.get("x-forwarded-host") ?? h.get("host");
  const proto = h.get("x-forwarded-proto") ?? "https";
  try { return host ? `${proto}://${host}` : new URL(req.url).origin; } catch { return new URL(req.url).origin; }
}

/** the examination slip as a PDF (V260): the crest, the same facts as the screen, the photograph on file, and the QR the door scans */
export async function GET(request: Request) {
  const me = await api<Application>("/api/v1/applicant/me");
  if (!me.ok) return NextResponse.json(me.problem, { status: me.problem.status });
  const a = me.data;
  const slip = a.screeningSlip;
  if (!slip) return NextResponse.json({ status: 409, title: "No examination slip yet", detail: "The slip appears when the schedule is published." }, { status: 409 });

  const p = new Page();
  const L = 60;
  let y = brandHeader(p, L, `${clean(slip.examName) || "Post-UTME examination slip"} · ${a.session} session`);

  /* the photograph, top right, if a JPEG is on file */
  const passport = a.documents.find((d) => d.kind === "PASSPORT");
  const token = await sessionToken();
  let drawn = false;
  if (passport && token && passport.contentType === "image/jpeg") {
    const r = await fetch(`${API_URL}/api/v1/applicant/me/documents/${passport.id}/content`, { headers: { authorization: `Bearer ${token}` }, cache: "no-store" }).catch(() => null);
    if (r && r.ok) {
      const bytes = new Uint8Array(await r.arrayBuffer());
      const size = jpegSize(bytes);
      if (size) { p.jpeg(A4.w - L - 84, y - 104, 84, 104, { data: bytes, width: size.width, height: size.height }); drawn = true; }
    }
  }
  if (!drawn) {
    p.box(A4.w - L - 84, y - 104, 84, 104);
    p.text(A4.w - L - 78, y - 56, "no photograph", 7);
  }

  p.text(L, y, clean(a.name), 16, true);
  y -= 18;
  p.text(L, y, `${a.applicationNo} · JAMB ${a.jambKey}`, 10);
  y -= 14;
  p.text(L, y, clean(`${a.programme ?? ""}${a.faculty ? ` · Faculty of ${a.faculty}` : ""}`), 10);
  y -= 14;
  if (slip.batchState === "POSTPONED" || slip.batchState === "CANCELLED") p.text(L, y, `THIS BATCH IS ${slip.batchState} — a new date will be published`, 9, true, [0.7, 0.1, 0.1]);
  y -= 26;
  p.rule(L, y, A4.w - L - 100, y);
  y -= 22;
  const rows: [string, string][] = [
    ["Batch", slip.batch], ["Date", day(slip.heldOn)],
    ["Report by", reportingTime(slip)], ["Examination", `${clock(slip.startsAt)} – ${clock(slip.endsAt)}`],
    ["Centre", clean(slip.centre ? `${slip.centre}${slip.centreLocation ? ` · ${slip.centreLocation}` : ""}` : slip.venue)],
    ["Room", clean(slip.room) || "—"], ["Seat", slip.seat], ["Workstation", clean(slip.workstation) || "Assigned at the seat"],
  ];
  for (const [k, v] of rows) {
    p.text(L, y, k.toUpperCase(), 7.5, false, [0.4, 0.4, 0.4]);
    p.text(L + 110, y, v, 11, k === "Seat" || k === "Batch" || k === "Report by");
    y -= 20;
  }
  if (slip.centreAddress) { y = p.paragraph(L + 110, y + 4, clean(slip.centreAddress), A4.w - 2 * L - 110, 8.5); y -= 10; }

  /* the QR, bottom right of the facts: the door scans it and the portal answers with the record */
  if (slip.token) {
    const { size, dark } = qrMatrix(`${originOf(request)}${putmeVerifyPath(slip.token)}`);
    const side = 92, cell = side / size, qx = A4.w - L - side, qy = y + 6;
    for (let r = 0; r < size; r++) for (let c = 0; c < size; c++) if (dark[r * size + c]) p.fill(qx + c * cell, qy + (size - 1 - r) * cell, cell, cell, 0);
    p.text(qx - 2, qy - 10, "Scan to verify at the door", 7, false, [0.4, 0.4, 0.4]);
  }
  y -= 8;
  const instr = clean(slip.instructions);
  if (instr) {
    p.text(L, y, "Examination instructions", 10, true);
    y = p.paragraph(L, y - 16, instr, A4.w - 2 * L - 110, 9);
    y -= 14;
  }
  p.fill(L, y - 74, A4.w - 2 * L, 84);
  p.text(L + 10, y - 4, "What to bring, and what you may not", 10, true);
  y = p.paragraph(L + 10, y - 20, "Bring this slip, printed or on your phone; your JAMB result slip; a valid photo identification document; a dark pen. Do not bring any phone, watch or electronic device into the hall, written material of any kind, or bags — there is no storage at the venue.", A4.w - 2 * L - 20, 9);
  y -= 24;
  y = p.paragraph(L, y, `Your photograph is checked at the door and again at your seat. If the person who arrives is not the person in the photograph, both are reported to the Board and both lose the place. Report by ${reportingTime(slip)}; check-in closes when the batch begins at ${clock(slip.startsAt)}.${slip.contact ? ` Enquiries: ${clean(slip.contact)}.` : ""}`, A4.w - 2 * L, 9);
  p.text(L, 50, `Issued by the portal on ${new Date().toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" })} · ${a.applicationNo} · the QR verifies this slip against the University's record`, 7.5, false, [0.4, 0.4, 0.4]);

  const bytes = pdf([p], `Examination slip ${a.applicationNo}`);
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="putme-slip-${a.applicationNo.replace(/\//g, "-")}.pdf"` } });
}
