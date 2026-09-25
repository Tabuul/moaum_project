import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import type { StudentHostelFull } from "@/lib/hostel";
import { hostelVerifyPath } from "@/lib/hostel";
import { A4, Page, pdf } from "@/lib/pdf-write";
import { brandHeader } from "@/lib/pdf-crest";
import { qrMatrix } from "@/lib/qr";

export const dynamic = "force-dynamic";

const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");
const clean = (s: string | null | undefined) => (s ?? "").replace(/[^\x20-\x7E]/g, " ").replace(/\s+/g, " ").trim();
function originOf(req: Request): string {
  const h = req.headers;
  const host = h.get("x-forwarded-host") ?? h.get("host");
  const proto = h.get("x-forwarded-proto") ?? "https";
  try { return host ? `${proto}://${host}` : new URL(req.url).origin; } catch { return new URL(req.url).origin; }
}

/** the hostel allocation letter as a PDF (V261): the crest, the student, the placing, the stay, the rules, and a QR the porter verifies */
export async function GET(request: Request) {
  const session = new URL(request.url).searchParams.get("session") ?? "";
  const [me, h] = await Promise.all([api<{ name: string; matricNo: string | null; admissionNo: string; programme: string | null; department: string | null; faculty: string | null; level: number }>("/api/v1/me"), api<StudentHostelFull>(`/api/v1/me/hostel/full${session ? `?session=${encodeURIComponent(session)}` : ""}`)]);
  if (!h.ok) return NextResponse.json(h.problem, { status: h.problem.status });
  const v = h.data.view;
  if (!v.allocation_ref || !v.allocation_state || ["HELD", "LAPSED", "DECLINED", "CANCELLED"].includes(v.allocation_state)) {
    return NextResponse.json({ status: 409, title: "No allocation letter", detail: "The letter is issued once the accommodation fee is confirmed." }, { status: 409 });
  }
  const s = me.ok ? me.data : null;
  const p = new Page();
  const L = 60;
  let y = brandHeader(p, L, `Hostel allocation letter · ${h.data.session} session`);
  p.text(L, y, "HOSTEL ALLOCATION LETTER", 15, true);
  y -= 16;
  p.text(L, y, `Reference ${v.allocation_ref} · issued ${day(new Date().toISOString())}`, 9.5, false, [0.35, 0.35, 0.35]);
  y -= 26;
  const rows: [string, string][] = [
    ["Student", clean(s?.name ?? "")], ["Student ID", clean(s?.matricNo ?? s?.admissionNo ?? "")],
    ["Faculty", clean(s?.faculty ?? "—")], ["Department", clean(s?.department ?? "—")], ["Programme", clean(s?.programme ?? "—")], ["Level", s?.level ? `${s.level} Level` : "—"],
    ["Session", h.data.session], ["Hostel", clean(`${v.hall_name ?? ""}${v.hall_campus ? ` · ${v.hall_campus}` : ""}`)],
    ["Block", clean(v.block ?? "—")], ["Floor", v.floor ? String(v.floor) : "Ground"], ["Room", clean(`${v.room_no ?? "—"}${v.room_type ? ` (${v.room_type})` : ""}`)], ["Bed", clean(v.bed_label ?? `Bed ${v.bed ?? ""}`)],
    ["Stay", `${day(v.start_on)} to ${day(v.end_on)}`], ["Check in from", day(v.start_on)], ["Fee", v.confirmed_at ? `Paid, confirmed ${day(v.confirmed_at)}` : "Not yet confirmed"],
  ];
  const half = Math.ceil(rows.length / 2);
  for (let i = 0; i < rows.length; i++) {
    const col = i < half ? 0 : 1;
    const yy = y - (i % half) * 22;
    const x = L + col * ((A4.w - 2 * L) / 2);
    p.text(x, yy, rows[i][0].toUpperCase(), 7.5, false, [0.4, 0.4, 0.4]);
    p.text(x + 82, yy, rows[i][1], 10.5, ["Room", "Bed", "Hostel"].includes(rows[i][0]));
  }
  y -= half * 22 + 6;
  p.rule(L, y, A4.w - L, y);
  y -= 22;
  y = p.paragraph(L, y, `The Registry allocates the above bed space to the student named for the ${h.data.session} session. The student reports to the porter's lodge of the hall with this letter and a valid University identity card; the porter records the check-in and the condition of the room and its assets. The allocation is personal and may not be exchanged, sublet or transferred except by the housing desk on the record.`, A4.w - 2 * L, 9.5);
  y -= 14;
  p.text(L, y, "Important instructions", 10, true);
  y = p.paragraph(L, y - 16, clean(v.hall_location ? `Location: ${v.hall_location}. ` : "") + "Keep this letter for the whole stay; it is asked for at check-in and at checkout. Report any fault in the room from the portal. A transfer is requested from the portal and takes effect only when approved. At the end of the stay, request checkout on the portal: the room is inspected, damage assessed, keys and access card returned, and clearance completed before the bed is released.", A4.w - 2 * L - 110, 9);
  if (v.rules) {
    y -= 14;
    p.text(L, y, `Hostel rules and regulations (version ${v.rules_version})`, 10, true);
    y = p.paragraph(L, y - 16, clean(v.rules).slice(0, 2600), A4.w - 2 * L - 110, 8.5);
  }
  const { size, dark } = qrMatrix(`${originOf(request)}${hostelVerifyPath(v.allocation_ref)}`);
  const side = 92, cell = side / size, qx = A4.w - L - side, qy = 84;
  for (let r = 0; r < size; r++) for (let c = 0; c < size; c++) if (dark[r * size + c]) p.fill(qx + c * cell, qy + (size - 1 - r) * cell, cell, cell, 0);
  p.text(qx - 4, qy - 10, "Scan to verify this letter", 7, false, [0.4, 0.4, 0.4]);
  p.text(L, 62, "Deputy Registrar (Housing, Welfare and Passages)", 9, true);
  p.text(L, 50, `Issued by the portal · ${v.allocation_ref} · the QR verifies this letter against the University's record`, 7.5, false, [0.4, 0.4, 0.4]);
  const bytes = pdf([p], `Hostel allocation ${v.allocation_ref}`);
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="hostel-allocation-${v.allocation_ref}.pdf"` } });
}
