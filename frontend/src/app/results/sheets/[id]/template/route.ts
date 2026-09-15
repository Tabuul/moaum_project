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
  const course = detail.ok ? detail.data.sheet.courseCode : "score";
  const header = ["Matriculation number", "Name", "Programme", "Level", "CA (0-40)", "Exam (0-60)",
    "Outcome (blank = GRADED, or ABSENT / WITHHELD / INCOMPLETE / MALPRACTICE / EXEMPTED)"];
  const lines = [header, ...roll.data.map((r) => [
    r.number, `${r.surname}, ${r.otherNames}`, r.programmeName, r.level,
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
