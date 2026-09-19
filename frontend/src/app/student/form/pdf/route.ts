import { NextRequest, NextResponse } from "next/server";
import { api, API_URL } from "@/lib/api";
import { sessionToken } from "@/lib/session";
import type { Me, RegistrationView, Entry } from "@/lib/student-portal";
import { A4, Page, pdf, jpegSize } from "@/lib/pdf-write";
import { brandHeader } from "@/lib/pdf-crest";

export const dynamic = "force-dynamic";

const day = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");
const clean = (s: string | null | undefined) => (s ?? "").replace(/[^\x20-\x7E]/g, " ").replace(/\s+/g, " ").trim();
const cut = (s: string, n: number) => (s.length > n ? s.slice(0, n - 1).trimEnd() + "..." : s);

/** GST / Elective / Core (Compulsory/Required → Core) */
function courseType(e: Entry): string {
  const k = (e.kind ?? "").toLowerCase();
  if (k === "gst") return "GST";
  if (k === "elective") return "Elective";
  if (k === "compulsory" || k === "required") return "Core";
  const t = (e.entryType ?? "").toUpperCase();
  return t === "GST" ? "GST" : t === "ELECTIVE" ? "Elective" : "Core";
}

/** the course registration form as a PDF: what the Head of Department approved, with the student's passport */
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

  // the passport, embedded as JPEG (blank box when none) — resolved from the document store OR the
  // JAMB/attachment store, so a migrated / JAMB-loaded student's photo also prints
  let photo: { width: number; height: number; data: Uint8Array } | null = null;
  try {
    const tok = await sessionToken();
    const res = await fetch(`${API_URL}/api/v1/me/passport`, { headers: tok ? { Authorization: `Bearer ${tok}` } : {}, cache: "no-store" });
    if (res.ok) {
      const buf = new Uint8Array(await res.arrayBuffer());
      const dim = jpegSize(buf);
      if (dim) photo = { width: dim.width, height: dim.height, data: buf };
    }
  } catch { /* leave the box blank */ }

  const p = new Page();
  const L = 64;
  let y = brandHeader(p, L, "Course Registration Form");

  // passport at the top-right, aligned with the candidate block
  const pw = 62, ph = 76, px = A4.w - L - pw, ptop = y + 6;
  if (photo) p.jpeg(px, ptop - ph, pw, ph, photo);
  else { p.rule(px, ptop, px + pw, ptop, 0.6, 0.7); p.rule(px, ptop - ph, px + pw, ptop - ph, 0.6, 0.7); p.rule(px, ptop, px, ptop - ph, 0.6, 0.7); p.rule(px + pw, ptop, px + pw, ptop - ph, 0.6, 0.7); p.text(px + 12, ptop - ph / 2, "PHOTO", 7.5, false, [0.6, 0.6, 0.6]); }

  for (const [k, val] of [["Name", clean(s.name)], ["Matriculation number", s.matricNo ?? s.admissionNo ?? ""], ["Programme", clean(s.programme)], ["Level", `${reg.level} Level`], ["Session", `${session} · semester ${semester}`]]) {
    p.text(L, y, k.toUpperCase(), 7.5, false, [0.4, 0.4, 0.4]);
    p.text(L + 150, y, val, 10.5);
    y -= 17;
  }
  y = Math.min(y, ptop - ph) - 10;

  // ── table: course · lecturer · unit · type, carryovers first ──
  const lecX = A4.w - L - 200, unitX = A4.w - L - 92, typeX = A4.w - L - 46;
  p.fill(L, y - 4, A4.w - 2 * L, 18, 0.2);
  p.text(L + 8, y, "COURSE", 8, true, [1, 1, 1]);
  p.text(lecX, y, "LECTURER", 8, true, [1, 1, 1]);
  p.text(unitX, y, "UNIT", 8, true, [1, 1, 1]);
  p.text(typeX, y, "TYPE", 8, true, [1, 1, 1]);
  y -= 22;
  for (const e of reg.entries) {
    const co = e.entryType === "CARRYOVER";
    p.text(L + 8, y, clean(e.courseCode), 9, true, co ? [0.72, 0.11, 0.11] : [0, 0, 0]);
    p.text(L + 8 + Math.min(clean(e.courseCode).length * 5.6 + 8, 74), y, cut(clean(e.title), 34), 9, false, [0.2, 0.2, 0.2]);
    p.text(lecX, y, cut(clean(e.lecturer) || "—", 22), 8.5, false, [0.3, 0.3, 0.3]);
    p.text(unitX, y, String(e.units), 9);
    p.text(typeX, y, courseType(e), 8.5, true, [0.35, 0.35, 0.35]);
    if (co) p.text(lecX, y - 8, "carryover", 6.5, false, [0.72, 0.11, 0.11]);
    y -= co ? 19 : 16;
  }
  p.rule(L, y + 6, A4.w - L, y + 6);
  p.text(L + 8, y - 8, "TOTAL CREDIT UNITS", 10.5, true);
  p.text(unitX, y - 8, String(reg.units), 12, true);
  y -= 40;
  p.text(L, y, `Approved by the Head of Department on ${day(reg.approved_at)}`, 10, true, [0.1, 0.4, 0.2]);
  y -= 24;
  y = p.paragraph(L, y, "The register is the thing; this form is a view of it. The class lists, the attendance register, the examination roll and the score sheets are drawn from the approved entries above and nothing else. A carryover is a course failed earlier and repeated this semester.", A4.w - 2 * L, 9);
  p.text(L, 50, `Issued by the portal on ${day(new Date().toISOString())} · ${reg.id.slice(0, 8).toUpperCase()}`, 7.5, false, [0.4, 0.4, 0.4]);
  const bytes = pdf([p], `Course form ${s.matricNo ?? ""}`);
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="course-form-${session.replace("/", "-")}-${semester}.pdf"` } });
}
