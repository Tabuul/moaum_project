import { NextRequest, NextResponse } from "next/server";
import { api, API_URL } from "@/lib/api";
import { sessionToken } from "@/lib/session";
import { A4, jpegSize, type Image } from "@/lib/pdf-write";
import { loadInstitution } from "@/lib/document/institution-server";
import { nameUpper } from "@/lib/document/institution";
import { finishPdf } from "@/lib/document/pdf";
import { semesterName } from "@/lib/student-portal";
import {
  CARD_L, EXAM_INSTRUCTIONS, EXAM_REGULATIONS, cardClean as clean, cardDay as day, cardFit, cardFooter, cardIdentity, cardPage, cardRules,
  cardTableEnd, cardTableHead, cardVerify, cardWrap,
} from "@/lib/exam-card-pdf";
import { permitSections, permitSummary, permitVerifyPath, scheduled, slotDate, slotTime, slotVenue, TO_BE_SCHEDULED, type PermitState } from "@/lib/gst-eps-permit";
import { shownCode } from "@/lib/course-code";

export const dynamic = "force-dynamic";

function originOf(req: Request): string {
  const h = req.headers;
  const host = h.get("x-forwarded-host") ?? h.get("host");
  const proto = h.get("x-forwarded-proto") ?? "https";
  try { return host ? `${proto}://${host}` : new URL(req.url).origin; } catch { return new URL(req.url).origin; }
}

/** the examination card's instructions and regulations, in the permit's own words */
const forPermit = (t: string) => t.replace(/(the|[Yy]our) examination card/g, "$1 permit").replace(/this card/g, "this permit");
const INSTRUCTIONS = ["Present this permit and your student I.D. card at every GST and EPS examination.", ...EXAM_INSTRUCTIONS.map(forPermit)];
const REGULATIONS = EXAM_REGULATIONS.map(forPermit);

/**
 * The GST & EPS examination permit card as a PDF (V492), drawn with the examination card's design (lib/exam-card-pdf): the
 * University's header, the photograph, the particulars, the courses, the instructions, the verification QR. The API issues it
 * (POST /api/v1/me/gst-eps-permit/issue): the student from the session token, the GST and EPS courses of the submitted
 * registration chosen by the database (V589: on the examination card's own terms, registered and paid, and the GST fee), the
 * issue counted (VIEW, DOWNLOAD, PRINT), refused with the reason when a rule fails. ICT Support viewing the student's portal
 * (V521) may change nothing, so for the view the permit the student last issued is read instead (GET …/document), with its
 * code, and nothing is made or counted. This draws what it is given and never adds a course; a date, time or venue the
 * timetable has not set reads TO BE SCHEDULED.
 */
