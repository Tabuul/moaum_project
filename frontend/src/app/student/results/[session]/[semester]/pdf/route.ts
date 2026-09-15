import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import type { Results } from "@/lib/student-portal";
import { semesterName } from "@/lib/student-portal";
import { A4, Page, pdf } from "@/lib/pdf-write";
import { brandHeader } from "@/lib/pdf-crest";

export const dynamic = "force-dynamic";

const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");
/* the PDF font is WinAnsi Helvetica; a non-breaking space or a stray accent in a migrated title renders as
   "Â" or a box. Fold the text down to plain ASCII so the statement always reads cleanly. */
const clean = (s: string | null | undefined) => (s ?? "").replace(/[\u00A0\u2007\u202F\u200B]/g, " ").replace(/[^\x20-\x7E]/g, "").replace(/\s+/g, " ").trim();
const cut = (s: string, n: number) => (s.length > n ? s.slice(0, n - 1).trimEnd() + "…".replace("…", "...") : s);
const scoreOf = (c: { outcome: string | null; total: number | null | undefined }) =>
  c.outcome === "GRADED" ? (c.total == null ? "—" : String(c.total)) : (c.outcome ? c.outcome.charAt(0) + c.outcome.slice(1).toLowerCase() : "—");

/** the statement of results as a PDF: one semester, the published grades and nothing else */
export async function GET(_: Request, { params }: { params: Promise<{ session: string; semester: string }> }) {
  const p0 = await params;
  const session = decodeURIComponent(p0.session);
  const semester = Number(p0.semester);
  const r = await api<Results>("/api/v1/me/results");
  if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status });
  const x = r.data;
  if (x.clearsResults === false) return NextResponse.json({ status: 409, title: "Withheld", detail: "Results are withheld until the fees are settled." }, { status: 409 });
  const rows = x.rows.filter((c) => c.session === session && c.semester === semester && c.published);
  if (!rows.length) return NextResponse.json({ status: 409, title: "Nothing published", detail: "No result is published for this semester." }, { status: 409 });
  const sem = x.semesters.find((s) => s.session === session && s.semester === semester);

  const p = new Page();
  const L = 56;
  const R = A4.w - L;
  const W = R - L;
  // column anchors (left-aligned text at each x)
  const cUnit = R - 210, cScore = R - 155, cGrade = R - 95, cPoint = R - 40;

  let y = brandHeader(p, L, "Semester Results · Exams & Records");
  y -= 4;

  // ── candidate block: two columns ──────────────────────────────────────────
  const meta: [string, string][][] = [
    [["Name", clean(x.name)], ["Programme", clean(`${x.programme} · ${x.level} Level`)]],
    [["Matriculation number", x.matricNo ?? "—"], ["Session", `${session} · ${semesterName(semester)} semester`]],
  ];
  for (const line of meta) {
    let cx = L;
    for (const [k, v] of line) {
      p.text(cx, y, k.toUpperCase(), 7, false, [0.42, 0.42, 0.42]);
      p.text(cx, y - 12, v, 10.5, true);
      cx += W / 2;
    }
    y -= 34;
  }
  y -= 6;

  // ── table header ──────────────────────────────────────────────────────────
  p.fill(L, y - 5, W, 19, 0.16);
  p.text(L + 8, y, "COURSE", 8, true, [1, 1, 1]);
  p.text(cUnit, y, "UNIT", 8, true, [1, 1, 1]);
  p.text(cScore, y, "SCORE", 8, true, [1, 1, 1]);
  p.text(cGrade, y, "GRADE", 8, true, [1, 1, 1]);
  p.text(cPoint, y, "POINTS", 8, true, [1, 1, 1]);
  y -= 23;

  // ── rows, with alternating shading ────────────────────────────────────────
  let gp = 0, registered = 0, passed = 0;
  rows.forEach((c, i) => {
    if (i % 2 === 1) p.fill(L, y - 5, W, 16, 0.965);
    // keep the course code bold, the title lighter, and truncate so it never reaches the UNIT column
    p.text(L + 8, y, clean(c.course_code), 8.5, true);
    p.text(L + 8 + Math.min(clean(c.course_code).length * 5.4 + 8, 78), y, cut(clean(c.title), 44), 8.5, false, [0.2, 0.2, 0.2]);
    p.text(cUnit, y, String(c.units), 8.5);
    p.text(cScore, y, scoreOf(c), 8.5, false, c.outcome !== "GRADED" ? [0.5, 0.3, 0.05] : [0, 0, 0]);
    p.text(cGrade, y, c.grade ?? "—", 8.5, true, c.grade === "F" ? [0.72, 0.11, 0.11] : [0.05, 0.05, 0.05]);
    p.text(cPoint, y, c.points == null ? "—" : String(c.points), 8.5);
    registered += c.units;
    if (c.outcome === "GRADED") { gp += c.units * Number(c.points ?? 0); if (Number(c.points ?? 0) > 0) passed += c.units; }
    y -= 17;
  });
  p.rule(L, y + 7, R, y + 7, 0.8, 0.55);
  p.text(L + 8, y - 6, `Units registered ${registered}`, 9.5, true);
  p.text(cUnit - 40, y - 6, `Passed ${passed}`, 9.5, true);
  p.text(cScore + 6, y - 6, `Grade points ${gp.toFixed(1)}`, 9.5, true);
  y -= 30;

  // ── summary box: GPA · CGPA · standing ────────────────────────────────────
  const bh = 46;
  p.fill(L, y - bh + 12, W, bh, 0.945);
  p.rule(L, y - bh + 12, L, y + 12, 3, 0.16);   // a left accent bar
  const cellW = W / 3;
  const cells: [string, string][] = [
    ["Semester GPA", sem?.gpa != null ? String(sem.gpa) : "—"],
    ["Cumulative GPA", sem?.cgpa != null ? String(sem.cgpa) : "—"],
    ["Class of standing", clean(x.standing ?? "—")],
  ];
  cells.forEach(([k, v], i) => {
    const cx = L + 16 + i * cellW;
    p.text(cx, y - 4, k.toUpperCase(), 7.5, false, [0.42, 0.42, 0.42]);
    p.text(cx, y - 24, v, i === 2 ? 12 : 18, true, [0.06, 0.15, 0.22]);
  });
  y -= bh + 12;

  // ── the academic summary line: this semester, then cumulative ──────────────
  if (sem) {
    p.text(L, y, "SUMMARY", 7.5, true, [0.42, 0.42, 0.42]);
    const dash = (v: number | null | undefined) => (v == null ? "-" : String(v));
    const line = `CUR ${sem.cur}   CUE ${sem.cue}   WGP ${sem.wgp}   GPA ${dash(sem.gpa)}       TCR ${sem.tcr}   TCE ${sem.tce}   TWGP ${sem.twgp}   LCGPA ${dash(sem.lcgpa)}   CGPA ${dash(sem.cgpa)}`;
    p.text(L + 58, y, line, 8.5, true, [0.1, 0.1, 0.1]);
    y -= 22;
  }

  // ── grading key ───────────────────────────────────────────────────────────
  p.text(L, y, "GRADING", 7.5, true, [0.42, 0.42, 0.42]);
  p.text(L + 60, y, "A 70-100 (5)   B 60-69 (4)   C 50-59 (3)   D 45-49 (2)   E 40-44 (1)   F 0-39 (0)", 8.5, false, [0.25, 0.25, 0.25]);
  y -= 24;

  y = p.paragraph(L, y, `Published ${day(rows[0].published_at)} after Senate approval${rows[0].senate_minute ? ` under minute ${clean(rows[0].senate_minute)}` : ""}. A grade that is not on a published sheet is not on this statement. The register is the thing; this statement is a view of it and is verified against it, not by its appearance.`, W, 8.5);

  p.rule(L, 44, R, 44, 0.5, 0.8);
  p.text(L, 34, `Issued by the portal on ${day(new Date().toISOString())}`, 7.5, false, [0.45, 0.45, 0.45]);
  p.text(cPoint - 80, 34, x.matricNo ?? "", 7.5, false, [0.45, 0.45, 0.45]);

  const bytes = pdf([p], `Semester Results ${session} ${semester}`);
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="semester-results-${session.replace("/", "-")}-${semester}.pdf"` } });
}
