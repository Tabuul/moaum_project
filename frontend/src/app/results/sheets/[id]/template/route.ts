import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import type { RollRow, SheetDetail } from "@/lib/results";
import { buildXlsx } from "@/lib/xlsx";
import { crestPng } from "@/lib/crest-server";
import { SCHOOL } from "@/lib/exportbrand";
import { semesterName } from "@/lib/student-portal";

export const dynamic = "force-dynamic";

const cell = (v: string | number | null | undefined) => {
  const s = String(v ?? "");
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};

/** GET /results/sheets/[id]/template?format=xlsx|csv — the score sheet to fill offline: this course's live
 *  register, every registered candidate already on it in alphabetical order with a serial number, under the
 *  University's letterhead and the course's particulars. Fill the CA and Exam columns and upload the file on
 *  the sheet; it is the same file the upload reads back. The workbook is the default (the marks are bounded
 *  as they are typed); the CSV is kept for a spreadsheet that cannot open one. */
export async function GET(req: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const format = new URL(req.url).searchParams.get("format") === "csv" ? "csv" : "xlsx";
  const [roll, detail] = await Promise.all([
    api<RollRow[]>(`/api/v1/results/sheets/${id}/roll`),
    api<SheetDetail>(`/api/v1/results/sheets/${id}`),
  ]);
  if (!roll.ok) return NextResponse.json(roll.problem, { status: roll.problem.status });
  if (!detail.ok) return NextResponse.json(detail.problem, { status: detail.problem.status });
  const sheet = detail.data.sheet;
  const counts = new Map<string, number>();
  for (const r of roll.data) counts.set(r.programmeCode, (counts.get(r.programmeCode) ?? 0) + 1);
  const ownCode = [...counts.entries()].sort((a, b) => b[1] - a[1])[0]?.[0];
  const programme = roll.data.find((r) => r.programmeCode === ownCode)?.programmeName ?? "";
  const byName = [...roll.data].sort((a, b) => a.surname.localeCompare(b.surname) || a.otherNames.localeCompare(b.otherNames) || a.number.localeCompare(b.number));
  const caMax = typeof sheet.caMax === "number" ? sheet.caMax : 40;
  const meta: [string, string][] = [
    ["Department", sheet.deptName], ["Programme", programme], ["Course", `${sheet.courseCode} — ${sheet.courseTitle} (${sheet.units} units)`],
    ["Lecturer", sheet.lecturer ?? "Not allocated"], ["Session", `${sheet.session} · ${semesterName(sheet.semester)} semester`],
    ["Candidates", String(byName.length)],
  ];
  const header = ["S/N", "Matriculation number", "Name", "Programme", "Level", `CA (0-${caMax})`, `Exam (0-${100 - caMax})`,
    "Outcome (blank = GRADED, or ABSENT / WITHHELD / INCOMPLETE / MALPRACTICE / EXEMPTED)"];
  const rows = byName.map((r, i) => [
    i + 1, r.number, `${r.surname}, ${r.otherNames}`, r.programmeName, r.level,
    r.ca ?? "", r.exam ?? "", r.outcome && r.outcome !== "GRADED" ? r.outcome : "",
  ]);
  const base = `${sheet.courseCode.replace(/[^A-Za-z0-9]+/g, "-")}-score-sheet-${sheet.session.replace("/", "-")}`;

  if (format === "csv") {
    const lines = [...meta.map(([k, v]) => [k, v]), [], header, ...rows].map((row) => row.map(cell).join(",")).join("\r\n");
    return new NextResponse("﻿" + lines, {
      status: 200,
      headers: { "content-type": "text/csv; charset=utf-8", "content-disposition": `attachment; filename="${base}.csv"` },
    });
  }
  const xlsx = buildXlsx(header, rows, "Score sheet", {
    school: SCHOOL,
    title: `${sheet.courseCode} — ${sheet.courseTitle} · score sheet`,
    date: `Generated ${new Date().toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" })} from the register · fill CA and Exam only; the total, grade and point are computed on upload`,
    logo: crestPng(),
    meta,
    validations: [
      { col: 5, min: 0, max: caMax, title: "Continuous assessment", message: `A whole number from 0 to ${caMax}.` },
      { col: 6, min: 0, max: 100 - caMax, title: "Examination", message: `A whole number from 0 to ${100 - caMax}.` },
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
