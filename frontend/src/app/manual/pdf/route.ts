import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import type { Me } from "@/components/proto/Shell";
import { loadInstitution } from "@/lib/document/institution-server";
import { PdfDocument } from "@/lib/document/pdf";
import { byCategory, dayOf, paper, readerLabel, readerMenus, type ManualView } from "@/lib/manual";
import { readerMenu } from "../page";

export const dynamic = "force-dynamic";

const clean = (s: unknown) => String(s ?? "").replace(/[^\x20-\x7E]/g, " ").replace(/\s+/g, " ").trim();

/** V387: the person's Quick Operational Manual as a branded PDF — the role, the edition, a contents list, then every procedure
 *  of their office as purpose, numbered steps and the expected result; page numbers from the document profile */
export async function GET(req: Request) {
  const inst = await loadInstitution();
  const me = await api<Me>("/api/v1/iam/me");
  if (!me.ok) return NextResponse.json(me.problem, { status: me.problem.status });
  const asked = new URL(req.url).searchParams.get("menu");
  const menu = (asked && /^[a-z]+$/.test(asked) ? asked : null) ?? (await readerMenu(me.data));
  const office = me.data.activeOffice ?? null;
  const data = await api<ManualView>(`/api/v1/manual${menu ? `?menu=${encodeURIComponent(menu)}` : ""}`);
  if (!data.ok) return NextResponse.json(data.problem, { status: data.problem.status });
  const d = data.data;
  const menus = readerMenus(office, menu);
  const label = readerLabel(office, menu);
  const groups = byCategory(d.procedures);
  const pdf = new PdfDocument("STANDARD_REPORT", {
    title: "Quick Operational Manual",
    subtitle: `${clean(label)} - Edition ${d.edition.version}`,
    unit: clean(label),
    meta: [["Role", clean(label)], ["Office", clean(office)], ["Edition", d.edition.version], ["Last updated", dayOf(d.edition.updated_at)], ["Procedures", String(d.procedures.length)]],
    generatedBy: clean(me.data.name ?? me.data.actorId),
  }, inst);
  pdf.paragraph("What to click, what to enter, what to confirm and what to expect. Menu and button names are the portal's own at the time of generation; the dashboard always carries the current edition.", 9);
  if (d.procedures.length > 6) {
    pdf.space(6);
    pdf.heading("Contents");
    let n = 0;
    for (const g of groups) for (const p of g.rows) pdf.paragraph(`${++n}. ${clean(p.title)}  -  ${g.word}`, 9, 1.25);
  }
  for (const g of groups) {
    pdf.space(10);
    pdf.heading(g.word.toUpperCase(), 11);
    for (const p of g.rows) {
      pdf.ensure(90);
      pdf.space(4);
      pdf.heading(clean(p.title));
      pdf.paragraph(`Purpose: ${clean(p.purpose)}`, 9.5);
      p.steps.forEach((s, i) => pdf.paragraph(`${i + 1}. ${clean(paper(s, menus))}`, 9.5, 1.3));
      pdf.paragraph(`Expected result: ${clean(p.expected)}`, 9.5);
    }
  }
  if (!d.procedures.length) pdf.paragraph("No procedure is published for this office yet.", 9.5);
  const bytes = pdf.finish();
  await api("/api/v1/manual/views", { method: "POST", body: { kind: "PDF" } });
  return new NextResponse(Buffer.from(bytes), {
    status: 200,
    headers: { "content-type": "application/pdf", "content-disposition": `attachment; filename="quick-operational-manual-${(menu ?? office ?? "portal").replace(/[^a-z0-9]/gi, "-")}.pdf"`, "cache-control": "no-store" },
  });
}
