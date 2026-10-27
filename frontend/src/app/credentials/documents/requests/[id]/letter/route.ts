import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import type { CoverLetter, RequestFull } from "@/lib/documents";
import { coverLetterPdf } from "@/lib/document-pdf";

import { loadInstitution } from "@/lib/document/institution-server";

export const dynamic = "force-dynamic";

/** V668: the Transcript Desk's covering letter for a request to a recipient, to print with the transcript */
export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  await loadInstitution();
  const { id } = await params;
  const r = await api<RequestFull>(`/api/v1/documents/requests/${encodeURIComponent(id)}`);
  if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status });
  if (!r.data.coverLetter) return NextResponse.json({ status: 404, title: "A covering letter is written only for a copy sent to a recipient" }, { status: 404 });
  const letter = JSON.parse(r.data.coverLetter) as CoverLetter;
  const bytes = coverLetterPdf(letter);
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="letter-${letter.requestRef.replace(/[\/\s]/g, "-")}.pdf"`, "cache-control": "private, no-store" } });
}
