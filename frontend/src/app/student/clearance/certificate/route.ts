import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import { clearanceVerifyPath } from "@/lib/clearance";
import { A4, Page, pdf } from "@/lib/pdf-write";
import { brandHeader } from "@/lib/pdf-crest";
import { qrMatrix } from "@/lib/qr";

export const dynamic = "force-dynamic";

const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");
const clean = (s: unknown) => String(s ?? "").replace(/[^\x20-\x7E]/g, " ").replace(/\s+/g, " ").trim();
function originOf(req: Request): string {
  const h = req.headers;
  const host = h.get("x-forwarded-host") ?? h.get("host");
  const proto = h.get("x-forwarded-proto") ?? "https";
  try { return host ? `${proto}://${host}` : new URL(req.url).origin; } catch { return new URL(req.url).origin; }
}

interface Certificate {
  reference: string; workflow_label: string; session: string; completed_at: string; surname: string; other_names: string; matric_no: string | null;
  admission_no: string | null; programme: string | null; department: string | null; faculty: string | null; verify_code: string; issued_at: string;
  stages: { label: string; state: string; decided_at: string; officer: string }[];
}

/** the clearance certificate (V415) as a PDF — issued once every office has cleared the student; its QR leads to the
 *  University's public check of the reference with its check code */
export async function GET(request: Request) {
  const process = new URL(request.url).searchParams.get("process") ?? "";
  if (!/^[0-9a-f-]{36}$/.test(process)) return NextResponse.json({ status: 400, title: "No such clearance" }, { status: 400 });
  const c = await api<Certificate>(`/api/v1/me/clearance/${process}/certificate`, { method: "POST", body: {}, reason: "Clearance certificate downloaded" });
  if (!c.ok) return NextResponse.json(c.problem, { status: c.problem.status || 409 });
  const v = c.data;
  const p = new Page();
  const L = 60;
  let y = brandHeader(p, L, `${clean(v.workflow_label)} · ${v.session} session`);
  p.text(L, y, clean(v.workflow_label).toUpperCase() + " CERTIFICATE", 15, true);
  y -= 16;
  p.text(L, y, `Clearance reference ${v.reference}`, 9.5, false, [0.35, 0.35, 0.35]);
  y -= 28;
  const rows: [string, string][] = [
    ["Student", clean(`${v.surname}, ${v.other_names}`)], ["Matriculation number", clean(v.matric_no ?? v.admission_no ?? "—")],
    ["Programme", clean(v.programme ?? "—")], ["Department", clean(v.department ?? "—")], ["Faculty", clean(v.faculty ?? "—")],
    ["Session", v.session], ["Clearance", clean(v.workflow_label)], ["Completed", day(v.completed_at)],
  ];
  for (const [k, val] of rows) {
    p.text(L, y, k.toUpperCase(), 7.5, false, [0.4, 0.4, 0.4]);
    p.text(L + 130, y, val, 10.5, k === "Student");
    y -= 20;
  }
  y -= 6;
  p.text(L, y, "Offices", 10, true);
  y -= 16;
  for (const s of v.stages) {
    p.text(L, y, clean(s.label), 9);
    p.text(L + 200, y, s.state === "NOT_APPLICABLE" ? "not required" : s.state.replace(/_/g, " ").toLowerCase(), 9, true);
    if (s.decided_at) p.text(L + 290, y, `${day(s.decided_at)}${s.officer ? ` · ${clean(s.officer).slice(0, 30)}` : ""}`, 8, false, [0.4, 0.4, 0.4]);
    y -= 14;
  }
  y -= 10;
  y = p.paragraph(L, y, `This certifies that every office of the University required for the ${clean(v.workflow_label).toLowerCase()} of the student named has cleared them on the University's record. It does not of itself confer a degree: graduation remains with Senate.`, A4.w - 2 * L - 110, 9.5);
  const { size, dark } = qrMatrix(`${originOf(request)}${clearanceVerifyPath(v.reference, v.verify_code)}`);
  const side = 92, cell = side / size, qx = A4.w - L - side, qy = 84;
  for (let r = 0; r < size; r++) for (let col = 0; col < size; col++) if (dark[r * size + col]) p.fill(qx + col * cell, qy + (size - 1 - r) * cell, cell, cell, 0);
  p.text(qx - 4, qy - 10, "Scan to verify", 7, false, [0.4, 0.4, 0.4]);
  p.text(L, 62, "Registrar", 9, true);
  p.text(L, 50, `Issued by the portal on ${day(v.issued_at)} · ${v.reference} · verified against the University's record`, 7.5, false, [0.4, 0.4, 0.4]);
  const bytes = pdf([p], `Clearance ${v.reference}`);
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="clearance-${v.reference.replace(/\//g, "-")}.pdf"` } });
}
