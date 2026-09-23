import { NextRequest, NextResponse } from "next/server";
import { api, API_URL } from "@/lib/api";
import { sessionToken } from "@/lib/session";
import type { Me, RegistrationView, Entry } from "@/lib/student-portal";
import { semesterName } from "@/lib/student-portal";
import { A4, Page, pdf, jpegSize } from "@/lib/pdf-write";
import { brandHeader } from "@/lib/pdf-crest";
import { qrMatrix, regToken, regVerifyPath } from "@/lib/qr";

export const dynamic = "force-dynamic";

const day = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");
const clean = (s: string | null | undefined) => (s ?? "").replace(/[^\x20-\x7E]/g, " ").replace(/\s+/g, " ").trim();
const cut = (s: string, n: number) => (s.length > n ? s.slice(0, n - 1).trimEnd() + "..." : s);
function originOf(req: Request): string {
  const h = req.headers;
  const host = h.get("x-forwarded-host") ?? h.get("host");
  const proto = h.get("x-forwarded-proto") ?? "https";
  try { return host ? `${proto}://${host}` : new URL(req.url).origin; } catch { return new URL(req.url).origin; }
}

/** GST / Elective / Core (Core/Required → Core) */
/** display order: carryover first, then GST, then Core, then Elective */
function orderRank(e: Entry): number {
  if ((e.entryType ?? "").toUpperCase() === "CARRYOVER") return 0;
  const t = courseType(e);
  return t === "GST" ? 1 : t === "Core" ? 2 : 3;
}

function courseType(e: Entry): string {
  const k = (e.kind ?? "").toLowerCase();
  if (k === "gst") return "GST";
  if (k === "elective") return "Elective";
  if (k === "core" || k === "compulsory" || k === "required") return "Core";
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

  const regDate = day(reg.submitted_at ?? reg.approved_at);
  for (const [k, val] of [["Name", clean(s.name)], ["Matriculation number", s.matricNo ?? s.admissionNo ?? ""], ["Programme", clean(s.programme)], ["Level", `${reg.level} Level`], ["Session", session], ["Semester", semesterName(semester)], ["Date of registration", regDate]]) {
    p.text(L, y, k.toUpperCase(), 7.5, false, [0.4, 0.4, 0.4]);
    p.text(L + 150, y, val, 10.5);
    y -= 17;
  }
  y = Math.min(y, ptop - ph) - 10;

  // ── table: code · course title · unit · type, carryovers first ──
  const codeX = L + 8, titleX = L + 104, unitX = A4.w - L - 92, typeX = A4.w - L - 46;
  p.fill(L, y - 4, A4.w - 2 * L, 18, 0.2);
  p.text(codeX, y, "CODE", 8, true, [1, 1, 1]);
  p.text(titleX, y, "COURSE TITLE", 8, true, [1, 1, 1]);
  p.text(unitX, y, "UNIT", 8, true, [1, 1, 1]);
  p.text(typeX, y, "TYPE", 8, true, [1, 1, 1]);
  y -= 22;
  for (const e of [...reg.entries].sort((a, b) => orderRank(a) - orderRank(b) || (a.courseCode ?? "").localeCompare(b.courseCode ?? ""))) {
    const co = e.entryType === "CARRYOVER";
    p.text(codeX, y, clean(e.courseCode), 9, true, co ? [0.72, 0.11, 0.11] : [0, 0, 0]);
    p.text(titleX, y, cut(clean(e.title), 44), 9, false, [0.2, 0.2, 0.2]);
    p.text(unitX, y, String(e.units), 9);
    p.text(typeX, y, courseType(e), 8.5, true, [0.35, 0.35, 0.35]);
    if (co) p.text(codeX, y - 8, "carryover", 6.5, false, [0.72, 0.11, 0.11]);
    y -= co ? 19 : 16;
  }
  p.rule(L, y + 6, A4.w - L, y + 6);
  p.text(codeX, y - 8, "TOTAL CREDIT UNITS", 10.5, true);
  p.text(unitX, y - 8, String(reg.units), 12, true);
  y -= 48;

  // ── verification QR (bottom-left): opens the University's OWN record, so a forged or altered
  //    form is exposed. The QR carries only a link to the portal plus a check code — the courses,
  //    units and approval date shown on scan come from the database, not from this sheet. ──
  const matric = s.matricNo ?? s.admissionNo ?? "";
  const verifyUrl = originOf(request) + regVerifyPath(matric, session, semester);
  const code = regToken(matric, session, semester);
  const { size, dark } = qrMatrix(verifyUrl);
  const qDim = Math.min(size * 2.6, 96), cell = qDim / size, qx = L, qy = y;
  for (let rr = 0; rr < size; rr++) for (let cc = 0; cc < size; cc++) if (dark[rr * size + cc]) p.fill(qx + cc * cell, qy - (rr + 1) * cell, cell, cell, 0);
  p.text(qx, qy - qDim - 12, "SCAN TO VERIFY", 7.5, true, [0.4, 0.4, 0.4]);
  p.text(qx, qy - qDim - 23, verifyUrl.replace(/^https?:\/\//, ""), 6.5, false, [0.1, 0.25, 0.4]);
  p.text(qx, qy - qDim - 34, `Check code  ${code}`, 8, true, [0.3, 0.3, 0.3]);

  // ── signatures: Head of Department / Level Coordinator, and Dean of Faculty ──
  const sigW = 264, sigX2 = A4.w - L - sigW, dateX = sigX2 + sigW - 54;
  let sy = qy - 8;
  for (const role of ["Head of Department / Level Coordinator", "Dean of Faculty"]) {
    p.rule(sigX2, sy, dateX - 12, sy, 0.6, 0.55);
    p.rule(dateX, sy, sigX2 + sigW, sy, 0.6, 0.55);
    p.text(sigX2, sy - 11, role, 7.5, true, [0.25, 0.25, 0.25]);
    p.text(dateX, sy - 11, "Date", 7.5, false, [0.45, 0.45, 0.45]);
    sy -= 40;
  }

  p.text(L, 50, `Issued by the portal on ${day(new Date().toISOString())} · ${reg.id.slice(0, 8).toUpperCase()}`, 7.5, false, [0.4, 0.4, 0.4]);
  const bytes = pdf([p], `Course form ${s.matricNo ?? ""}`);
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="course-form-${session.replace("/", "-")}-${semester}.pdf"` } });
}
