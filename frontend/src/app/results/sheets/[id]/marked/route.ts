import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import type { RollRow, SheetDetail } from "@/lib/results";
import { buildXlsx } from "@/lib/xlsx";
import { crestPng } from "@/lib/crest-server";
import { MARKED_HEADERS, markedRows, markedSheetPdf, performance, performanceRows } from "@/lib/marked-sheet";
import { semesterName } from "@/lib/student-portal";

export const dynamic = "force-dynamic";

/** the API leaves a null field out of the JSON; the sheet's arithmetic tests against null */
const normalise = (r: RollRow): RollRow => ({ ...r, ca: r.ca ?? null, exam: r.exam ?? null, total: r.total ?? null, grade: r.grade ?? null, points: r.points ?? null, outcome: r.outcome ?? null, version: r.version ?? null });

/** GET /results/sheets/[id]/marked?format=pdf|xlsx — the marked score sheet as the lecturer may take
 *  it away: the roll with the computed total, grade and point, and a summary of performance at the end.
 *  Built from the register as it stands; for reference, the record stays the register. */
export async function GET(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const format = new URL(req.url).searchParams.get("format") === "pdf" ? "pdf" : "xlsx";
  const [detail, roll] = await Promise.all([
    api<SheetDetail>(`/api/v1/results/sheets/${id}`),
    api<RollRow[]>(`/api/v1/results/sheets/${id}/roll`),
  ]);
  if (!detail.ok) return NextResponse.json(detail.problem, { status: detail.problem.status });
  if (!roll.ok) return NextResponse.json(roll.problem, { status: roll.problem.status });
  const s = detail.data.sheet;
  const rows = roll.data.map(normalise);
  const counts = new Map<string, number>();
  for (const r of rows) counts.set(r.programmeCode, (counts.get(r.programmeCode) ?? 0) + 1);
  const ownCode = [...counts.entries()].sort((a, b) => b[1] - a[1])[0]?.[0];
  const programme = rows.find((r) => r.programmeCode === ownCode)?.programmeName ?? "";
  const semester = semesterName(s.semester);
  const base = `${s.courseCode.replace(/[^A-Za-z0-9]+/g, "-")}-marked-score-sheet-${s.session.replace("/", "-")}`;

  if (format === "pdf") {
    const bytes = markedSheetPdf({ sheet: s, programme, roll: rows }, semester.toLowerCase());
    return new NextResponse(new Uint8Array(bytes), {
      status: 200,
      headers: { "content-type": "application/pdf", "content-disposition": `attachment; filename="${base}.pdf"` },
    });
  }
  const caMax = typeof s.caMax === "number" ? s.caMax : 40;
  const perf = performance(rows);
  const xlsx = buildXlsx(MARKED_HEADERS, [...markedRows(rows), ...performanceRows(perf)], "Marked sheet", {
    school: "REV. FR. MOSES ORSHIO ADASU UNIVERSITY, MAKURDI",
    title: `${s.courseCode} — ${s.courseTitle} · marked score sheet`,
    date: `Generated ${new Date().toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" })} from the register · for reference; the record is the register`,
    logo: crestPng(),
    meta: [
      ["Department", s.deptName],
      ["Programme", programme],
      ["Course", `${s.courseCode} — ${s.courseTitle} · ${s.units} unit${s.units === 1 ? "" : "s"}`],
      ["Lecturer", s.lecturer ?? "Not allocated"],
      ["Session", `${s.session} · ${semester} semester · CA out of ${caMax}, examination out of ${100 - caMax}`],
      ["Standing", `${s.stage.toLowerCase().replace(/_/g, " ")} · ${perf.graded} of ${perf.candidates} graded · ${perf.passed} passed, ${perf.failed} failed`],
    ],
  });
  return new NextResponse(await xlsx.arrayBuffer(), {
    status: 200,
    headers: {
      "content-type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      "content-disposition": `attachment; filename="${base}.xlsx"`,
    },
  });
}
