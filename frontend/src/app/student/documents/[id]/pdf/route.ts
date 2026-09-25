import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import { parseStatement, verifyPathFor, type DocumentFull } from "@/lib/documents";
import { documentPdf, originOf } from "@/lib/document-pdf";

export const dynamic = "force-dynamic";

/** the student's own document as a PDF (V262): rendered from the signed statement under the template it was issued with; the download is logged */
export async function GET(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const r = await api<DocumentFull>(`/api/v1/me/documents/${encodeURIComponent(id)}?download=true`);
  if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status });
  const d = r.data;
  const s = parseStatement(d.statement);
  if (!s) return NextResponse.json({ status: 500, title: "The document's statement could not be read" }, { status: 500 });
  const bytes = documentPdf(s, d.template, `${originOf(request)}${verifyPathFor(d.verification_code)}`, d.verification_code, d.status);
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="${(d.number ?? d.verification_code).replace(/[\/\s]/g, "-")}.pdf"`, "cache-control": "private, no-store" } });
}
