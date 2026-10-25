import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import { clearanceVerifyPath } from "@/lib/clearance";
import { A4, Page, pdf } from "@/lib/pdf-write";
import { brandHeader } from "@/lib/pdf-crest";
import { qrMatrix } from "@/lib/qr";
import type { StudentAccount } from "@/lib/historical-fees";

export const dynamic = "force-dynamic";

const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");
const clean = (s: unknown) => String(s ?? "").replace(/[^\x20-\x7E]/g, " ").replace(/\s+/g, " ").trim();
const ngn = (n: unknown) => `NGN ${Number(n ?? 0).toLocaleString("en-NG", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
function originOf(req: Request): string {
  const h = req.headers;
  const host = h.get("x-forwarded-host") ?? h.get("host");
  const proto = h.get("x-forwarded-proto") ?? "https";
  try { return host ? `${proto}://${host}` : new URL(req.url).origin; } catch { return new URL(req.url).origin; }
}

/** V654: the financial clearance certificate of a graduate whose final clearance's Bursary stage is cleared — read from the
 *  historical account (the API checks the office), with the clearance's QR to the University's public check */
export async function GET(request: Request) {
  const student = new URL(request.url).searchParams.get("student") ?? "";
  if (!/^[0-9a-f-]{36}$/.test(student)) return NextResponse.json({ status: 400, title: "No such student" }, { status: 400 });
  const r = await api<StudentAccount>(`/api/v1/finance/historical/students/${student}`);
  if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status || 409 });
  const a = r.data;
  const c = a.clearance;
  if (!c || c.bursary !== "CLEARED") {
    return NextResponse.json({ status: 409, title: "Not cleared", detail: "The financial clearance certificate is issued once the final clearance's Bursary stage is cleared." }, { status: 409 });
  }
  const s = a.student;
  const assessed = a.periods.reduce((n, x) => n + Number(x.assessed ?? 0), 0);
  const paid = a.periods.reduce((n, x) => n + Number(x.paid ?? 0), 0);
  const p = new Page();
  const L = 60;
  let y = brandHeader(p, L, `Bursary · financial clearance`);
  p.text(L, y, "FINANCIAL CLEARANCE CERTIFICATE", 15, true);
  y -= 16;
  p.text(L, y, `Clearance reference ${c.reference}`, 9.5, false, [0.35, 0.35, 0.35]);
  y -= 28;
  const rows: [string, string][] = [
    ["Student", clean(`${s.surname}, ${s.other_names}`)], ["Matriculation number", clean(s.matric_no ?? s.admission_no ?? "—")], ["JAMB number", clean(s.jamb_reg_no ?? "—")],
    ["Faculty", clean(s.faculty ?? "—")], ["Department", clean(s.department ?? "—")], ["Programme", clean(s.programme)],
    ["Graduation session", clean(s.graduation_session ?? "—")], ["Financial clearance", "CLEARED - no outstanding school fees"],
    ["Historical school fees", `${ngn(assessed)} assessed, ${ngn(paid)} paid`], ["Cleared by the Bursary", day(c.bursary_at)],
  ];
  for (const [k, val] of rows) {
    p.text(L, y, k.toUpperCase(), 7.5, false, [0.4, 0.4, 0.4]);
    p.text(L + 150, y, val, 10.5, k === "Student" || k === "Financial clearance");
    y -= 20;
  }
  y -= 10;
  p.paragraph(L, y, "This certifies that the student named has no outstanding school-fee obligation to the University on the historical account of the sessions of their record, assessed at the University's fees for each session and level or by an assessment the Bursar approved, against the payments confirmed for each session. It does not of itself confer a degree: graduation remains with Senate.", A4.w - 2 * L - 110, 9.5);
  const { size, dark } = qrMatrix(`${originOf(request)}${clearanceVerifyPath(c.reference, c.verify_code)}`);
  const side = 92, cell = side / size, qx = A4.w - L - side, qy = 84;
  for (let rr = 0; rr < size; rr++) for (let col = 0; col < size; col++) if (dark[rr * size + col]) p.fill(qx + col * cell, qy + (size - 1 - rr) * cell, cell, cell, 0);
  p.text(qx - 4, qy - 10, "Scan to verify", 7, false, [0.4, 0.4, 0.4]);
  p.text(L, 74, "______________________________", 9);
  p.text(L, 62, "Bursar / authorised officer", 9, true);
  p.text(L, 50, `Issued by the portal on ${day(new Date().toISOString())} · ${c.reference} · verified against the University's record`, 7.5, false, [0.4, 0.4, 0.4]);
  const bytes = pdf([p], `Financial clearance ${c.reference}`);
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="financial-clearance-${c.reference.replace(/\//g, "-")}.pdf"` } });
}
