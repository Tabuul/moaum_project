import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import type { Results, ResultRow, Semester } from "@/lib/student-portal";
import { semesterName } from "@/lib/student-portal";
import { A4, Page, pdf } from "@/lib/pdf-write";
import { brandHeader } from "@/lib/pdf-crest";

export const dynamic = "force-dynamic";

const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");
const clean = (s: string | null | undefined) => (s ?? "").replace(/[^\x20-\x7E]/g, " ").replace(/\s+/g, " ").trim();
const cut = (s: string, n: number) => (s.length > n ? s.slice(0, n - 1).trimEnd() + "..." : s);
const scoreOf = (c: ResultRow) => c.outcome === "GRADED" ? (c.total == null ? "-" : String(c.total)) : (c.outcome ? c.outcome.charAt(0) + c.outcome.slice(1).toLowerCase() : "-");

/** the student's result broadsheet as a PDF: each published semester's courses and its summary line */
export async function GET() {
  const [me, res] = await Promise.all([api<{ name: string; matricNo: string | null; admissionNo: string | null; programme: string; level: number }>("/api/v1/me"), api<Results>("/api/v1/me/results")]);
  if (!me.ok) return NextResponse.json(me.problem, { status: me.problem.status });
  if (!res.ok) return NextResponse.json(res.problem, { status: res.problem.status });
  const s = me.data, r = res.data;
  if (r.clearsResults === false) return NextResponse.json({ status: 409, title: "Withheld", detail: "Results are withheld until the fees are settled." }, { status: 409 });

  // group published rows by session+semester
  const groups: { session: string; semester: number; rows: ResultRow[] }[] = [];
  for (const row of r.rows.filter((x) => x.published)) {
    let g = groups.find((x) => x.session === row.session && x.semester === row.semester);
    if (!g) { g = { session: row.session, semester: row.semester, rows: [] }; groups.push(g); }
    g.rows.push(row);
  }
  const semOf = (ses: string, n: number): Semester | undefined => r.semesters.find((x) => x.session === ses && x.semester === n);

  const L = 56, R = A4.w - L;
  const cTitle = L + 66, cUnit = R - 250, cCa = R - 205, cEx = R - 162, cTot = R - 114, cGr = R - 60, cPt = R - 22;
  const pages: Page[] = [];
  let p = new Page();
  let y = brandHeader(p, L, "Result Broadsheet · Exams & Records");
  y -= 2;
  for (const [k, v] of [["Name", clean(s.name)], ["Matriculation number", s.matricNo ?? s.admissionNo ?? ""], ["Programme", clean(`${s.programme} · ${s.level} Level`)], ["Cumulative", `CGPA ${r.cgpa ?? "-"} · ${clean(r.standing ?? "-")}`]]) {
    p.text(L, y, k.toUpperCase(), 7, false, [0.42, 0.42, 0.42]);
    p.text(L + 130, y, v, 10);
    y -= 15;
  }
  y -= 8;

  const newPage = () => { pages.push(p); p = new Page(); y = A4.h - 56; };
  const need = (h: number) => { if (y - h < 56) newPage(); };

  for (const g of groups) {
    const sm = semOf(g.session, g.semester);
    need(30 + g.rows.length * 15 + 28);
    p.text(L, y, `${g.session} · ${semesterName(g.semester)} semester`, 11, true, [0.06, 0.15, 0.22]);
    y -= 16;
    p.fill(L, y - 5, R - L, 17, 0.16);
    p.text(L + 6, y, "COURSE", 7.5, true, [1, 1, 1]);
    p.text(cTitle, y, "TITLE", 7.5, true, [1, 1, 1]);
    p.text(cUnit, y, "UNIT", 7.5, true, [1, 1, 1]);
    p.text(cCa, y, "CA", 7.5, true, [1, 1, 1]);
    p.text(cEx, y, "EXAM", 7.5, true, [1, 1, 1]);
    p.text(cTot, y, "TOTAL", 7.5, true, [1, 1, 1]);
    p.text(cGr, y, "GRADE", 7.5, true, [1, 1, 1]);
    p.text(cPt, y, "PT", 7.5, true, [1, 1, 1]);
    y -= 20;
    for (const c of g.rows) {
      need(16);
      if (y === A4.h - 56) { /* fresh page: no repeat header, keep simple */ }
      p.text(L + 6, y, clean(c.course_code), 8.5, true);
      p.text(cTitle, y, cut(clean(c.title), 34), 8.5, false, [0.2, 0.2, 0.2]);
      p.text(cUnit, y, String(c.units), 8.5);
      p.text(cCa, y, c.outcome === "GRADED" ? (c.ca == null ? "-" : String(c.ca)) : "-", 8.5);
      p.text(cEx, y, c.outcome === "GRADED" ? (c.exam == null ? "-" : String(c.exam)) : "-", 8.5);
      p.text(cTot, y, scoreOf(c), 8.5, false, c.outcome !== "GRADED" ? [0.5, 0.3, 0.05] : [0, 0, 0]);
      p.text(cGr, y, c.grade ?? "-", 8.5, true, c.grade === "F" ? [0.72, 0.11, 0.11] : [0.05, 0.05, 0.05]);
      p.text(cPt, y, c.points == null ? "-" : String(c.points), 8.5);
      y -= 15;
    }
    // the summary line
    p.rule(L, y + 6, R, y + 6, 0.6, 0.6);
    if (sm) {
      const line = `CUR ${sm.cur}   CUE ${sm.cue}   WGP ${sm.wgp}   GPA ${sm.gpa ?? "-"}      TCR ${sm.tcr}   TCE ${sm.tce}   TWGP ${sm.twgp}   LCGPA ${sm.lcgpa ?? "-"}   CGPA ${sm.cgpa ?? "-"}`;
      p.text(L + 6, y - 7, line, 8.5, true, [0.06, 0.15, 0.22]);
    }
    y -= 30;
  }
  if (!groups.length) p.text(L, y, "No semester has a published result yet.", 10, false, [0.4, 0.4, 0.4]);

  p.rule(L, 44, R, 44, 0.5, 0.8);
  p.text(L, 34, `Issued by the portal on ${day(new Date().toISOString())} · ${s.matricNo ?? ""} · a view of the published record`, 7.5, false, [0.45, 0.45, 0.45]);
  pages.push(p);

  const bytes = pdf(pages, `Result broadsheet ${s.matricNo ?? ""}`);
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="broadsheet-${(s.matricNo ?? "").replace(/\//g, "-")}.pdf"` } });
}
