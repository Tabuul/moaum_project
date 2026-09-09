import { NextRequest, NextResponse } from "next/server";
import { api } from "@/lib/api";
import type { Me, RegistrationView } from "@/lib/student-portal";
import { A4, Page, pdf } from "@/lib/pdf-write";
import { brandHeader } from "@/lib/pdf-crest";

export const dynamic = "force-dynamic";

const day = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");

/** the course registration form as a PDF: what the Head of Department approved, and nothing else */
export async function GET(request: NextRequest) {
  const q = request.nextUrl.searchParams;
  const me = await api<Me>("/api/v1/me");
  if (!me.ok) return NextResponse.json(me.problem, { status: me.problem.status });
  const s = me.data;
  const session = /^\d{4}\/\d{4}$/.test(q.get("session") ?? "") ? (q.get("session") as string) : s.session;
  const semester = q.get("semester") === "2" ? 2 : q.get("semester") === "3" ? 3 : 1;
  const v = await api<RegistrationView>(`/api/v1/me/registration?session=${encodeURIComponent(session)}&semester=${semester}`);
  if (!v.ok) return NextResponse.json(v.problem, { status: v.problem.status });
  const reg = v.data.registration;
  if (!reg || !(reg.status === "APPROVED" || reg.status === "LOCKED")) {
    return NextResponse.json({ status: 409, title: "Not approved", detail: "The form is issued when the registration is approved." }, { status: 409 });
  }
  const p = new Page();
  const L = 64;
  let y = brandHeader(p, L, "Course Registration Form");
  for (const [k, val] of [["Name", s.name], ["Matriculation number", s.matricNo ?? s.admissionNo ?? ""], ["Programme", `${s.programme}`], ["Level", String(reg.level)], ["Session", `${session} · semester ${semester}`]]) {
    p.text(L, y, k.toUpperCase(), 7.5, false, [0.4, 0.4, 0.4]);
    p.text(L + 150, y, val, 10.5);
    y -= 17;
  }
  y -= 10;
  p.fill(L, y - 4, A4.w - 2 * L, 18, 0.2);
  p.text(L + 8, y, "COURSE", 8, true, [1, 1, 1]);
  p.text(A4.w - L - 130, y, "UNIT", 8, true, [1, 1, 1]);
  p.text(A4.w - L - 60, y, "TYPE", 8, true, [1, 1, 1]);
  y -= 22;
  for (const e of reg.entries) {
    p.text(L + 8, y, `${e.courseCode}  ${e.title}`, 10);
    p.text(A4.w - L - 125, y, String(e.units), 10);
    p.text(A4.w - L - 60, y, e.entryType === "CARRYOVER" ? "C/OVER" : e.entryType === "ELECTIVE" ? "ELECT" : e.entryType === "GST" ? "GST" : e.entryType === "BORROWED" ? "BORROW" : "CORE", 8, true, e.entryType === "CARRYOVER" ? [0.7, 0.1, 0.1] : [0.4, 0.4, 0.4]);
    y -= 17;
  }
  p.rule(L, y + 6, A4.w - L, y + 6);
  p.text(L + 8, y - 8, "TOTAL CREDIT UNITS", 10.5, true);
  p.text(A4.w - L - 125, y - 8, String(reg.units), 12, true);
  y -= 40;
  p.text(L, y, `Approved by the Head of Department on ${day(reg.approved_at)}`, 10, true, [0.1, 0.4, 0.2]);
  y -= 24;
  y = p.paragraph(L, y, "The register is the thing; this form is a view of it. The class lists, the attendance register, the examination roll and the score sheets are drawn from the approved entries above and nothing else.", A4.w - 2 * L, 9);
  p.text(L, 50, `Issued by the portal on ${day(new Date().toISOString())} · ${reg.id.slice(0, 8).toUpperCase()}`, 7.5, false, [0.4, 0.4, 0.4]);
  const bytes = pdf([p], `Course form ${s.matricNo ?? ""}`);
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="course-form-${session.replace("/", "-")}-${semester}.pdf"` } });
}
