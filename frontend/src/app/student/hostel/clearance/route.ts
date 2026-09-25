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

/** the hostel clearance certificate as a PDF (V261): issued once every requirement is cleared, waived or not applicable */
export async function GET(request: Request) {
  const session = new URL(request.url).searchParams.get("session") ?? "";
  const [me, h] = await Promise.all([api<{ name: string; matricNo: string | null; admissionNo: string; programme: string | null }>("/api/v1/me"), api<StudentHostelFull>(`/api/v1/me/hostel/full${session ? `?session=${encodeURIComponent(session)}` : ""}`)]);
  if (!h.ok) return NextResponse.json(h.problem, { status: h.problem.status });
  const v = h.data.view;
  if (v.clearance_state !== "CLEARED" || !v.clearance_ref) return NextResponse.json({ status: 409, title: "No clearance certificate", detail: "The certificate is issued when the hostel clearance is complete." }, { status: 409 });
  const s = me.ok ? me.data : null;
  const p = new Page();
  const L = 60;
  let y = brandHeader(p, L, `Hostel clearance certificate · ${h.data.session} session`);
  p.text(L, y, "HOSTEL CLEARANCE CERTIFICATE", 15, true);
  y -= 16;
  p.text(L, y, `Clearance ${v.clearance_ref} · allocation ${v.allocation_ref}`, 9.5, false, [0.35, 0.35, 0.35]);
  y -= 28;
  const rows: [string, string][] = [
    ["Student", clean(s?.name ?? "")], ["Student ID", clean(s?.matricNo ?? s?.admissionNo ?? "")], ["Programme", clean(s?.programme ?? "—")], ["Session", h.data.session],
    ["Hostel", clean(v.hall_name ?? "—")], ["Block", clean(v.block ?? "—")], ["Room", clean(v.room_no ?? "—")], ["Bed", clean(v.bed_label ?? "—")],
    ["Checked in", day(v.checked_in_at)], ["Checked out", day(v.checked_out_at)],
  ];
  for (const [k, val] of rows) {
    p.text(L, y, k.toUpperCase(), 7.5, false, [0.4, 0.4, 0.4]);
    p.text(L + 110, y, val, 10.5, k === "Student");
    y -= 20;
  }
  y -= 6;
  p.text(L, y, "Requirements", 10, true);
  y -= 16;
  for (const i of h.data.clearanceItems) {
    p.text(L, y, clean(i.label), 9);
    p.text(L + 260, y, i.state.replace(/_/g, " ").toLowerCase(), 9, true);
    if (i.remarks) p.text(L + 350, y, clean(i.remarks).slice(0, 40), 8, false, [0.4, 0.4, 0.4]);
    y -= 14;
  }
  y -= 10;
  y = p.paragraph(L, y, "This certifies that the student named has returned the bed space above, that the room, bed and assets were inspected, keys and access card returned, and that no hostel obligation is outstanding for the session. The hostel unit of the graduation clearance is signed on this record.", A4.w - 2 * L - 110, 9.5);
  const { size, dark } = qrMatrix(`${originOf(request)}${hostelVerifyPath(v.allocation_ref ?? "")}`);
  const side = 92, cell = side / size, qx = A4.w - L - side, qy = 84;
  for (let r = 0; r < size; r++) for (let c = 0; c < size; c++) if (dark[r * size + c]) p.fill(qx + c * cell, qy + (size - 1 - r) * cell, cell, cell, 0);
  p.text(qx - 4, qy - 10, "Scan to verify", 7, false, [0.4, 0.4, 0.4]);
  p.text(L, 62, "Deputy Registrar (Housing, Welfare and Passages)", 9, true);
  p.text(L, 50, `Issued by the portal · ${v.clearance_ref} · verified against the University's record`, 7.5, false, [0.4, 0.4, 0.4]);
  const bytes = pdf([p], `Hostel clearance ${v.clearance_ref}`);
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="hostel-clearance-${v.clearance_ref}.pdf"` } });
}
