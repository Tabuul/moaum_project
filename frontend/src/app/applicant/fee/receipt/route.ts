import { NextResponse } from "next/server";
import { api } from "@/lib/api";
import { admissionReceiptPdf, type AdmissionReceipt } from "@/lib/admission-receipt-pdf";
import { originOf } from "@/lib/receipt-pdf";
import { loadInstitution } from "@/lib/document/institution-server";

export const dynamic = "force-dynamic";

/** the receipt of an applicant's fee (the Post-UTME application fee, admission checking or acceptance) as a PDF, from the applicant's dashboard (V282),
 *  titled for the fee and carrying the QR to its verification page */
export async function GET(req: Request) {
  await loadInstitution();
  const url = new URL(req.url);
  const reference = url.searchParams.get("reference") ?? "";
  if (!reference) return NextResponse.json({ status: 400, title: "Which receipt?", detail: "Name the payment reference." }, { status: 400 });
  const r = await api<AdmissionReceipt>(`/api/v1/applicant/me/receipts/${encodeURIComponent(reference)}`);
  if (!r.ok) return NextResponse.json(r.problem, { status: r.problem.status });
  const bytes = admissionReceiptPdf(r.data, originOf(req));
  const download = url.searchParams.get("download") === "1";
  return new NextResponse(Buffer.from(bytes), { status: 200, headers: { "content-type": "application/pdf", "content-disposition": `${download ? "attachment" : "inline"}; filename="receipt-${reference.replace(/[^A-Za-z0-9]+/g, "-")}.pdf"` } });
}
