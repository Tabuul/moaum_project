import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import { logServerExport } from "@/lib/export-log-server";
import { loadInstitution } from "@/lib/document/institution-server";
import { attendanceSheetsPdf } from "@/lib/exam-attendance-pdf";
import type { Sheet } from "@/lib/exam-attendance";
import type { Me } from "@/components/proto/Shell";

export const dynamic = "force-dynamic";

const REF = /^ATT\/[A-Z0-9-]{2,24}\/\d{4}\/\d{5}\/V\d{1,3}$/;

/**
 * /exams/attendance/sheets/pdf?ref=ATT/…/V1[&ref=…] — V652: one or more examination attendance sheets as one PDF for the hall.
 * Each sheet is read as it was issued (the students listed then, never the registrations of today), within the office's scope by
 * the API; each prints its own Page X of Y. At most 200 sheets a document.
 */
export async function GET(req: Request) {
  const refs = [...new Set(new URL(req.url).searchParams.getAll("ref").map((r) => r.trim().toUpperCase()))].filter((r) => REF.test(r));
  if (!refs.length) return NextResponse.json({ status: 400, title: "Name the attendance sheet", detail: "ref=ATT/<code>/<year>/<number>/V<version>" }, { status: 400 });
  if (refs.length > 200) return NextResponse.json({ status: 400, title: "At most 200 sheets a document" }, { status: 400 });
  const inst = await loadInstitution();
  const me = await api<Me>("/api/v1/iam/me");
  const sheets: Sheet[] = [];
  for (const ref of refs) {
    const r = await api<Sheet>(`/api/v1/exams/attendance/sheets/by-reference?reference=${encodeURIComponent(ref)}`);
    if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status || 500 });
    sheets.push(r.data);
  }
  const bytes = attendanceSheetsPdf(sheets, { inst, generatedBy: me.ok ? me.data.name ?? null : null });
  await logServerExport({
    report: sheets.length === 1 ? `Examination attendance sheet ${sheets[0].reference}` : `Examination attendance sheets (${sheets.length})`,
    format: "PDF", rows: sheets.reduce((n, s) => n + s.students, 0), meta: sheets.slice(0, 20).map((s) => ["Sheet", s.reference] as [string, string]),
  }, req);
  const name = sheets.length === 1 ? sheets[0].reference.replace(/\//g, "-").toLowerCase() : `attendance-sheets-${sheets.length}`;
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="${name}.pdf"` } });
}
