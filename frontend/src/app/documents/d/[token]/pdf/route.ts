import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import { verifyPathFor, type Statement, type Template } from "@/lib/documents";
import { documentPdf, originOf } from "@/lib/document-pdf";

export const dynamic = "force-dynamic";

/** the document behind a recipient's secure link, as a PDF; every opening spends the token and is logged */
export async function GET(request: Request, { params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const t = token.replace(/[^a-f0-9]/gi, "").toLowerCase();
  const r = await api<{ result: string; template: string | null }>(`/api/v1/verify/download/${encodeURIComponent(t)}`);
  if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status });
  const c = JSON.parse(r.data.result) as { ok: boolean; why?: string; statement?: Statement; code?: string; number?: string };
  if (!c.ok || !c.statement) return NextResponse.json({ status: 410, title: `This link is ${(c.why ?? "not valid").toLowerCase()}` }, { status: 410 });
  const tpl = r.data.template ? (JSON.parse(r.data.template) as Template) : null;
  const bytes = documentPdf(c.statement, tpl, `${originOf(request)}${verifyPathFor(c.code ?? "")}`, c.code ?? "", "ACTIVE");
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="${(c.number ?? "document").replace(/[\/\s]/g, "-")}.pdf"`, "cache-control": "private, no-store" } });
}
