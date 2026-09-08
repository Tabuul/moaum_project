import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import type { Results } from "@/lib/student-portal";
import { semesterName } from "@/lib/student-portal";
import { A4, Page, pdf } from "@/lib/pdf-write";

export const dynamic = "force-dynamic";

const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "—");

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
  const L = 64;
  let y = A4.h - 70;
  p.text(L, y, "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI", 12, true);
  y -= 15;
  p.text(L, y, "Statement of Results · Exams & Records", 9.5, false, [0.35, 0.35, 0.35]);
  y -= 10;
  p.rule(L, y, A4.w - L, y, 1, 0.2);
  y -= 26;
  for (const [k, v] of [["Name", x.name], ["Matriculation number", x.matricNo], ["Programme", `${x.programme} · ${x.level} Level`], ["Session", `${session} · ${semesterName(semester)} semester`]]) {
    p.text(L, y, k.toUpperCase(), 7.5, false, [0.4, 0.4, 0.4]);
    p.text(L + 150, y, v, 10.5);
    y -= 17;
  }
  y -= 10;
  p.fill(L, y - 4, A4.w - 2 * L, 18, 0.2);
  p.text(L + 8, y, "COURSE", 8, true, [1, 1, 1]);
  p.text(A4.w - L - 200, y, "UNIT", 8, true, [1, 1, 1]);
  p.text(A4.w - L - 150, y, "SCORE", 8, true, [1, 1, 1]);
  p.text(A4.w - L - 95, y, "GRADE", 8, true, [1, 1, 1]);
  p.text(A4.w - L - 45, y, "POINTS", 8, true, [1, 1, 1]);
  y -= 22;
  let gp = 0;
  let registered = 0;
  let passed = 0;
  for (const c of rows) {
    p.text(L + 8, y, `${c.course_code}  ${c.title}`, 10);
    p.text(A4.w - L - 195, y, String(c.units), 10);
    p.text(A4.w - L - 145, y, c.outcome === "GRADED" ? String(c.total) : String(c.outcome), 10);
    p.text(A4.w - L - 88, y, c.grade ?? "—", 10, true, c.grade === "F" ? [0.7, 0.1, 0.1] : [0, 0, 0]);
    p.text(A4.w - L - 40, y, c.points == null ? "—" : String(c.points), 10);
    registered += c.units;
    if (c.outcome === "GRADED") { gp += c.units * Number(c.points ?? 0); if (Number(c.points ?? 0) > 0) passed += c.units; }
    y -= 17;
  }
  p.rule(L, y + 6, A4.w - L, y + 6);
  p.text(L + 8, y - 8, `Units registered ${registered} · passed ${passed} · grade points ${gp.toFixed(1)}`, 10, true);
  y -= 30;
  p.text(L, y, `Semester GPA ${sem?.gpa ?? "—"} · Cumulative GPA ${sem?.cgpa ?? "—"}${x.standing ? ` · ${x.standing}` : ""}`, 11, true);
  y -= 26;
  y = p.paragraph(L, y, `Published ${day(rows[0].published_at)} after Senate approval${rows[0].senate_minute ? ` under minute ${rows[0].senate_minute}` : ""}. A grade that is not on a published sheet is not on this statement. The register is the thing; this statement is a view of it and is verified against it, not by its appearance.`, A4.w - 2 * L, 9);
  p.text(L, 50, `Issued by the portal on ${day(new Date().toISOString())} · ${x.matricNo}`, 7.5, false, [0.4, 0.4, 0.4]);
  const bytes = pdf([p], `Results ${session} ${semester}`);
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="results-${session.replace("/", "-")}-${semester}.pdf"` } });
}