export async function GET(request: NextRequest) {
  const inst = await loadInstitution();
  const q = request.nextUrl.searchParams;
  const semester = ["1", "2", "3"].includes(q.get("semester") ?? "") ? Number(q.get("semester")) : undefined;
  const act = q.get("act") === "download" ? "DOWNLOAD" : q.get("act") === "print" ? "PRINT" : "VIEW";
  let r = await api<PermitState>("/api/v1/me/gst-eps-permit/issue", { method: "POST", body: { semester, act } });
  if (!r.ok && r.problem.code === "SUPPORT_VIEW_READ_ONLY") {
    r = await api<PermitState>(`/api/v1/me/gst-eps-permit/document${semester ? `?semester=${semester}` : ""}`);
    if (r.ok && r.data.available && !r.data.permit) {
      return NextResponse.json({ status: 409, title: "The student has not opened the permit yet",
        detail: "A GST & EPS permit is made, with its number, at the student's first view. ICT Support reads the permit the student has opened; none is made from the student view." }, { status: 409 });
    }
  }
  if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status });
  const v = r.data;
  if (!v.available) {
    return NextResponse.json({ status: 409, title: "GST & EPS permit not available", detail: v.reason ?? "The GST & EPS permit cannot be issued yet." }, { status: 409 });
  }
  if (!v.permit || !v.checkCode || !v.courses.length) {
    return NextResponse.json({ status: 409, title: "No GST & EPS permit", detail: "You have not registered any GST or EPS course for the selected session and semester." }, { status: 409 });
  }
  const st = v.student;
  const matric = clean(st.matricNo ?? st.number ?? "");
  const name = clean(st.name) || matric;
  const sem = semesterName(v.semester);

  // the passport — the same photograph the examination card prints, from /me/passport
  let photo: Image | null = null;
  try {
    const tok = await sessionToken();
    const res = await fetch(`${API_URL}/api/v1/me/passport`, { headers: tok ? { Authorization: `Bearer ${tok}` } : {}, cache: "no-store" });
    if (res.ok) { const buf = new Uint8Array(await res.arrayBuffer()); const dim = jpegSize(buf); if (dim) photo = { width: dim.width, height: dim.height, data: buf }; }
  } catch { /* blank box */ }

  const L = CARD_L;
  const { p, y: top } = cardPage({
    matric, institution: clean(nameUpper(inst)), office: "Office of the Registrar", title: "GST & EPS EXAMINATION PERMIT CARD",
    band: `${v.session} ACADEMIC SESSION · ${sem.toUpperCase()} SEMESTER`,
  });
  const details: [string, string][] = [["Name", name], ["Matriculation number", matric]];
  if (st.jambNo) details.push(["JAMB registration number", clean(st.jambNo)]);
  details.push(
    ["Faculty", cardFit(clean(st.faculty) || "—", 240, 10, true)], ["Department", cardFit(clean(st.department) || "—", 240, 10, true)],
    ["Programme", cardFit(clean(st.programme) || "—", 240, 10, true)], ["Level", `${v.registration?.level ?? st.level ?? "—"} Level`],
    ["Session", v.session], ["Semester", sem], ["Permit number", v.permit.reference],
  );
  let y = cardIdentity(p, top, { photo, name, details });

  // ── the GST and EPS courses, each kind under its own heading (a kind the student did not register has none) ──
  const X = { sn: L + 6, code: L + 24, title: L + 80, unit: L + 202, type: L + 226, date: L + 256, time: L + 324, venue: L + 376, sign: L + 440 };
  const W = { title: X.unit - X.title - 6, date: X.time - X.date - 4, time: X.venue - X.time - 4, venue: X.sign - X.venue - 6 };
  cardTableHead(p, y, [[X.sn, "S/N"], [X.code, "CODE"], [X.title, "COURSE TITLE"], [X.unit, "UNIT"], [X.type, "TYPE"], [X.date, "DATE"], [X.time, "TIME"], [X.venue, "VENUE"], [X.sign, "SIGN"]]);
  y -= 19;
  let n = 0;
  const barred: string[] = [];
  for (const section of permitSections(v.courses)) {
    p.fill(L, y - 4, A4.w - 2 * L, 14, 0.92);
    p.text(L + 6, y, section.title, 8, true, [0.1, 0.25, 0.4]);
    y -= 17;
    for (const c of section.courses) {
      n += 1;
      const title = cardWrap(clean(c.title), W.title, 8.5);
      const venue = scheduled(c) ? cardWrap(clean(slotVenue(c)), W.venue, 8) : [];
      p.text(X.sn, y, String(n), 9);
      p.text(X.code, y, clean(shownCode(c.course_code)), 9, true);
      title.forEach((t, i) => p.text(X.title, y - i * 10, t, 8.5));
      p.text(X.unit + 2, y, String(c.units), 9);
      p.text(X.type, y, c.course_type, 8.5, true);
      if (scheduled(c)) {
        p.text(X.date, y, cardFit(slotDate(c), W.date, 8), 8);
        p.text(X.time, y, cardFit(slotTime(c, "-"), W.time, 8), 8);
        venue.forEach((t, i) => p.text(X.venue, y - i * 10, t, 8, t === TO_BE_SCHEDULED, t === TO_BE_SCHEDULED ? [0.45, 0.45, 0.45] : [0, 0, 0]));
      } else {
        p.text(X.date, y, TO_BE_SCHEDULED, 7.5, true, [0.45, 0.45, 0.45]);   // no date, time or venue is ever invented
      }
      if (c.bar) { p.text(X.sign, y, "BARRED", 7.5, true, [0.6, 0.1, 0.1]); barred.push(clean(shownCode(c.course_code))); }
      else p.rule(X.sign, y - 2, A4.w - L - 8, y - 2, 0.4, 0.75);   // a signature line per paper, as on the examination card
      y -= Math.max(16, 10 * Math.max(title.length, venue.length) + 6);
    }
  }
  y = cardTableEnd(p, y, permitSummary(v));
  if (barred.length) {
    p.text(L + 8, y + 8, `BARRED: attendance below the minimum for ${barred.join(", ")}`, 7.5, true, [0.6, 0.1, 0.1]);
    y -= 10;
  }

  // ── instructions and examination regulations, as on the examination card ──
  y = cardRules(p, y, INSTRUCTIONS, REGULATIONS);

  // ── the verify QR: the permit's reference and its signed check code ──
  const url = originOf(request) + permitVerifyPath(v.permit.reference, v.checkCode);
  cardVerify(p, y, url, v.checkCode, [`Permit No. ${v.permit.reference}`]);

  // above the document engine's own footer (the examination card's line sits at 40, on it)
  cardFooter(p, `${name} · ${matric} · issued ${day(new Date().toISOString())} · valid for the GST and EPS examinations of ${v.session} ${sem} semester only`, 58);

  const bytes = finishPdf([p], `GST & EPS permit ${matric}`, "FORM");
  return new NextResponse(Buffer.from(bytes), {
    status: 200,
    headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="gst-eps-permit-${v.session.replace("/", "-")}-${v.semester}.pdf"`, "cache-control": "no-store" },
  });
}
