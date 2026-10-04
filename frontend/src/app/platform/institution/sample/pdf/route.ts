import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import type { Me } from "@/components/proto/Shell";
import { loadInstitution } from "@/lib/document/institution-server";
import { PdfDocument } from "@/lib/document/pdf";

export const dynamic = "force-dynamic";

/** a sample standard report on the central PDF document (V320): the official header, a filter block, a long table across
 *  pages with the header repeated and the serial numbers running on, signature lines, and the footer with page numbers —
 *  for an administrator to see what every report will look like under the profile as saved */
export async function GET() {
  const me = await api<Me>("/api/v1/iam/me");
  if (!me.ok) return NextResponse.json(me.problem, { status: me.problem.status });
  const inst = await loadInstitution();
  const doc = new PdfDocument("STANDARD_REPORT", {
    title: "Sample report",
    subtitle: "2025/2026 Academic Session — First Semester",
    meta: [["Faculty", "Science"], ["Department", "Mathematics and Computer Science"], ["Programme", "B.Sc. Computer Science"], ["Level", "All"], ["Session", "2025/2026"], ["Semester", "First"]],
    generatedBy: me.data.name ?? null,
    reference: `${inst.shortName}/SAMPLE/${new Date().getFullYear()}`,
    watermark: "SAMPLE",
  }, inst);
  doc.paragraph("A sample: the rows below are invented. Every real report prints under this header with the filters it was made with, the table header repeated on each page, the serial numbers running on, and the footer with the page count.");
  doc.keyValues([["Prepared for", "The Registrar"], ["Prepared by", me.data.name ?? "—"], ["Rows", "120 invented"], ["Status", "All"]]);
  const names = ["Adaeze Okafor", "Terhemba Iorfa", "Grace Abah", "Musa Danladi", "Ngozi Eze", "Aondona Ukpe"];
  doc.table(["Matriculation number", "Name", "Level", "Score", "Grade"],
    Array.from({ length: 120 }, (_, i) => [`${inst.shortName}/SC/CMP/25/${String(70001 + i).padStart(5, "0")}`, names[i % names.length], 100 + (i % 4) * 100, 40 + ((i * 13) % 60), ["A", "B", "C", "D", "E"][i % 5]]));
  doc.signatures([{ designation: "Head of Department" }, { designation: "Dean of Faculty" }]);
  const bytes = doc.finish();
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="sample-report.pdf"` } });
}
