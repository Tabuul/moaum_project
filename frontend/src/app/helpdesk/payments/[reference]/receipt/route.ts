import { NextResponse } from "next/server";
import { api, API_URL } from "@/lib/api";
import { sessionToken } from "@/lib/session";
import type { Receipt } from "@/lib/student-portal";
import { loadInstitution } from "@/lib/document/institution-server";
import { receiptPdf, receiptPhoto } from "@/lib/receipt-pdf";

export const dynamic = "force-dynamic";

/**
 * /helpdesk/payments/{reference}/receipt — VIEW RECEIPT from the payment support desk (V346): the student's own receipt,
 * drawn by the same function from the same facts, for a confirmed payment of a student within the agent's reach. The
 * support API decides who may read it; nothing here is a second receipt.
 */
export async function GET(req: Request, { params }: { params: Promise<{ reference: string }> }) {
  await loadInstitution();
  const { reference } = await params;
  const r = await api<Receipt & { studentId: string }>(`/api/v1/helpdesk/support/payments/${encodeURIComponent(reference)}/receipt`);
  if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status });
  const x = r.data;
  let photo: ReturnType<typeof receiptPhoto> = null;
  try {
    const tok = await sessionToken();
    const res = await fetch(`${API_URL}/api/v1/helpdesk/support/students/${encodeURIComponent(x.studentId)}/passport`, { headers: tok ? { Authorization: `Bearer ${tok}` } : {}, cache: "no-store" });
    if (res.ok) photo = receiptPhoto(new Uint8Array(await res.arrayBuffer()));
  } catch { /* leave the box blank */ }
  const bytes = receiptPdf(req, x, photo);
  return new NextResponse(Buffer.from(bytes), {
    status: 200,
    headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="receipt-${(x.receipt_no ?? "").replace(/\//g, "-")}.pdf"`, "cache-control": "no-store" },
  });
}
