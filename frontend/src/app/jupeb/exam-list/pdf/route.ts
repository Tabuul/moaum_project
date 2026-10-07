import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import { loadInstitution } from "@/lib/document/institution-server";
import { PdfDocument } from "@/lib/document/pdf";
import { formatDocDate } from "@/lib/document/institution";
import { streamLabel } from "@/lib/jupeb";

export const dynamic = "force-dynamic";

interface Row {
  application_no: string; surname: string; first_name: string; middle_name: string | null; sex: string | null; date_of_birth: string | null;
  stream: string | null; combination_code: string | null; class_name: string | null; exam_no: string | null; subject_codes: string[];
}
interface List { session: string; which: string; notRegistered: number; rows: Row[] }

/**
 * /jupeb/exam-list/pdf — the list of JUPEB candidates sent to the Board for examination numbers, on the University's
 * letterhead (landscape): every active student of the session whose three subjects are registered, without a number or
 * everyone. The JUPEB Office's own endpoint decides who may read it.
 */
export async function GET(req: Request) {
  const url = new URL(req.url);
  const session = url.searchParams.get("session") ?? "";
  const which = url.searchParams.get("which") === "all" ? "all" : "pending";
  const inst = await loadInstitution();
  const res = await api<List>(`/api/v1/jupeb/office/exam-number-list?session=${encodeURIComponent(session)}&which=${which}`);
  if (!res.ok) return NextResponse.json(res.problem, { status: res.problem.status });
  const d = res.data;
  const pdf = new PdfDocument("BROADSHEET", {
    title: "JUPEB candidates for examination numbers",
    subtitle: `${d.session} academic session - ${which === "all" ? "every student with registered subjects" : "students without a JUPEB examination number"}`,
    unit: "JUPEB Office", meta: [["Session", d.session], ["Candidates", String(d.rows.length)]],
  }, inst);
  pdf.table(["Application No", "Surname", "Other names", "Sex", "Date of birth", "Programme", "Combination", "Subjects", "Class", "JUPEB Exam No"],
    d.rows.map((r) => [r.application_no, r.surname.toUpperCase(), `${r.first_name}${r.middle_name ? ` ${r.middle_name}` : ""}`, r.sex === "F" ? "F" : r.sex === "M" ? "M" : "-",
      r.date_of_birth ? formatDocDate(r.date_of_birth, inst) : "-", r.stream ? streamLabel(r.stream) : "-", r.combination_code ?? "-", (r.subject_codes ?? []).join(", "), r.class_name ?? "-", r.exam_no ?? ""]),
    { serial: true });
  pdf.space(8);
  pdf.paragraph(`${d.rows.length} candidate${d.rows.length === 1 ? "" : "s"}. Return the list with the JUPEB examination number of each candidate against their application number; the JUPEB Office uploads it on the portal, matched by application number.`, 9);
  if (d.notRegistered) pdf.paragraph(`${d.notRegistered} active student${d.notRegistered === 1 ? " has" : "s have"} not yet registered their subjects and ${d.notRegistered === 1 ? "is" : "are"} not on this list.`, 9);
  pdf.signatures([{ designation: "Prepared by (JUPEB Office)" }, { designation: "Programme Director" }]);
  const bytes = pdf.finish();
  return new NextResponse(Buffer.from(bytes), {
    status: 200,
    headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="jupeb-exam-number-list-${d.session.replace("/", "-")}.pdf"`, "cache-control": "no-store" },
  });
}
