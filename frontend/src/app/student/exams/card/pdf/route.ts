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

  const INSTRUCTIONS = [
    "Do not write anything on your examination card.",
    "Do not write anything on your question paper.",
    "Do not exchange your examination card.",
    "Do not impersonate or be impersonated.",
    "Fill in your particulars accurately on the examination booklet.",
    "Ensure your attendance slip is fully completed and submitted.",
    "Submit your answer script before you leave the hall.",
    "Have your student I.D. card on your person.",
  ];
  const REGULATIONS = [
    "Only writing materials, or items specially allowed, may be introduced into the hall.",
    "Candidates must be seated at least 10 minutes before the scheduled time.",
    "No candidate is admitted 30 minutes after commencement, or may leave before the first 45 minutes or during the last 15.",
    "Assisting, aiding or abetting cheating is prohibited.",
    "Silence must be maintained; raise your hand to call the invigilator.",
    "Smoking is prohibited in the examination hall.",
    "No answer script or sheet may be taken out by any candidate.",
    "Cheat-notes or any other material, relevant or not, are prohibited.",
    "Mobile phones or similar devices, on or off, are prohibited in the hall.",
    "No candidate may leave the hall unaccompanied and return to it.",
    "Any infraction of this card constitutes an examination irregularity and is subject to sanctions.",
    "Your examination card is a security document; protect it.",
    "Exchange of the examination card is misconduct.",
    "Avoid misplacement of your examination card.",
  ];

  const p = new Page();
  const L = 56;
  p.watermark(matric);   // the matric number, tiled faint at 45°, as a security watermark
  let y = brandHeader(p, L, "Examination Card");

  // photo top-right
  const pw = 74, ph = 88, px = A4.w - L - pw, ptop = y + 8;
  if (photo) p.jpeg(px, ptop - ph, pw, ph, photo);
  else { for (const [a, b, cc, d] of [[px, ptop, px + pw, ptop], [px, ptop - ph, px + pw, ptop - ph], [px, ptop, px, ptop - ph], [px + pw, ptop, px + pw, ptop - ph]]) p.rule(a, b, cc, d, 0.6, 0.7); p.text(px + 20, ptop - ph / 2, "PHOTO", 8, false, [0.6, 0.6, 0.6]); }
  p.text(px, ptop - ph - 9, "Photograph on file", 6.5, false, [0.5, 0.5, 0.5]);

  for (const [k, val] of [["Name", clean(s.name)], ["Matriculation number", matric], ["Programme", clean(s.programme)], ["Level", `${reg.level} Level`], ["Session", session], ["Semester", semesterName(semester)]]) {
    p.text(L, y, k.toUpperCase(), 7, false, [0.4, 0.4, 0.4]);
    p.text(L + 140, y, val, 10, true);
    y -= 15;
  }
  y = Math.min(y, ptop - ph - 18) - 4;

  p.fill(L, y - 4, A4.w - 2 * L, 16, 0.16);
  p.text(L + 8, y, "COURSES TO SIT", 8, true, [1, 1, 1]);
  p.text(A4.w - L - 150, y, "UNIT", 8, true, [1, 1, 1]);
  p.text(A4.w - L - 92, y, "SIGN / INVIGILATOR", 8, true, [1, 1, 1]);
  y -= 19;
  for (const e of reg.entries) {
    p.text(L + 8, y, clean(e.courseCode), 9, true);
    p.text(L + 8 + Math.min(clean(e.courseCode).length * 6 + 8, 74), y, cut(clean(e.title), 42), 8.5);
    p.text(A4.w - L - 148, y, String(e.units), 9);
    p.rule(A4.w - L - 92, y - 2, A4.w - L - 8, y - 2, 0.4, 0.75);   // a signature line per paper
    y -= 16;
  }
  p.rule(L, y + 7, A4.w - L, y + 7, 0.8, 0.55);
  p.text(L + 8, y - 4, `${reg.entries.length} paper(s) · ${reg.units} credit units`, 9, true);
  y -= 22;

  // ── instructions and examination regulations, two compact columns ──
  const colW = (A4.w - 2 * L - 16) / 2;
  const colX2 = L + colW + 16;
  const column = (x: number, top: number, title: string, items: string[]) => {
    p.fill(x, top - 4, colW, 15, 0.16);
    p.text(x + 6, top, title, 7.5, true, [1, 1, 1]);
    let yy = top - 18;
    items.forEach((t, i) => {
      p.text(x, yy, `${i + 1}.`, 7, true);
      yy = p.paragraph(x + 14, yy, t, colW - 14, 7, 1.25) - 2;
    });
    return yy;
  };
  const colTop = y;
  const endL = column(L, colTop, "INSTRUCTIONS TO THE CANDIDATE", INSTRUCTIONS);
  const endR = column(colX2, colTop, "EXAMINATION REGULATIONS", REGULATIONS);
  y = Math.min(endL, endR) - 14;

  // ── a small verify QR, bottom-left, with the check code (no explanatory paragraph) ──
  const url = originOf(request) + examVerifyPath(matric, session, semester);
  const code = examToken(matric, session, semester);
  const { size, dark } = qrMatrix(url);
  const cell = 1.7, qDim = size * cell, qy = Math.max(y, 96);
  for (let rr = 0; rr < size; rr++) for (let cc = 0; cc < size; cc++) if (dark[rr * size + cc]) p.fill(L + cc * cell, qy - (rr + 1) * cell, cell, cell, 0);
  p.text(L + qDim + 12, qy - 10, "SCAN TO VERIFY", 8, true, [0.4, 0.4, 0.4]);
  p.text(L + qDim + 12, qy - 24, `Check code  ${code}`, 8.5, true);
  p.text(L + qDim + 12, qy - 37, "Verified against the register — the invigilator checks the face against the photograph.", 7, false, [0.45, 0.45, 0.45]);

  p.text(L, 40, `${clean(s.name)} · ${matric} · issued ${day(new Date().toISOString())} · valid for ${session} ${semesterName(semester)} semester only`, 7, false, [0.45, 0.45, 0.45]);

  const bytes = pdf([p], `Exam card ${matric}`);
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="exam-card-${session.replace("/", "-")}-${semester}.pdf"` } });
}
