import { NextResponse } from "next/server";
import { api, API_URL } from "@/lib/api";
import { sessionToken } from "@/lib/session";
import type { Receipt } from "@/lib/student-portal";
import { loadInstitution } from "@/lib/document/institution-server";
import { receiptPdf, receiptPhoto } from "@/lib/receipt-pdf";

export const dynamic = "force-dynamic";

/**
 * /students/{id}/receipt/{reference}/pdf — the receipt as the University's PDF, drawn by the student's own receipt function from
 * the same facts; the API decides who may read it (fees, the office's reach, the reference this student's), as for the window.
 */
export async function GET(req: Request, { params }: { params: Promise<{ id: string; reference: string }> }) {
  await loadInstitution();
  const { id, reference } = await params;
  const r = await api<Receipt>(`/api/v1/student/students/${encodeURIComponent(id)}/full/receipts/${encodeURIComponent(reference)}`);
  if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status });
  const x = r.data;
  let photo: ReturnType<typeof receiptPhoto> = null;
  try {
    const tok = await sessionToken();
    const res = await fetch(`${API_URL}/api/v1/student/students/${encodeURIComponent(id)}/passport`, { headers: tok ? { Authorization: `Bearer ${tok}` } : {}, cache: "no-store" });
    if (res.ok) photo = receiptPhoto(new Uint8Array(await res.arrayBuffer()));
  } catch { /* leave the box blank */ }
  const bytes = receiptPdf(req, x, photo);
  return new NextResponse(Buffer.from(bytes), {
    status: 200,
    headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="receipt-${(x.receipt_no ?? "").replace(/\//g, "-")}.pdf"`, "cache-control": "no-store" },
  });
}
