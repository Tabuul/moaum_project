import { NextRequest, NextResponse } from "next/server";
import { api, API_URL } from "@/lib/api";
import { sessionToken } from "@/lib/session";
import type { Me, RegistrationView, Docket } from "@/lib/student-portal";
import { A4, Page, pdf, jpegSize } from "@/lib/pdf-write";
import { brandHeader } from "@/lib/pdf-crest";
import { qrMatrix, examToken, examVerifyPath } from "@/lib/qr";
import { semesterName } from "@/lib/student-portal";

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

/** the examination card as a PDF: the courses to sit, the student's photograph, and a QR that
 *  opens the public verification page — so it cannot be cloned, and the face is checked at the hall */
export async function GET(request: NextRequest) {
  const q = request.nextUrl.searchParams;
  const me = await api<Me>("/api/v1/me");
  if (!me.ok) return NextResponse.json(me.problem, { status: me.problem.status });
  const s = me.data;
  const session = /^\d{4}\/\d{4}$/.test(q.get("session") ?? "") ? (q.get("session") as string) : s.session;
  const semester = q.get("semester") === "2" ? 2 : q.get("semester") === "3" ? 3 : 1;
  const matric = s.matricNo ?? s.admissionNo ?? "";

  const [v, dk] = await Promise.all([
    api<RegistrationView>(`/api/v1/me/registration?session=${encodeURIComponent(session)}&semester=${semester}`),
    api<Docket>("/api/v1/me/docket"),
  ]);
  const reg = v.ok ? v.data.registration : null;
  const cleared = dk.ok ? dk.data.clearsExamination : null;
  if (!reg || !(reg.status === "APPROVED" || reg.status === "LOCKED")) {
    return NextResponse.json({ status: 409, title: "No approved registration", detail: "An examination card is issued for an approved registration." }, { status: 409 });
  }
  if (cleared === false) {
    return NextResponse.json({ status: 409, title: "Not cleared for examinations", detail: "The card is issued when the Bursary clears you for the examination. Settle the fees the scheme requires." }, { status: 409 });
  }

  // the passport — the invigilator checks the face against it (anti-impersonation); from /me/passport,
  // which resolves the document store OR the JAMB/attachment store, so a migrated / JAMB-loaded photo also prints
  let photo: { width: number; height: number; data: Uint8Array } | null = null;
  try {
    const tok = await sessionToken();
    const res = await fetch(`${API_URL}/api/v1/me/passport`, { headers: tok ? { Authorization: `Bearer ${tok}` } : {}, cache: "no-store" });
    if (res.ok) { const buf = new Uint8Array(await res.arrayBuffer()); const dim = jpegSize(buf); if (dim) photo = { width: dim.width, height: dim.height, data: buf }; }
  } catch { /* blank box */ }

  const p = new Page();
  const L = 56;
  p.watermark(matric);   // the matric number, tiled faint at 45°, as a security watermark
  let y = brandHeader(p, L, "Examination Card");

  // photo top-right
  const pw = 84, ph = 100, px = A4.w - L - pw, ptop = y + 8;
  if (photo) p.jpeg(px, ptop - ph, pw, ph, photo);
  else { for (const [a, b, cc, d] of [[px, ptop, px + pw, ptop], [px, ptop - ph, px + pw, ptop - ph], [px, ptop, px, ptop - ph], [px + pw, ptop, px + pw, ptop - ph]]) p.rule(a, b, cc, d, 0.6, 0.7); p.text(px + 22, ptop - ph / 2, "PHOTO", 8, false, [0.6, 0.6, 0.6]); }
  p.text(px, ptop - ph - 10, "Photograph on file", 7, false, [0.5, 0.5, 0.5]);

  for (const [k, val] of [["Name", clean(s.name)], ["Matriculation number", matric], ["Programme", clean(s.programme)], ["Level", `${reg.level} Level`], ["Session", session], ["Semester", semesterName(semester)]]) {
    p.text(L, y, k.toUpperCase(), 7.5, false, [0.4, 0.4, 0.4]);
    p.text(L + 150, y, val, 10.5, true);
    y -= 18;
  }
  y = Math.min(y, ptop - ph - 22) - 6;

  p.fill(L, y - 4, A4.w - 2 * L, 18, 0.16);
  p.text(L + 8, y, "COURSES TO SIT", 8, true, [1, 1, 1]);
  p.text(A4.w - L - 150, y, "UNIT", 8, true, [1, 1, 1]);
  p.text(A4.w - L - 92, y, "SIGN / INVIGILATOR", 8, true, [1, 1, 1]);
  y -= 22;
  for (const e of reg.entries) {
    p.text(L + 8, y, clean(e.courseCode), 9.5, true);
    p.text(L + 8 + Math.min(clean(e.courseCode).length * 6 + 8, 78), y, cut(clean(e.title), 40), 9);
    p.text(A4.w - L - 148, y, String(e.units), 9.5);
    p.rule(A4.w - L - 92, y - 2, A4.w - L - 8, y - 2, 0.4, 0.75);   // a signature line per paper
    y -= 20;
  }
  p.rule(L, y + 8, A4.w - L, y + 8, 0.8, 0.55);
  p.text(L + 8, y - 4, `${reg.entries.length} paper(s) · ${reg.units} credit units`, 9.5, true);
  y -= 30;

  // ── verify QR (anti-clone) ──
  const url = originOf(request) + examVerifyPath(matric, session, semester);
  const code = examToken(matric, session, semester);
  const { size, dark } = qrMatrix(url);
  const cell = 2.7, qDim = size * cell, qx = A4.w - L - qDim, qy = y;
  p.fill(qx - 11, qy - qDim - 11, qDim + 22, qDim + 22, 1);
  for (let rr = 0; rr < size; rr++) for (let cc = 0; cc < size; cc++) if (dark[rr * size + cc]) p.fill(qx + cc * cell, qy - (rr + 1) * cell, cell, cell, 0);
  p.text(L, qy, "SCAN TO VERIFY", 8, true, [0.4, 0.4, 0.4]);
  let ty = p.paragraph(L, qy - 14, "This card is verified against the register, not by its appearance. The invigilator checks your face against the photograph and scans the code, which shows the University's own record of your name, photograph and courses. Admission without a valid card and a matching face is refused.", qx - L - 16, 9);
  ty -= 4;
  p.text(L, ty, url.replace(/^https?:\/\//, ""), 8, false, [0.1, 0.25, 0.4]); ty -= 13;
  p.text(L, ty, `Check code  ${code}`, 8.5, true);
  y = Math.min(ty, qy - qDim) - 20;

  const strip = ` REV. FR. MOSES ORSHIO ADASU UNIVERSITY · EXAMINATION CARD · ${matric} · ${session} · VERIFY ONLINE ·`;
  for (const my of [y + 4, 46]) p.text(L, my, strip.repeat(5), 3.2, false, [0.82, 0.82, 0.82]);
  p.text(L, 34, `Issued by the portal on ${day(new Date().toISOString())} · valid for ${session} ${semesterName(semester)} semester only`, 7.5, false, [0.45, 0.45, 0.45]);

  // ── page 2 · the instructions and the examination regulations ──
  const INSTRUCTIONS = [
    "Do not write anything on your examination card.",
    "Do not write anything on your question paper.",
    "Do not exchange your examination card.",
    "Do not impersonate or be impersonated.",
    "Fill in your particulars accurately on the front cover of the examination booklet.",
    "Ensure that your attendance slip is fully completed and submitted.",
    "Submit your answer script before you leave the examination hall.",
    "Ensure that you have your student I.D. card on your person.",
  ];
  const REGULATIONS = [
    "Only writing materials, or any other items specially allowed, shall be introduced into the examination hall.",
    "Candidates must be seated in the examination hall at least 10 minutes before the scheduled time.",
    "No candidate shall be allowed into the examination 30 minutes after its commencement, or leave the hall before the expiration of the first 45 minutes or during the last 15 minutes.",
    "Assisting, aiding or abetting cheating in any examination is prohibited.",
    "Silence must be maintained during the examination. To call the attention of the invigilator, only raise your hand.",
    "Smoking is prohibited in the examination hall.",
    "No examination answer scripts or sheets shall be taken out by any candidate.",
    "Introduction of cheat-notes, pieces of paper or any other material, relevant to the examination or not, is prohibited.",
    "Introduction of mobile phones or similar electronic devices into the examination hall, whether switched on or off, is prohibited.",
    "No candidate shall be allowed to leave the examination hall unaccompanied and return to it.",
    "Any infraction of the contents of this examination card shall constitute an examination irregularity and be subject to appropriate sanctions.",
    "Your examination card is a security document; ensure that you protect it.",
    "Exchange of the examination card is misconduct.",
    "Avoid misplacement of your examination card.",
  ];
  const p2 = new Page();
  p2.watermark(matric);
  let y2 = brandHeader(p2, L, "Examination Instructions & Regulations");
  const listWidth = A4.w - 2 * L - 20;
  const section = (title: string, items: string[]) => {
    p2.fill(L, y2 - 4, A4.w - 2 * L, 18, 0.16);
    p2.text(L + 8, y2, title, 8, true, [1, 1, 1]);
    y2 -= 24;
    items.forEach((t, i) => {
      p2.text(L, y2, `${i + 1}.`, 8.5, true);
      y2 = p2.paragraph(L + 20, y2, t, listWidth, 8.5, 1.3) - 3;
    });
    y2 -= 12;
  };
  section("INSTRUCTIONS TO THE CANDIDATE", INSTRUCTIONS);
  section("EXAMINATION REGULATIONS", REGULATIONS);
  p2.text(L, 40, `${clean(s.name)} · ${matric} · ${session} ${semesterName(semester)} semester`, 7.5, false, [0.45, 0.45, 0.45]);

  const bytes = pdf([p, p2], `Exam card ${matric}`);
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="exam-card-${session.replace("/", "-")}-${semester}.pdf"` } });
}
