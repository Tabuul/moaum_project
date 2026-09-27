import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import { admissionReceiptPdf, type AdmissionReceipt } from "@/lib/admission-receipt-pdf";

export const dynamic = "force-dynamic";

/** the receipt of an admission fee (checking or acceptance) as a PDF, from the student's library (V282) */
export async function GET(req: Request) {
  const url = new URL(req.url);
  const reference = url.searchParams.get("reference") ?? "";
  if (!reference) return NextResponse.json({ status: 400, title: "Which receipt?", detail: "Name the payment reference." }, { status: 400 });
  const r = await api<AdmissionReceipt>(`/api/v1/me/admission-documents/receipts/${encodeURIComponent(reference)}`);
  if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status });
  const bytes = admissionReceiptPdf(r.data);
  const download = url.searchParams.get("download") === "1";
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `${download ? "attachment" : "inline"}; filename="receipt-${reference.replace(/[^A-Za-z0-9]+/g, "-")}.pdf"` } });
}
