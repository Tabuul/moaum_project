import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import type { Receipt } from "@/lib/student-portal";
import { originOf } from "@/lib/receipt-pdf";
import { qrDataUrl, verifyPath } from "@/lib/qr";

export const dynamic = "force-dynamic";

/**
 * /students/{id}/receipt/{reference} — the official receipt for one confirmed payment of this student, for the full record's
 * receipt window: the student's own receipt facts (the API checks the office reads fees, the student is within its reach and the
 * reference is this student's) and the QR to the public verification page, made over the reference and the signed check code
 * only. Nothing here is a second receipt.
 */
export async function GET(req: Request, { params }: { params: Promise<{ id: string; reference: string }> }) {
  const { id, reference } = await params;
  const r = await api<Receipt>(`/api/v1/student/students/${encodeURIComponent(id)}/full/receipts/${encodeURIComponent(reference)}`);
  if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status });
  let qr: string | null = null, verifyUrl: string | null = null;
  if (r.data.checkCode) {
    verifyUrl = originOf(req) + verifyPath(r.data.reference, r.data.checkCode);
    qr = await qrDataUrl(verifyUrl);
  }
  return NextResponse.json({ receipt: r.data, qr, verifyUrl, token: r.data.checkCode ?? null }, { headers: { "cache-control": "no-store" } });
}
