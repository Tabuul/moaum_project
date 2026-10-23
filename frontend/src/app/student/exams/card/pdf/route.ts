import { NextRequest, NextResponse } from "next/server";
import { api, API_URL } from "@/lib/api";
import { sessionToken } from "@/lib/session";
import type { Me, Docket } from "@/lib/student-portal";
import type { ExamCardState } from "@/lib/exam-card";
import { A4, jpegSize } from "@/lib/pdf-write";
import { examVerifyPath, studentCheckCodeResult } from "@/lib/qr";
import { CARD_L, EXAM_INSTRUCTIONS, EXAM_REGULATIONS, cardClean as clean, cardCut as cut, cardDay as day, cardFooter, cardIdentity, cardPage, cardRules, cardTableEnd, cardTableHead, cardVerify } from "@/lib/exam-card-pdf";
import { semesterName } from "@/lib/student-portal";
import { inUniversityOrder } from "@/lib/course-order";

import { loadInstitution } from "@/lib/document/institution-server";
import { finishPdf } from "@/lib/document/pdf";
import { shownCode } from "@/lib/course-code";

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

  // V501/V567: the card's own rule (registration.exam_card_state): a registration submitted carrying a course and the school fees paid —
  // and every course on the registration, departmental, GST and EPS alike
  const [v, dk] = await Promise.all([
    api<ExamCardState>(`/api/v1/me/exam-card?session=${encodeURIComponent(session)}&semester=${semester}`),
    api<Docket>("/api/v1/me/docket"),
  ]);
  if (!v.ok) return NextResponse.json(v.problem, { status: v.problem.status });
  const card = v.data;
  if (!card.available) {
    return NextResponse.json({ status: 409, title: "Examination card not available", detail: card.reason ?? "The examination card cannot be issued yet." }, { status: 409 });
  }
  // V381: a paper the Centre's attendance policy bars is printed as barred, with no signature line
  const barred = new Set(dk.ok ? dk.data.examSessions.filter((x) => x.session === session && x.semester === semester).flatMap((x) => x.papers.filter((pp) => pp.bar).map((pp) => pp.course_code)) : []);

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
    details: [["Name", clean(s.name)], ["Matriculation number", matric], ["Programme", clean(s.programme)], ["Level", `${card.registration?.level ?? s.level} Level`], ["Session", session], ["Semester", semesterName(semester)]],
  });

  // V504: numbered, in the University's order — carry-over, GST, core, elective (lib/course-order, as registration.entry_rank)
  const codeX = L + 30, titleX = L + 114, unitX = A4.w - L - 150, signX = A4.w - L - 92;
  cardTableHead(p, y, [[L + 8, "S/N"], [codeX, "COURSE CODE"], [titleX, "COURSE TITLE"], [unitX, "UNIT"], [signX, "SIGN / INVIGILATOR"]]);
  y -= 19;
  const titleMax = Math.floor((unitX - titleX - 6) / 4.6);   // chars that fit the title column at 8.5pt
  let sn = 0;
  for (const e of inUniversityOrder(card.courses)) {
    p.text(L + 8, y, String(++sn), 9);
    p.text(codeX, y, clean(shownCode(e.course_code)), 9, true);
    p.text(titleX, y, cut(clean(e.title), titleMax), 8.5);
    p.text(unitX + 2, y, String(e.units), 9);
    if (barred.has(e.course_code)) p.text(signX, y, "BARRED: ATTENDANCE", 8, true, [0.6, 0.1, 0.1]);
    else p.rule(signX, y - 2, A4.w - L - 8, y - 2, 0.4, 0.75);   // a signature line per paper
    y -= 16;
  }
  y = cardTableEnd(p, y, `${card.count} paper(s) · ${card.units} credit units`);

  // ── instructions and examination regulations, two compact columns ──
  y = cardRules(p, y, EXAM_INSTRUCTIONS, EXAM_REGULATIONS);

  // ── a small verify QR, bottom-left, with the check code (no explanatory paragraph) ──
  // V589: the API's own refusal is shown as it is (the card's rule, or a read-only support view), never a bare "try again"
  const check = await studentCheckCodeResult("EXAM", session, semester);
  if (!check.ok) return NextResponse.json(check.problem, { status: check.problem.status || 503 });
  const url = originOf(request) + examVerifyPath(check.number, session, semester, check.code);
  const beside = cardVerify(p, y, url, check.code);

  cardFooter(p, `${clean(s.name)} · ${matric} · issued ${day(new Date().toISOString())} · valid for ${session} ${semesterName(semester)} semester only`, beside.y, beside.x);   // beside the QR, above the document footer

  const bytes = finishPdf([p], `Exam card ${matric}`, "FORM");
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="exam-card-${session.replace("/", "-")}-${semester}.pdf"` } });
}
