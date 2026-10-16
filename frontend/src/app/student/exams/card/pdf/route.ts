import { NextRequest, NextResponse } from "next/server";
import { api, API_URL } from "@/lib/api";
import { sessionToken } from "@/lib/session";
import type { Me, RegistrationView, Docket } from "@/lib/student-portal";
import { A4, jpegSize } from "@/lib/pdf-write";
import { examVerifyPath, studentCheckCode } from "@/lib/qr";
import { CARD_L, EXAM_INSTRUCTIONS, EXAM_REGULATIONS, cardClean as clean, cardCut as cut, cardDay as day, cardFooter, cardIdentity, cardPage, cardRules, cardTableEnd, cardTableHead, cardVerify } from "@/lib/exam-card-pdf";
import { semesterName } from "@/lib/student-portal";

import { loadInstitution } from "@/lib/document/institution-server";
import { finishPdf } from "@/lib/document/pdf";

export const dynamic = "force-dynamic";

function originOf(req: Request): string {
  const h = req.headers;
  const host = h.get("x-forwarded-host") ?? h.get("host");
  const proto = h.get("x-forwarded-proto") ?? "https";
  try { return host ? `${proto}://${host}` : new URL(req.url).origin; } catch { return new URL(req.url).origin; }
}

/** the examination card as a PDF: the courses to sit, the student's photograph, and a QR that
 *  opens the public verification page — so it cannot be cloned, and the face is checked at the hall */
export async function GET(request: NextRequest) {
  await loadInstitution();
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
  // V381: a paper the Centre's attendance policy bars is printed as barred, with no signature line
  const barred = new Set(dk.ok ? dk.data.examSessions.filter((x) => x.session === session && x.semester === semester).flatMap((x) => x.papers.filter((pp) => pp.bar).map((pp) => pp.course_code)) : []);
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

  // ── the card's design (lib/exam-card-pdf, shared with the GST & EPS permit): header, photograph, particulars ──
  const L = CARD_L;
  const { p, y: top } = cardPage({ matric, institution: "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI", office: "Office of the Registrar", title: "EXAMINATION CARD" });
  let y = cardIdentity(p, top, {
    photo, name: clean(s.name) || matric,
    details: [["Name", clean(s.name)], ["Matriculation number", matric], ["Programme", clean(s.programme)], ["Level", `${reg.level} Level`], ["Session", session], ["Semester", semesterName(semester)]],
  });

  const titleX = L + 92, unitX = A4.w - L - 150, signX = A4.w - L - 92;
  cardTableHead(p, y, [[L + 8, "COURSE CODE"], [titleX, "COURSE TITLE"], [unitX, "UNIT"], [signX, "SIGN / INVIGILATOR"]]);
  y -= 19;
  const titleMax = Math.floor((unitX - titleX - 6) / 4.6);   // chars that fit the title column at 8.5pt
  for (const e of reg.entries) {
    p.text(L + 8, y, clean(e.courseCode), 9, true);
    p.text(titleX, y, cut(clean(e.title), titleMax), 8.5);
    p.text(unitX + 2, y, String(e.units), 9);
    if (barred.has(e.courseCode)) p.text(signX, y, "BARRED: ATTENDANCE", 8, true, [0.6, 0.1, 0.1]);
    else p.rule(signX, y - 2, A4.w - L - 8, y - 2, 0.4, 0.75);   // a signature line per paper
    y -= 16;
  }
  y = cardTableEnd(p, y, `${reg.entries.length} paper(s) · ${reg.units} credit units`);

  // ── instructions and examination regulations, two compact columns ──
  y = cardRules(p, y, EXAM_INSTRUCTIONS, EXAM_REGULATIONS);

  // ── a small verify QR, bottom-left, with the check code (no explanatory paragraph) ──
  const check = await studentCheckCode("EXAM", session, semester);
  if (!check) return NextResponse.json({ status: 503, title: "The card's check code could not be made", detail: "Try again in a moment." }, { status: 503 });
  const url = originOf(request) + examVerifyPath(check.number, session, semester, check.code);
  cardVerify(p, y, url, check.code);

  cardFooter(p, `${clean(s.name)} · ${matric} · issued ${day(new Date().toISOString())} · valid for ${session} ${semesterName(semester)} semester only`);

  const bytes = finishPdf([p], `Exam card ${matric}`, "FORM");
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="exam-card-${session.replace("/", "-")}-${semester}.pdf"` } });
}
