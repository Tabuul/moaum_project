import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import { loadInstitution } from "@/lib/document/institution-server";
import { formatDocDateTime } from "@/lib/document/institution";
import { PdfDocument } from "@/lib/document/pdf";
import { PAID_HEAD, paidFileName, paidHeading, paidLine, paidPath, readPaidFilters, type PaidExport } from "@/lib/paid-applicants";

export const dynamic = "force-dynamic";

/** the PDF engine draws ASCII: the dashes and dots of the report's words are said in plain characters */
const plain = (s: string) => s.replace(/[—–]/g, "-").replace(/·/g, ";").replace(/[‘’]/g, "'");

/**
 * /admissions/paid-applicants/pdf — the Post-UTME paid applicants report (V479) as a PDF on the University's letterhead,
 * landscape: the title, the session, the filters, when and by whom, the total; the eight columns, the header repeated on
 * every page, S/N running on from 1, "Page X of Y" in the footer. The rows come from the report's own export endpoint,
 * which holds the office's scope and records the download.
 */
export async function GET(req: Request) {
  const f = readPaidFilters(Object.fromEntries(new URL(req.url).searchParams));
  if (!f.session) return NextResponse.json({ status: 400, title: "Choose the admission session." }, { status: 400 });
  const inst = await loadInstitution();
  const res = await api<PaidExport>(`${paidPath(f.session)}/export`, {
    method: "POST",
    reason: `Paid Post-UTME applicants of ${f.session} downloaded (PDF)`,
    body: {
      format: "PDF", status: f.status || undefined, fac: f.fac || undefined, dept: f.dept || undefined, prog: f.prog || undefined, sex: f.sex || undefined,
      entry: f.entry || undefined, from: f.from || undefined, to: f.to || undefined, jamb: f.jamb || undefined, q: f.q || undefined,
    },
  });
  if (!res.ok) return NextResponse.json(res.problem, { status: res.problem.status || 500 });
  const d = res.data;
  const h = paidHeading(f, d.labels, d.total, d.generatedBy, formatDocDateTime(new Date(), inst));
  const pdf = new PdfDocument("BROADSHEET", {
    title: plain(h.title),
    subtitle: plain(h.sub),
    unit: "Academic Office - Admissions",
    meta: h.meta.map(([k, v]) => [plain(k), plain(v)] as [string, string]),
    generatedBy: d.generatedBy,
    confidentiality: "CONFIDENTIAL - CONTAINS APPLICANTS' CONTACT DETAILS",
  }, inst);
  // after S/N (26 points): JAMB number, name, programme, gender, aggregate, phone, e-mail — the landscape page's 770 points,
  // at 7 points so a long programme name and "NOT AVAILABLE (DIRECT ENTRY)" fit their columns
  pdf.table(PAID_HEAD, d.rows.map((r) => paidLine(r).map((c) => (typeof c === "string" ? plain(c) : c))),
    { serial: true, size: 7, widths: [84, 150, 170, 38, 106, 62, 134], numeric: [false, false, false, false, false, false, false] });
  pdf.space(8);
  pdf.paragraph(`${d.total.toLocaleString("en-GB")} applicant${d.total === 1 ? "" : "s"}. Paid means an application-fee payment the payment service confirmed; a reversal by the Bursary undoes it. The UTME aggregate is JAMB's, never computed; a Direct Entry candidate sat no UTME. A value the record does not hold reads NOT AVAILABLE.`, 8.5);
  const bytes = pdf.finish();
  return new NextResponse(Buffer.from(bytes), {
    status: 200,
    headers: { "content-type": "application/pdf", "content-disposition": `attachment; filename="${paidFileName(f, "pdf")}"`, "cache-control": "no-store" },
  });
}
