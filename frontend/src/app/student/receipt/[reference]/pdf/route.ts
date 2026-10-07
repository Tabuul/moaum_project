import { NextResponse } from "next/server";
import { api, API_URL } from "@/lib/api";
import { sessionToken } from "@/lib/session";
import type { Receipt } from "@/lib/student-portal";
import { loadInstitution } from "@/lib/document/institution-server";
import { receiptPdf, receiptPhoto } from "@/lib/receipt-pdf";

export const dynamic = "force-dynamic";

/** the official payment receipt as a PDF: the same facts as the screen, on one A4 page */
export async function GET(req: Request, { params }: { params: Promise<{ reference: string }> }) {
  await loadInstitution();
  const { reference } = await params;
  const r = await api<Receipt>(`/api/v1/me/fees/receipts/${encodeURIComponent(reference)}`);
  if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status });
  const x = r.data;
  if (!x.confirmed_at) return NextResponse.json({ status: 409, title: "Not confirmed", detail: "A receipt is issued when the payment is confirmed." }, { status: 409 });
  // the student's passport, embedded as JPEG (blank box when none) — from /me/passport, which resolves
  // the document store OR the JAMB/attachment store, so a migrated / JAMB-loaded photo also prints
  let photo: ReturnType<typeof receiptPhoto> = null;
  try {
    const tok = await sessionToken();
    const res = await fetch(`${API_URL}/api/v1/me/passport`, { headers: tok ? { Authorization: `Bearer ${tok}` } : {}, cache: "no-store" });
    if (res.ok) photo = receiptPhoto(new Uint8Array(await res.arrayBuffer()));
  } catch { /* leave the box blank */ }
  const bytes = receiptPdf(req, x, photo);
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `inline; filename="receipt-${(x.receipt_no ?? "").replace(/\//g, "-")}.pdf"` } });
}
