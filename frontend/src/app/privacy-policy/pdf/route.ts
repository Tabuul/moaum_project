import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import { loadInstitution } from "@/lib/document/institution-server";
import { legalPdf, type LegalDocument } from "@/lib/legal";

export const dynamic = "force-dynamic";

/** the Privacy Policy as a PDF, from the portal's own document engine: letterhead, version, dates, page numbers, contact */
export async function GET(req: Request) {
  const url = new URL(req.url);
  const preview = url.searchParams.get("preview");
  const path = preview && /^[0-9a-f-]{36}$/i.test(preview) ? `/api/v1/privacy/admin/documents/${preview}/preview` : "/api/v1/public/legal/privacy-policy";
  const r = await api<LegalDocument>(path, { anonymous: path.startsWith("/api/v1/public/") });
  if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status });
  const inst = await loadInstitution();
  const bytes = legalPdf(r.data, inst);
  const name = `privacy-policy-v${r.data.version}${r.data.status === "PUBLISHED" ? "" : "-draft"}.pdf`;
  return new NextResponse(Buffer.from(bytes), { headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="${name}"` } });
}
