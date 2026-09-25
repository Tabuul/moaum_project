import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import { parseStatement, verifyPathFor, type DocumentFull } from "@/lib/documents";
import { documentPdf, originOf } from "@/lib/document-pdf";

export const dynamic = "force-dynamic";

/** an issued document as the office sees it; logged as an office download */
export async function GET(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const r = await api<DocumentFull>(`/api/v1/documents/issued/${encodeURIComponent(id)}/download`);
  if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status });
  const s = parseStatement(r.data.statement);
  if (!s) return NextResponse.json({ status: 500, title: "The document's statement could not be read" }, { status: 500 });
  const bytes = documentPdf(s, r.data.template, `${originOf(request)}${verifyPathFor(r.data.verification_code)}`, r.data.verification_code, r.data.status);
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="${(r.data.number ?? r.data.verification_code).replace(/[\/\s]/g, "-")}.pdf"`, "cache-control": "private, no-store" } });
}
