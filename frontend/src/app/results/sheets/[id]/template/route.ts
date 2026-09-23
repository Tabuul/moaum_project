import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import type { RollRow, SheetDetail } from "@/lib/results";

export const dynamic = "force-dynamic";

const cell = (v: string | number | null | undefined) => {
  const s = String(v ?? "");
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};

/** the score sheet as a CSV to fill offline — this course's live register, the same file the
 *  bulk upload reads back. Fill the CA and Exam columns and upload the computed sheet. */
export async function GET(_: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const [roll, detail] = await Promise.all([
    api<RollRow[]>(`/api/v1/results/sheets/${id}/roll`),
    api<SheetDetail>(`/api/v1/results/sheets/${id}`),
  ]);
  if (!roll.ok) return NextResponse.json(roll.problem, { status: roll.problem.status });
  const sheet = detail.ok ? detail.data.sheet : null;
  const course = sheet?.courseCode ?? "score";
  const counts = new Map<string, number>();
  for (const r of roll.data) counts.set(r.programmeCode, (counts.get(r.programmeCode) ?? 0) + 1);
  const ownCode = [...counts.entries()].sort((a, b) => b[1] - a[1])[0]?.[0];
  const programme = roll.data.find((r) => r.programmeCode === ownCode)?.programmeName ?? "";
  const heading: (string | number)[][] = sheet ? [
    ["Department", sheet.deptName], ["Programme", programme], ["Course", `${sheet.courseCode} — ${sheet.courseTitle}`],
    ["Lecturer", sheet.lecturer ?? "Not allocated"], ["Session", `${sheet.session} · semester ${sheet.semester}`], [],
  ] : [];
  const caMax = typeof sheet?.caMax === "number" ? sheet.caMax : 40;
  const header = ["S/N", "Matriculation number", "Name", "Programme", "Level", `CA (0-${caMax})`, `Exam (0-${100 - caMax})`,
    "Outcome (blank = GRADED, or ABSENT / WITHHELD / INCOMPLETE / MALPRACTICE / EXEMPTED)"];
  const lines = [...heading, header, ...roll.data.map((r, i) => [
    i + 1, r.number, `${r.surname}, ${r.otherNames}`, r.programmeName, r.level,
    r.ca ?? "", r.exam ?? "", r.outcome && r.outcome !== "GRADED" ? r.outcome : "",
  ])].map((row) => row.map(cell).join(",")).join("\r\n");

  return new NextResponse("﻿" + lines, {
    status: 200,
    headers: {
      "content-type": "text/csv; charset=utf-8",
      "content-disposition": `attachment; filename="${course.replace(/[^A-Za-z0-9]+/g, "-")}-score-sheet.csv"`,
    },
  });
}
